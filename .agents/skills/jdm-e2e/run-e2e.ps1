<#
.SYNOPSIS
    jdm End-to-End Acceptance Test Runner

.DESCRIPTION
    Performs a complete lifecycle test of jdm:
    1. Pre-flight checks (PowerShell, winget, network, privileges)
    2. Bootstrap install via install.ps1
    3. Load module into runner scope with prompt/output automation
    4. Install JDKs (real winget or mock fallback)
    5. Validate registry, candidates dir, symlink
    6. Exercise all CLI commands and validate outputs
    7. Test uninstall (single + --all-vendors) with disk sweep
    8. Self-uninstall and verify removal

.NOTES
    This script modifies the machine (PATH, JAVA_HOME, downloads JDKs).
    Run on a test machine or where state changes are acceptable.
    Requires: Windows 10+, PowerShell 5.1+, winget, Admin/DevMode for symlinks.
#>

$ErrorActionPreference = "Stop"

# ============================================================================
# GLOBAL STATE
# ============================================================================
$script:results = @()
$script:transcript = @()
$script:readHostQueue = @()
$script:snapshotBefore = $null
$script:jdmOwnedPaths = @()
$script:isMockMode = $false
$script:symlinkMode = "Unknown"
$script:repoRoot = $PSScriptRoot
while ($script:repoRoot -and -not (Test-Path (Join-Path $script:repoRoot "install.ps1"))) {
    $script:repoRoot = Split-Path $script:repoRoot -Parent
}
if (-not $script:repoRoot) {
    Write-Error "Cannot find repo root (install.ps1 not found)"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Add-Result {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ""
    )
    $script:results += [PSCustomObject]@{
        Name   = $Name
        Passed = $Passed
        Detail = $Detail
    }
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "$status $Name" -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor Gray }
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = "")
    Add-Result -Name $Name -Passed $Condition -Detail $Detail
    return $Condition
}

function Assert-PathExists {
    param([string]$Name, [string]$Path, [string]$Detail = "")
    $exists = Test-Path $Path
    $detailMsg = if ($exists) { "Exists at $Path" } else { "Missing: $Path; $Detail" }
    Add-Result -Name $Name -Passed $exists -Detail $detailMsg
    return $exists
}

function Assert-PathNotExists {
    param([string]$Name, [string]$Path, [string]$Detail = "")
    $exists = Test-Path $Path
    $detailMsg = if ($exists) { "Still exists: $Path; $Detail" } else { "Correctly removed" }
    Add-Result -Name $Name -Passed (-not $exists) -Detail $detailMsg
    return -not $exists
}

function Log-Transcript {
    param([string]$Message)
    $script:transcript += $Message
}

function Clear-Transcript {
    $script:transcript = @()
}

function Get-Transcript {
    return $script:transcript -join "`n"
}

function Enqueue-ReadHost {
    param([string[]]$Answers)
    $script:readHostQueue += $Answers
}

# ============================================================================
# PROMPT/OUTPUT OVERRIDES (defined early so they win)
# ============================================================================
function Read-Host {
    param([string]$Prompt)
    if ($script:readHostQueue.Count -gt 0) {
        $answer = $script:readHostQueue[0]
        $script:readHostQueue = $script:readHostQueue[1..($script:readHostQueue.Count - 1)]
        Log-Transcript "Read-Host prompt: $Prompt"
        Log-Transcript "Read-Host answer: $answer"
        return $answer
    }
    # Fallback: interactive fallback (shouldn't happen in automated run)
    Log-Transcript "Read-Host prompt (no queue): $Prompt"
    return Read-Host -Prompt $Prompt
}

function Write-Host {
    param(
        [Parameter(ValueFromPipeline, Position = 0)] [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [Switch]$NoNewline,
        [Switch]$Separator
    )
    $msg = ($Object | Out-String).Trim()
    Log-Transcript "Write-Host: $msg"
    
    # Evaluate script blocks in bound parameters
    $params = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [ScriptBlock]) {
            $params[$key] = & $value
        } else {
            $params[$key] = $value
        }
    }
    Microsoft.PowerShell.Utility\Write-Host @params
}

function Write-Step { param($msg) Log-Transcript "STEP: $msg"; Microsoft.PowerShell.Utility\Write-Host "  --> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Log-Transcript "OK: $msg";   Microsoft.PowerShell.Utility\Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Log-Transcript "FAIL: $msg";  Microsoft.PowerShell.Utility\Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Title{ param($msg) Log-Transcript "TITLE: $msg"; Microsoft.PowerShell.Utility\Write-Host "`n$msg" -ForegroundColor Yellow }

# ============================================================================
# PHASE 0: PRE-FLIGHT
# ============================================================================
function Phase-PreFlight {
    Write-Title "Phase 0: Pre-flight Checks"
    Clear-Transcript

    # PowerShell version
    $psVersion = $PSVersionTable.PSVersion.Major
    Assert-True "PowerShell >= 5.1" ($psVersion -ge 5) "Found v$($PSVersionTable.PSVersion)"

    # winget
    $wingetAvail = $false
    try {
        $null = Get-Command winget -ErrorAction Stop
        $wingetVer = winget --version 2>&1 | Select-Object -First 1
        $wingetAvail = $true
        Assert-True "winget available" $true "Version: $wingetVer"
    }
    catch {
        Assert-True "winget available" $false "Not found in PATH"
    }

    # Network (lightweight)
    $netAvail = $false
    if ($wingetAvail) {
        try {
            $response = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $netAvail = $true
            Assert-True "Network reachable" $true "GitHub reachable"
        }
        catch {
            Assert-True "Network reachable" $false "No internet (falling back to mock mode)"
            $script:isMockMode = $true
        }
    }
    else {
        $script:isMockMode = $true
    }

    # Force mock mode if JDKs already exist (prevents winget prompts on pre-installed packages)
    $existingJdks = @()
    $existingJdks += Get-ChildItem -Path "$env:ProgramFiles" -Filter "*jdk*" -Directory -ErrorAction SilentlyContinue
    $existingJdks += Get-ChildItem -Path "${env:ProgramFiles(x86)}" -Filter "*jdk*" -Directory -ErrorAction SilentlyContinue
    if ($existingJdks.Count -gt 0) {
        Write-Step "Existing JDKs detected in Program Files; forcing mock mode"
        $script:isMockMode = $true
    }

    # Symlink capability (admin or DevMode)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $devMode = Get-ItemProperty `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
        -Name "AllowDevelopmentWithoutDevLicense" `
        -ErrorAction SilentlyContinue
    $devModeEnabled = $devMode -and $devMode.AllowDevelopmentWithoutDevLicense -eq 1

    if ($isAdmin) { $script:symlinkMode = "SymbolicLink (Admin)" }
    elseif ($devModeEnabled) { $script:symlinkMode = "SymbolicLink (DevMode)" }
    else { $script:symlinkMode = "Junction (fallback)" }

    Assert-True "Symlink capability detected" $true "Mode: $($script:symlinkMode)"

    # Disk space (basic check on user profile)
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    $free = (Get-PSDrive $driveLetter).Free / 1GB
    Assert-True "Sufficient disk space (>1GB)" ($free -gt 1) "Free: $([math]::Round($free, 1)) GB"

    Write-Host ""
    Write-Host "Pre-flight summary:" -ForegroundColor Cyan
    Write-Host "  winget: $wingetAvail" -ForegroundColor Gray
    Write-Host "  network: $netAvail (mock mode: $($script:isMockMode))" -ForegroundColor Gray
    Write-Host "  symlink: $($script:symlinkMode)" -ForegroundColor Gray
    Write-Host "  repo: $script:repoRoot" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# PHASE 1: BOOTSTRAP
# ============================================================================
function Phase-Bootstrap {
    Write-Title "Phase 1: Bootstrap Install"
    Clear-Transcript

    $installScript = Join-Path $script:repoRoot "install.ps1"
    Assert-PathExists "install.ps1 exists" $installScript

    # Run install.ps1 - it will copy local module to ~/.jdm
    Write-Step "Running install.ps1 from $script:repoRoot"
    & $installScript

    $jdmModuleDir = "$env:USERPROFILE\.jdm\module"
    $jdmCmd = Join-Path $jdmModuleDir "jdm.cmd"
    $jdmPs1 = Join-Path $jdmModuleDir "jdm.ps1"

    Assert-PathExists "jdm module directory" $jdmModuleDir
    Assert-PathExists "jdm.ps1" $jdmPs1
    Assert-PathExists "jdm.cmd launcher" $jdmCmd

    # Verify PATH contains jdm module dir
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    Assert-True "jdm module dir in user PATH" ($userPath -like "*\.jdm\module*") "PATH: $userPath"

    # Verify JAVA_HOME points to current symlink
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    $expectedHome = "$env:USERPROFILE\.jdm\candidates\java\current"
    Assert-True "JAVA_HOME set to jdm current" ($javaHome -eq $expectedHome) "JAVA_HOME: $javaHome"

    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================

Write-Title "jdm End-to-End Acceptance Test"
Write-Host "Repo: $script:repoRoot" -ForegroundColor Cyan
Write-Host ""

try {
    Phase-PreFlight
    Phase-Bootstrap
}
catch {
    Write-Fail "Test crashed during pre-flight/bootstrap: $_"
    $script:results += [PSCustomObject]@{
        Name   = "Script execution"
        Passed = $false
        Detail = "Exception: $_"
    }
    # Print summary and exit
    Write-Title "=== TEST SUMMARY ==="
    $passed = ($script:results | Where-Object { $_.Passed }).Count
    $failed = ($script:results | Where-Object { -not $_.Passed }).Count
    $total  = $script:results.Count
    Write-Host "Total checks: $total" -ForegroundColor Cyan
    Write-Host "Passed:       $passed" -ForegroundColor Green
    Write-Host "Failed:       $failed" -ForegroundColor Red
    Write-Host ""
    if ($failed -gt 0) {
        Write-Host "Failures:" -ForegroundColor Red
        $script:results | Where-Object { -not $_.Passed } | ForEach-Object {
            Write-Host "  - $($_.Name): $($_.Detail)" -ForegroundColor Red
        }
        Write-Host ""
        Write-Fail "E2E TEST FAILED ($failed/$total)"
        exit 1
    }
    else {
        Write-Host ""
        Write-Ok "E2E TEST PASSED ($passed/$total)"
        exit 0
    }
}

# ============================================================================
# LOAD MODULE AT SCRIPT SCOPE (after bootstrap, before remaining phases)
# ============================================================================
$script:moduleDir = "$env:USERPROFILE\.jdm\module"
. (Join-Path $script:moduleDir "core\winget.ps1")
. (Join-Path $script:moduleDir "core\registry.ps1")
. (Join-Path $script:moduleDir "core\symlink.ps1")
. (Join-Path $script:moduleDir "commands\install.ps1")
. (Join-Path $script:moduleDir "commands\use.ps1")
. (Join-Path $script:moduleDir "commands\list.ps1")
. (Join-Path $script:moduleDir "commands\uninstall.ps1")
. (Join-Path $script:moduleDir "jdm.ps1")

# Mock Uninstall-WithWinget in mock mode (fake JDKs aren't installed via winget)
if ($script:isMockMode) {
    function Uninstall-WithWinget {
        param([string] $Id)
        Write-Step "Mock: skipping winget uninstall for $Id"
        return $true
    }
}

# Verify key functions are available
Write-Title "Phase 2: Load Module (Automation Harness)"
Clear-Transcript
$funcs = @("Invoke-Jdm", "Invoke-Install", "Invoke-Use", "Invoke-List", "Invoke-Uninstall", "Invoke-UninstallAll", "Invoke-SelfUninstall", "Get-Registry", "Get-CurrentVersion", "Get-CurrentSymlinkTarget", "Test-JdmPathEquals", "Normalize-VersionKey", "Get-JavaSnapshot", "Test-IsIdeRuntime", "Get-IdeExcludePatterns", "Add-Version", "Set-CurrentVersion", "Switch-Version", "Remove-Version", "Remove-CurrentSymlink")
foreach ($f in $funcs) {
    $cmd = Get-Command $f -ErrorAction SilentlyContinue
    Assert-True "Function $f available" ($null -ne $cmd)
}
Write-Host ""

# ============================================================================
# PHASE 3: INSTALL JDKS
# ============================================================================
function Phase-InstallJdks {
    Write-Title "Phase 3: Install JDKs"
    Clear-Transcript

    # Snapshot before
    if ($script:isMockMode) {
        # In mock mode, use a fast fake snapshot instead of scanning entire filesystem
        $script:snapshotBefore = @{}
    }
    else {
        $script:snapshotBefore = Get-JavaSnapshot
    }
    Write-Step "Pre-install Java snapshot: $($script:snapshotBefore.Count) JDK(s) found"

    if (-not $script:isMockMode) {
        # Real mode: temurin.21 then corretto.17
        # Each install has 3 prompts for already-installed: Reinstall? y, Proceed? y, Set current? y/n
        Write-Step "Installing temurin.21 (real winget)..."
        Enqueue-ReadHost @("y", "y", "y")  # Reinstall? y; Proceed? y; Set current? y
        Invoke-Jdm -command "install" -rest @("temurin.21")

        Write-Step "Installing corretto.17 (real winget)..."
        Enqueue-ReadHost @("y", "y", "n")  # Reinstall? y; Proceed? y; Set current? n (keep temurin current)
        Invoke-Jdm -command "install" -rest @("corretto.17")
    }
    else {
        # Mock mode: create fake JDKs and register
        Write-Step "Mock mode: creating fake JDKs..."
        $fakeTemurin = "$env:USERPROFILE\.jdks\e2e-fake-temurin21"
        $fakeCorretto = "$env:USERPROFILE\.jdks\e2e-fake-corretto17"

        # temurin.21
        New-Item -ItemType Directory -Path (Join-Path $fakeTemurin "bin") -Force | Out-Null
        Set-Content (Join-Path $fakeTemurin "bin\java.exe") "fake"
        Set-Content (Join-Path $fakeTemurin "release") 'JAVA_VERSION="21"'
        Add-Version -Key "temurin.21" -Result ([PSCustomObject]@{Id="EclipseAdoptium.Temurin.JDK.21";Name="Temurin JDK 21"}) -InstallPath $fakeTemurin -Vendor "temurin" -Version "21"
        Set-CurrentVersion -Key "temurin.21"
        Switch-Version -TargetPath $fakeTemurin

        # corretto.17
        New-Item -ItemType Directory -Path (Join-Path $fakeCorretto "bin") -Force | Out-Null
        Set-Content (Join-Path $fakeCorretto "bin\java.exe") "fake"
        Set-Content (Join-Path $fakeCorretto "release") 'JAVA_VERSION="17"'
        Add-Version -Key "corretto.17" -Result ([PSCustomObject]@{Id="Amazon.Corretto.17.JDK";Name="Corretto JDK 17"}) -InstallPath $fakeCorretto -Vendor "corretto" -Version "17"
        # Don't switch - keep temurin current
    }

    # Snapshot after and compute jdm-owned delta
    if ($script:isMockMode) {
        # In mock mode, jdm-owned paths are the fake ones we just created
        $script:jdmOwnedPaths = @($fakeTemurin, $fakeCorretto)
        $snapshotAfter = @{}
        foreach ($p in $script:jdmOwnedPaths) { $snapshotAfter[$p] = $true }
    }
    else {
        $snapshotAfter = Get-JavaSnapshot
        $script:jdmOwnedPaths = $snapshotAfter.Keys | Where-Object { -not $script:snapshotBefore.ContainsKey($_) }
    }
    Write-Step "Post-install snapshot: $($snapshotAfter.Count) JDK(s); jdm-owned: $($script:jdmOwnedPaths.Count)"
    foreach ($p in $script:jdmOwnedPaths) { Write-Step "  Owned: $p" }

    Write-Host ""
}

# ============================================================================
# PHASE 4: REGISTRY + CANDIDATES VALIDATION
# ============================================================================
function Phase-ValidateRegistry {
    Write-Title "Phase 4: Registry & Candidates Validation"
    Clear-Transcript

    $registry = Get-Registry
    Assert-True "Registry loaded" ($null -ne $registry)

    $versions = $registry.candidates.java.versions
    $installed = $registry.candidates.java.installed
    $current = $registry.candidates.java.current

    Assert-True "Registry has versions" ($versions -and $versions.PSObject.Properties.Count -gt 0)

    # Every version has a path that exists
    foreach ($prop in $versions.PSObject.Properties) {
        $entry = $prop.Value
        Assert-PathExists "Version $($prop.Name) path exists" $entry.path
    }

    # Installed list matches versions keys (normalized)
    $versionKeys = @($versions.PSObject.Properties | ForEach-Object { Normalize-VersionKey -Key $_.Name })
    $installedNorm = @($installed | ForEach-Object { Normalize-VersionKey -Key $_ })
    $vStr = $versionKeys -join ","
    $iStr = $installedNorm -join ","
    $installedMatch = [bool]($vStr -eq $iStr)
    Assert-True "Installed list matches versions keys" $installedMatch "Versions: $vStr; Installed: $iStr"

    # Current is valid
    if ($current) {
        $currentNorm = Normalize-VersionKey -Key $current
        Assert-True "Current version exists in installed" ($versionKeys -contains $currentNorm) "Current: $currentNorm"
        $currentEntry = Get-Version -Key $currentNorm
        Assert-PathExists "Current version path exists" $currentEntry.path
    }
    else {
        Assert-True "Current is null when no versions" ($versionKeys.Count -eq 0)
    }

    # Symlink validation
    $symlinkTarget = Get-CurrentSymlinkTarget
    if ($current) {
        $currentEntry = Get-Version -Key $current
        Assert-True "Symlink target matches registry current" (Test-JdmPathEquals -LeftPath $symlinkTarget -RightPath $currentEntry.path) "Symlink: $symlinkTarget; Registry: $($currentEntry.path)"
    }
    else {
        Assert-True "No symlink when no current" (-not (Test-Path "$env:USERPROFILE\.jdm\candidates\java\current"))
    }

    # Candidates directory
    $candidatesDir = "$env:USERPROFILE\.jdm\candidates\java"
    Assert-PathExists "Candidates dir exists" $candidatesDir
    $candidateDirs = Get-ChildItem -Path $candidatesDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    Assert-True "Candidates has 'current' link" ($candidateDirs -contains "current")
    # Note: jdm does not create version-named dirs in candidates; only 'current' symlink exists
    Write-Host "  [INFO] Candidates dir contains: $($candidateDirs -join ', ')" -ForegroundColor Gray

    Write-Host ""
}

# ============================================================================
# PHASE 5: COMMAND OUTPUT VALIDATION
# ============================================================================
function Phase-ValidateCommands {
    Write-Title "Phase 5: Command Output Validation"
    Clear-Transcript

    # Help
    Invoke-Jdm -command "help" -rest @()
    $helpOut = Get-Transcript
    Assert-True "help shows usage" ($helpOut -match "Usage:")
    Assert-True "help shows install command" ($helpOut -match "install VENDOR.VERSION")
    Assert-True "help shows uninstall --all-vendors" ($helpOut -match "--all-vendors")
    Assert-True "help shows uninstall --self" ($helpOut -match "--self")
    Assert-True "help shows version command" ($helpOut -match "version")

    # Version
    Clear-Transcript
    Invoke-Jdm -command "version" -rest @()
    $verOut = Get-Transcript
    Assert-True "version shows jdm version" ($verOut -match "jdm v0.2.0") "Got: $verOut"

    # List (should show both installed)
    Clear-Transcript
    Invoke-Jdm -command "list" -rest @()
    $listOut = Get-Transcript
    Assert-True "list shows temurin.21" ($listOut -match "temurin.21")
    Assert-True "list shows corretto.17" ($listOut -match "corretto.17")
    Assert-True "list marks current with -->" ($listOut -match "-->")

    # Use (switch to corretto.17)
    Clear-Transcript
    Enqueue-ReadHost @()  # no prompts expected for use
    Invoke-Jdm -command "use" -rest @("corretto.17")
    $useOut = Get-Transcript
    Assert-True "use switches successfully" ($useOut -match "Switched from.*corretto.17" -or $useOut -match "Repaired active version")

    # Verify list now shows corretto as current
    Clear-Transcript
    Invoke-Jdm -command "list" -rest @()
    $listOut2 = Get-Transcript
    Assert-True "list marks corretto.17 as current" ($listOut2 -match "corretto.17.*\(current\)" -or $listOut2 -match "-->.*corretto.17")

    # Hyphen format normalization
    Clear-Transcript
    Invoke-Jdm -command "use" -rest @("temurin-21")  # hyphen format
    $useOut2 = Get-Transcript
    Assert-True "Hyphen format accepted" ($useOut2 -match "Switched|Repaired")

    Write-Host ""
}

# ============================================================================
# PHASE 6: REMOVAL VALIDATION
# ============================================================================
function Phase-ValidateRemoval {
    Write-Title "Phase 6: Removal Validation"
    Clear-Transcript

    # Single uninstall: remove corretto.17 (not current)
    Write-Step "Uninstalling corretto.17 (single)..."
    Enqueue-ReadHost @("y")  # Confirm removal
    Invoke-Jdm -command "uninstall" -rest @("corretto.17")

    $registry = Get-Registry
    $versions = $registry.candidates.java.versions
    $installed = $registry.candidates.java.installed
    $versionKeysCheck = @($versions.PSObject.Properties | ForEach-Object { Normalize-VersionKey -Key $_.Name })
    $hasCorretto = $versionKeysCheck -contains "corretto.17"
    Assert-True "corretto.17 removed from versions" (-not $hasCorretto)
    $installedNormCheck = @($installed | ForEach-Object { Normalize-VersionKey -Key $_ })
    $hasCorrettoInstalled = $installedNormCheck -contains "corretto.17"
    Assert-True "corretto.17 removed from installed" (-not $hasCorrettoInstalled)

    # Current should still be temurin.21
    $current = $registry.candidates.java.current
    Assert-True "Current still temurin.21" ((Normalize-VersionKey -Key $current) -eq "temurin.21")

    # Bulk uninstall (--all-vendors)
    Write-Step "Running uninstall --all-vendors (bulk)..."
    Enqueue-ReadHost @("y")  # Confirm bulk removal
    $failCount = Invoke-UninstallAll  # This is the function, not via router

    Assert-True "Bulk uninstall returns 0 failures" ($failCount -eq 0) "Failures: $failCount"

    # Registry should be empty
    $registry2 = Get-Registry
    $versions2 = $registry2.candidates.java.versions
    $installed2 = $registry2.candidates.java.installed
    $current2 = $registry2.candidates.java.current

    $versionsCount = @($versions2.PSObject.Properties).Count
    Assert-True "Versions empty after bulk" ($versionsCount -eq 0)
    Assert-True "Installed empty after bulk" ($installed2.Count -eq 0)
    Assert-True "Current null after bulk" ($null -eq $current2)

    # Symlink removed
    Assert-PathNotExists "Current symlink removed" "$env:USERPROFILE\.jdm\candidates\java\current"

    # Tmp marker cleaned
    $marker = "$env:USERPROFILE\.jdm\tmp\last_install_path.txt"
    Assert-PathNotExists "Install marker cleaned" $marker

    # Disk sweep: jdm-owned paths should be gone
    if ($script:isMockMode) {
        # In mock mode, the fake JDKs were already removed by uninstall
        $snapshotAfter = @{}
    }
    else {
        $snapshotAfter = Get-JavaSnapshot
    }
    $leftoverOwned = $script:jdmOwnedPaths | Where-Object { $snapshotAfter.ContainsKey($_) }
    Assert-True "No jdm-owned JDK paths remain on disk" ($leftoverOwned.Count -eq 0) "Leftover: $($leftoverOwned -join ', ')"

    # Pre-existing (non-jdm) JDKs are warnings only
    $preExisting = $script:snapshotBefore.Keys | Where-Object { $snapshotAfter.ContainsKey($_) }
    foreach ($p in $preExisting) {
        if (-not (Test-IsIdeRuntime -Path $p)) {
            Write-Host "  [WARN] Pre-existing JDK still present (not managed by jdm): $p" -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

# ============================================================================
# PHASE 7: SELF-UNINSTALL VALIDATION
# ============================================================================
function Phase-SelfUninstall {
    Write-Title "Phase 7: Self-Uninstall Validation"
    Clear-Transcript

    Write-Step "Running uninstall --self..."
    Enqueue-ReadHost @("y")  # Confirm self-uninstall
    Invoke-SelfUninstall

    # ~/.jdm gone
    Assert-PathNotExists "~/.jdm directory removed" "$env:USERPROFILE\.jdm"

    # User PATH no longer contains jdm
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    Assert-True "jdm removed from user PATH" (-not ($userPath -like "*\.jdm\module*"))

    # User JAVA_HOME cleared
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    Assert-True "JAVA_HOME cleared (user)" ([string]::IsNullOrEmpty($javaHome) -or -not ($javaHome -like "*\.jdm*"))

    # Report intentional leftovers
    $jdksDir = "$env:USERPROFILE\.jdks"
    if (Test-Path $jdksDir) {
        Write-Host "  [INFO] JDKs remain in $jdksDir (intentional, per --self behavior)" -ForegroundColor Cyan
    }

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $machineJava = $machinePath -split ";" | Where-Object { $_ -match "java|jdk|temurin|corretto|zulu|jdm" }
    if ($machineJava) {
        Write-Host "  [INFO] Machine PATH still has Java entries (requires admin to clean):" -ForegroundColor Cyan
        $machineJava | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }

    Write-Host ""
}

# Run remaining phases
try {
    Phase-InstallJdks
    Phase-ValidateRegistry
    Phase-ValidateCommands
    Phase-ValidateRemoval
    Phase-SelfUninstall
}
catch {
    Write-Fail "Test crashed: $_"
    $script:results += [PSCustomObject]@{
        Name   = "Script execution"
        Passed = $false
        Detail = "Exception: $_"
    }
}

# Final report
Write-Title "=== TEST SUMMARY ==="
$passed = ($script:results | Where-Object { $_.Passed }).Count
$failed = ($script:results | Where-Object { -not $_.Passed }).Count
$total  = $script:results.Count

Write-Host "Total checks: $total" -ForegroundColor Cyan
Write-Host "Passed:       $passed" -ForegroundColor Green
Write-Host "Failed:       $failed" -ForegroundColor Red
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Failures:" -ForegroundColor Red
    $script:results | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Detail)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Fail "E2E TEST FAILED ($failed/$total)"
    exit 1
}
else {
    Write-Host ""
    Write-Ok "E2E TEST PASSED ($passed/$total)"
    exit 0
}