# jdm - core/symlink.ps1
# Manages the 'current' symlink, JAVA_HOME and PATH

$JAVA_CANDIDATES = "$env:USERPROFILE\.jdm\candidates\java"
$CURRENT_LINK = "$JAVA_CANDIDATES\current"

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

function Set-JavaHome {
    Write-Step "Setting JAVA_HOME..."
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT_LINK, "User")
    $env:JAVA_HOME = $CURRENT_LINK
    Write-Ok "JAVA_HOME set to $CURRENT_LINK"
}

function Add-JavaToPath {
    Write-Step "Adding Java to PATH..."

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $javaEntry = "%JAVA_HOME%\bin"

    if ($currentPath -notlike "*JAVA_HOME*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$javaEntry", "User")
        Write-Ok "Added %JAVA_HOME%\bin to PATH"
    }
    else {
        Write-Ok "%JAVA_HOME%\bin already in PATH, skipping"
    }
}

function Switch-Version {
    param(
        [Parameter(Mandatory)] [string] $TargetPath
    )

    Write-Step "Switching Java version..."

    $success = Set-CurrentSymlink -TargetPath $TargetPath

    if ($success) {
        $javaBin = "$TargetPath\bin\java.exe"
        if (Test-Path $javaBin) {
            Write-Ok "Verified: java.exe found at $javaBin"
        }
        else {
            Write-Fail "Warning: java.exe not found at $javaBin - install may be incomplete"
        }
    }

    return $success
}

function Remove-CurrentSymlink {
    if (Test-Path $CURRENT_LINK) {
        Remove-Item $CURRENT_LINK -Force -Recurse
        Write-Ok "Removed current symlink"
    }
}

function Initialize-JavaEnvironment {
    Write-Step "Configuring Java environment variables..."
    Set-JavaHome
    Add-JavaToPath
    Write-Ok "Environment configured. Restart your terminal for changes to take effect."
}
