<# 
.SYNOPSIS
    End-to-end validation script for jdm Java Version Manager.
    Runs the full install/switch/uninstall/cleanup lifecycle non-interactively.

.DESCRIPTION
    This script executes the complete E2E test matrix defined in the jdm-e2e skill:
    1. Bootstrap jdm (./install.ps1)
    2. Install 3 JDKs (temurin.21, corretto.21, azul.21)
    3. Switch between versions and verify java -version
    4. Single uninstall + reinstall test (validates Option b fix)
    5. Bulk uninstall (--all-vendors)
    6. Full cleanup (user + machine level)

    All operations use -Force for non-interactive execution.
    Validation uses registry.json and Test-Path, not text scraping.

.PARAMETER Mode
    Privilege mode: 'Auto' (detect), 'Administrator', 'NonAdmin'

.PARAMETER OutputDir
    Directory for artifacts (JSON summary, logs)

.PARAMETER SkipCleanup
    Skip final cleanup step (for debugging)

.OUTPUTS
    Writes e2e_summary.json to OutputDir with structured results.
#>

param(
    [ValidateSet('Auto','Administrator','NonAdmin')]
    [string]$Mode = 'Auto',

    [string]$OutputDir = '.\artifacts\e2e',

    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'

# ─── Helpers ──────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    $global:logEntries += $line
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════"
    Write-Host "  $Title"
    Write-Host "═══════════════════════════════════════════"
    Write-Host ""
}

function Test-IsAdmin {
    try {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-DevModeEnabled {
    try {
        $devMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
        return ($devMode -and $devMode.AllowDevelopmentWithoutDevLicense -eq 1)
    }
    catch { return $false }
}

function Test-CanCreateSymlink {
    $tmpDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
    $target = Join-Path $tmpDir 'target'
    New-Item -Path $target -ItemType Directory | Out-Null
    $link = Join-Path $tmpDir 'link'
    try {
        New-Item -Path $link -ItemType SymbolicLink -Value $target -ErrorAction Stop | Out-Null
        $ok = Test-Path $link
    }
    catch { $ok = $false }
    finally { Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    return $ok
}

function Get-Registry {
    $path = "$env:USERPROFILE\.jdm\registry.json"
    if (-not (Test-Path $path)) { return $null }
    try { return Get-Content $path -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Get-InstalledKeys {
    $reg = Get-Registry
    if (-not $reg) { return @() }
    return @($reg.candidates.java.installed)
}

function Get-CurrentKey {
    $reg = Get-Registry
    if (-not $reg -or -not $reg.candidates.java.current) { return $null }
    return $reg.candidates.java.current
}

function Get-VersionPath {
    param([string]$Key)
    $reg = Get-Registry
    if (-not $reg) { return $null }
    $norm = $Key -replace '-', '.'
    $hyphen = $norm -replace '\.', '-'
    $versions = $reg.candidates.java.versions
    $entry = $versions.PSObject.Properties[$norm] ?? $versions.PSObject.Properties[$hyphen] ?? $versions.PSObject.Properties[$Key]
    return $entry?.Value?.path
}

function Run-Command {
    param([string]$Command, [string[]]$Args)
    Write-Log "EXEC: $Command $($Args -join ' ')"
    $p = Start-Process -FilePath $Command -ArgumentList $Args -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\jdm_e2e_stdout.txt" -RedirectStandardError "$env:TEMP\jdm_e2e_stderr.txt"
    $stdout = Get-Content "$env:TEMP\jdm_e2e_stdout.txt" -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content "$env:TEMP\jdm_e2e_stderr.txt" -Raw -ErrorAction SilentlyContinue
    if ($stdout) { Write-Log "STDOUT: $stdout" 'DEBUG' }
    if ($stderr) { Write-Log "STDERR: $stderr" 'DEBUG' }
    return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Assert-RegistryHasKey {
    param([string]$Key, [string]$Context)
    $keys = Get-InstalledKeys
    $norm = $Key -replace '-', '.'
    if ($keys -notcontains $norm -and $keys -notcontains $Key -and $keys -notcontains ($norm -replace '\.', '-')) {
        throw "ASSERT FAILED [$Context]: Registry missing key '$Key'. Found: $($keys -join ', ')"
    }
    Write-Log "✓ Registry has key: $Key" 'PASS'
}

function Assert-RegistryNotHasKey {
    param([string]$Key, [string]$Context)
    $keys = Get-InstalledKeys
    $norm = $Key -replace '-', '.'
    if ($keys -contains $norm -or $keys -contains $Key -or $keys -contains ($norm -replace '\.', '-')) {
        throw "ASSERT FAILED [$Context]: Registry should not have key '$Key'. Found: $($keys -join ', ')"
    }
    Write-Log "✓ Registry does not have key: $Key" 'PASS'
}

function Assert-PathExists {
    param([string]$Path, [string]$Context)
    if (-not (Test-Path $Path)) {
        throw "ASSERT FAILED [$Context]: Path does not exist: $Path"
    }
    Write-Log "✓ Path exists: $Path" 'PASS'
}

function Assert-PathNotExists {
    param([string]$Path, [string]$Context)
    if (Test-Path $Path) {
        throw "ASSERT FAILED [$Context]: Path should not exist: $Path"
    }
    Write-Log "✓ Path does not exist: $Path" 'PASS'
}

function Assert-JavaVersion {
    param([string]$ExpectedVendor, [string]$ExpectedVersion, [string]$Context)
    $javaOut = & java -version 2>&1
    $matched = $false
    switch -Wildcard ($ExpectedVendor.ToLower()) {
        'temurin' { $matched = $javaOut -match 'Temurin|Adoptium|Eclipse' }
        'corretto' { $matched = $javaOut -match 'Corretto|Amazon' }
        'azul' { $matched = $javaOut -match 'Zulu|Azul' }
        default { $matched = $javaOut -match $ExpectedVendor }
    }
    if (-not $matched) {
        throw "ASSERT FAILED [$Context]: java -version output does not match expected vendor '$ExpectedVendor'. Output: $javaOut"
    }
    if ($javaOut -notmatch $ExpectedVersion) {
        throw "ASSERT FAILED [$Context]: java -version output does not match expected version '$ExpectedVersion'. Output: $javaOut"
    }
    Write-Log "✓ java -version matches $ExpectedVendor $ExpectedVersion" 'PASS'
}

# ─── Main E2E Flow ────────────────────────────────────────────────

$global:logEntries = @()
$summary = [ordered]@{
    Timestamp     = (Get-Date).ToString('o')
    Mode          = $Mode
    Steps         = @()
    OverallResult = 'FAIL'
    Errors        = @()
}

try {
    # ─── Privilege Detection ──────────────────────────────────────
    Write-Section "Privilege Detection"
    $detected = 'NonAdmin'
    if (Test-IsAdmin) { $detected = 'Administrator' }
    elseif (Test-DevModeEnabled -or Test-CanCreateSymlink) { $detected = 'DevModeNonAdmin' }
    
    $selectedMode = if ($Mode -eq 'Auto') { $detected } else { $Mode }
    Write-Log "Detected: $detected | Selected: $selectedMode"
    $summary.Mode = $selectedMode

    # ─── Step 1: Bootstrap jdm ────────────────────────────────────
    Write-Section "Step 1: Bootstrap jdm (./install.ps1)"
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
    Set-Location $repoRoot
    
    $result = Run-Command 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\install.ps1')
    if ($result.ExitCode -ne 0) { throw "Bootstrap failed with exit code $($result.ExitCode)" }
    Write-Log "Bootstrap succeeded"

    # Verify jdm is on PATH
    $jdmTest = Run-Command 'jdm' @('version')
    if ($jdmTest.ExitCode -ne 0) { throw "jdm not on PATH after bootstrap" }
    Write-Log "✓ jdm command available"
    $summary.Steps += @{ Name = 'Bootstrap'; Result = 'PASS' }

    # ─── Step 2: Install 3 JDKs ───────────────────────────────────
    Write-Section "Step 2: Install 3 JDKs"
    $jdkMatrix = @(
        @{ Vendor = 'temurin'; Version = '21'; Key = 'temurin.21'; Id = 'EclipseAdoptium.Temurin.JDK.21' },
        @{ Vendor = 'corretto'; Version = '21'; Key = 'corretto.21'; Id = 'Amazon.Corretto.21' },
        @{ Vendor = 'azul'; Version = '21'; Key = 'azul.21'; Id = 'Azul.Zulu.21.JDK' }
    )

    foreach ($jdk in $jdkMatrix) {
        Write-Log "Installing $($jdk.Key)..."
        $result = Run-Command 'jdm' @('install', $jdk.Key, '-Force')
        if ($result.ExitCode -ne 0) { throw "Install $($jdk.Key) failed: $($result.StdErr)" }
        
        Assert-RegistryHasKey $jdk.Key "Install $($jdk.Key)"
        $path = Get-VersionPath $jdk.Key
        if (-not $path) { throw "Registry has $($jdk.Key) but no path found" }
        Assert-PathExists $path "Install $($jdk.Key) path"
    }
    $summary.Steps += @{ Name = 'Install3JDKs'; Result = 'PASS' }

    # ─── Step 3: Switch Loop ──────────────────────────────────────
    Write-Section "Step 3: Switch Between Versions"
    $switchSequence = @(
        @{ Key = 'temurin.21'; Vendor = 'temurin'; Version = '21' },
        @{ Key = 'corretto.21'; Vendor = 'corretto'; Version = '21' },
        @{ Key = 'azul.21'; Vendor = 'azul'; Version = '21' }
    )

    foreach ($switch in $switchSequence) {
        Write-Log "Switching to $($switch.Key)..."
        $result = Run-Command 'jdm' @('use', $switch.Key)
        if ($result.ExitCode -ne 0) { throw "Switch to $($switch.Key) failed: $($result.StdErr)" }
        
        # Verify registry current
        $current = Get-CurrentKey
        if ($current -ne $switch.Key -and $current -ne ($switch.Key -replace '\.', '-')) {
            throw "Registry current not updated to $($switch.Key). Current: $current"
        }
        Write-Log "✓ Registry current = $($switch.Key)"
        
        # Verify java -version
        Assert-JavaVersion $switch.Vendor $switch.Version "Switch to $($switch.Key)"
    }
    $summary.Steps += @{ Name = 'SwitchLoop'; Result = 'PASS' }

    # ─── Step 4: Single Uninstall + Reinstall (Option b test) ─────
    Write-Section "Step 4: Single Uninstall + Reinstall (corretto.21)"
    
    # Uninstall corretto.21
    Write-Log "Uninstalling corretto.21..."
    $result = Run-Command 'jdm' @('uninstall', 'corretto.21', '-Force')
    if ($result.ExitCode -ne 0) { throw "Uninstall corretto.21 failed: $($result.StdErr)" }
    
    Assert-RegistryNotHasKey 'corretto.21' 'Uninstall corretto.21'
    $path = Get-VersionPath 'corretto.21'
    if ($path) { Assert-PathNotExists $path 'Uninstall corretto.21 files' }
    
    # Reinstall corretto.21 (this tests Option b - winget uninstall was called)
    Write-Log "Reinstalling corretto.21..."
    $result = Run-Command 'jdm' @('install', 'corretto.21', '-Force')
    if ($result.ExitCode -ne 0) { throw "Reinstall corretto.21 failed: $($result.StdErr)" }
    
    Assert-RegistryHasKey 'corretto.21' 'Reinstall corretto.21'
    $path = Get-VersionPath 'corretto.21'
    if (-not $path) { throw "Registry has corretto.21 but no path found after reinstall" }
    Assert-PathExists $path 'Reinstall corretto.21 path'
    
    Write-Log "✓ Single uninstall + reinstall works (Option b validated)"
    $summary.Steps += @{ Name = 'SingleUninstallReinstall'; Result = 'PASS' }

    # ─── Step 5: Bulk Uninstall (--all-vendors) ───────────────────
    Write-Section "Step 5: Bulk Uninstall (--all-vendors)"
    $result = Run-Command 'jdm' @('uninstall', '--all-vendors', '-Force')
    if ($result.ExitCode -ne 0) { throw "Bulk uninstall failed: $($result.StdErr)" }
    
    # Verify registry empty
    $keys = Get-InstalledKeys
    if ($keys.Count -gt 0) { throw "Registry not empty after bulk uninstall: $($keys -join ', ')" }
    Write-Log "✓ Registry empty after bulk uninstall"
    
    # Verify no JDK dirs remain under user install root
    $userJdks = "$env:USERPROFILE\.jdks"
    if (Test-Path $userJdks) {
        $dirs = Get-ChildItem $userJdks -Directory -ErrorAction SilentlyContinue
        $jdkDirs = $dirs | Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') }
        if ($jdkDirs.Count -gt 0) {
            throw "JDK directories remain in $userJdks: $($jdkDirs.FullName -join ', ')"
        }
    }
    Write-Log "✓ No JDK dirs in ~/.jdks"
    
    # Verify symlink gone
    $symlink = "$env:USERPROFILE\.jdm\candidates\java\current"
    Assert-PathNotExists $symlink 'Bulk uninstall symlink'
    
    $summary.Steps += @{ Name = 'BulkUninstall'; Result = 'PASS' }

    # ─── Step 6: Final Cleanup ────────────────────────────────────
    if (-not $SkipCleanup) {
        Write-Section "Step 6: Final Cleanup"
        
        # Remove ~/.jdm
        $jdmDir = "$env:USERPROFILE\.jdm"
        if (Test-Path $jdmDir) {
            Remove-Item $jdmDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed $jdmDir"
        }
        
        # Remove ~/.jdks
        $jdksDir = "$env:USERPROFILE\.jdks"
        if (Test-Path $jdksDir) {
            Remove-Item $jdksDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed $jdksDir"
        }
        
        # Clean user PATH (jdm entries)
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $cleaned = $userPath -split ";" | Where-Object { $_ -notmatch "jdm" -and $_ -ne "" }
        [Environment]::SetEnvironmentVariable("PATH", $cleaned -join ";", "User")
        Write-Log "Cleaned user PATH"
        
        # Clean user JAVA_HOME
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "User")
        Write-Log "Cleared user JAVA_HOME"
        
        # Machine-level cleanup (if admin)
        if ($selectedMode -eq 'Administrator') {
            $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            $cleaned = $machinePath -split ";" | Where-Object { 
                $_ -notmatch "jdk" -and $_ -notmatch "java" -and $_ -notmatch "temurin" -and 
                $_ -notmatch "corretto" -and $_ -notmatch "zulu" -and $_ -notmatch "jdm" -and $_ -ne "" 
            }
            [Environment]::SetEnvironmentVariable("PATH", $cleaned -join ";", "Machine")
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "Machine")
            Write-Log "Cleaned machine PATH and JAVA_HOME"
        }
        else {
            Write-Log "Skipping machine-level cleanup (not Administrator)"
        }
        
        $summary.Steps += @{ Name = 'Cleanup'; Result = 'PASS' }
    }

    $summary.OverallResult = 'PASS'
    Write-Section "E2E VALIDATION PASSED"
}
catch {
    $summary.OverallResult = 'FAIL'
    $summary.Errors += $_.ToString()
    Write-Section "E2E VALIDATION FAILED"
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
}
finally {
    # ─── Write Summary ────────────────────────────────────────────
    if (-not (Test-Path $OutputDir)) {
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    }
    $summaryPath = Join-Path $OutputDir 'e2e_summary.json'
    $summary.Log = $global:logEntries
    $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-Log "Summary written to $summaryPath"
    
    if ($summary.OverallResult -eq 'FAIL') { exit 1 }
}