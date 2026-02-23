# jdm - core/symlink.ps1
# Manages the 'current' symlink, JAVA_HOME and PATH

$JAVA_CANDIDATES = "$env:USERPROFILE\.jdm\candidates\java"
$CURRENT_LINK = "$JAVA_CANDIDATES\current"
$JDM_JAVA_BIN = "$CURRENT_LINK\bin"

function Test-SymlinkCapability {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) { return $true }

    $devMode = Get-ItemProperty `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
        -Name "AllowDevelopmentWithoutDevLicense" `
        -ErrorAction SilentlyContinue

    if ($devMode -and $devMode.AllowDevelopmentWithoutDevLicense -eq 1) {
        return $true
    }

    return $false
}

function Set-CurrentSymlink {
    param(
        [Parameter(Mandatory)] [string] $TargetPath
    )

    if (-not (Test-SymlinkCapability)) {
        Write-Fail "Cannot create symlink. Run as Administrator or enable Developer Mode."
        return $false
    }

    if (-not (Test-Path $TargetPath)) {
        Write-Fail "Target path does not exist: $TargetPath"
        return $false
    }

    if (Test-Path $CURRENT_LINK) {
        Write-Step "Removing existing symlink..."
        Remove-Item $CURRENT_LINK -Force -Recurse
    }

    try {
        New-Item -ItemType SymbolicLink -Path $CURRENT_LINK -Target $TargetPath -Force | Out-Null
        Write-Ok "Symlink updated: current -> $TargetPath"
        return $true
    }
    catch {
        Write-Fail "Failed to create symlink: $_"
        return $false
    }
}

function Get-CurrentSymlinkTarget {
    if (-not (Test-Path $CURRENT_LINK)) {
        return $null
    }

    $item = Get-Item $CURRENT_LINK -ErrorAction SilentlyContinue

    if ($item.LinkType -eq "SymbolicLink") {
        return $item.Target
    }

    return $null
}

# ── Clean all hardcoded java paths from Machine and User PATH ─
# Then put jdm symlink bin first so it always wins
function Repair-JavaPath {

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    # Always fix User PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $userCleaned = $userPath -split ";" | Where-Object {
        $_ -notmatch "java" -and
        $_ -notmatch "jdk" -and
        $_ -notmatch "temurin" -and
        $_ -notmatch "corretto" -and
        $_ -notmatch "adoptium" -and
        $_ -notmatch "zulu" -and
        $_ -notmatch "jdm\\candidates" -and
        $_ -ne ""
    }
    # Add jdm bin to user PATH
    $newUserPath = $JDM_JAVA_BIN + ";" + ($userCleaned -join ";")
    [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
    Write-Ok "User PATH updated"

    # Fix Machine PATH only if admin
    if ($isAdmin) {
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $machineCleaned = $machinePath -split ";" | Where-Object {
            $_ -notmatch "java" -and
            $_ -notmatch "jdk" -and
            $_ -notmatch "temurin" -and
            $_ -notmatch "corretto" -and
            $_ -notmatch "adoptium" -and
            $_ -notmatch "zulu" -and
            $_ -notmatch "jdm\\candidates" -and
            $_ -ne ""
        }
        $newMachinePath = $JDM_JAVA_BIN + ";" + ($machineCleaned -join ";")
        [Environment]::SetEnvironmentVariable("PATH", $newMachinePath, "Machine")
        Write-Ok "Machine PATH updated"
    }
    else {
        Write-Step "Not running as Admin - Machine PATH not cleaned"
        Write-Step "Run 'jdm repair' as Administrator to fully clean Machine PATH"
    }
}

function Set-JavaHome {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT_LINK, "User")
    $env:JAVA_HOME = $CURRENT_LINK

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT_LINK, "Machine")
    }

    Write-Ok "JAVA_HOME set to $CURRENT_LINK"
}

function Switch-Version {
    param(
        [Parameter(Mandatory)] [string] $TargetPath
    )

    Write-Step "Switching Java version..."

    # Update symlink
    $success = Set-CurrentSymlink -TargetPath $TargetPath

    if (-not $success) { return $false }

    # Verify java.exe exists
    $javaBin = "$TargetPath\bin\java.exe"
    if (Test-Path $javaBin) {
        Write-Ok "Verified: java.exe found"
    }
    else {
        Write-Fail "Warning: java.exe not found at $javaBin - install may be incomplete"
    }

    # Clean PATH so jdm symlink always wins
    Write-Step "Updating PATH..."
    Repair-JavaPath

    # Ensure JAVA_HOME points to symlink
    Set-JavaHome

    return $true
}

function Remove-CurrentSymlink {
    if (Test-Path $CURRENT_LINK) {
        Remove-Item $CURRENT_LINK -Force -Recurse
        Write-Ok "Removed current symlink"
    }
}

function Initialize-JavaEnvironment {
    Write-Step "Configuring Java environment..."
    Set-JavaHome
    Repair-JavaPath
    Write-Ok "Environment configured. Restart your terminal for changes to take effect."
}
