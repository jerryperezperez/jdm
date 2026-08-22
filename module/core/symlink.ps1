# jdm - core/symlink.ps1
# Manages the 'current' symlink, JAVA_HOME and PATH

$JAVA_CANDIDATES = "$env:USERPROFILE\.jdm\candidates\java"
$CURRENT_LINK = "$JAVA_CANDIDATES\current"
$JDM_JAVA_BIN = "$CURRENT_LINK\bin"

# Wrapper functions for testability
function Get-CurrentPrincipalIsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-DevModeEnabled {
    $devMode = Get-ItemProperty `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
        -Name "AllowDevelopmentWithoutDevLicense" `
        -ErrorAction SilentlyContinue
    
    return ($devMode -and $devMode.AllowDevelopmentWithoutDevLicense -eq 1)
}

function Get-JdmEnvVariable {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [System.EnvironmentVariableTarget] $Target
    )
    return [Environment]::GetEnvironmentVariable($Name, $Target)
}

function Set-JdmEnvVariable {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [System.EnvironmentVariableTarget] $Target
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, $Target)
}

function Normalize-JdmPath {
    param(
        [AllowNull()] [object] $PathValue
    )

    if ($null -eq $PathValue) {
        return $null
    }

    if ($PathValue -is [array] -and $PathValue.Count -gt 0) {
        $PathValue = $PathValue[0]
    }

    $normalized = [string]$PathValue
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    return $normalized.Replace("/", "\").TrimEnd("\").ToLowerInvariant()
}

function Test-JdmPathEquals {
    param(
        [AllowNull()] [object] $LeftPath,
        [AllowNull()] [object] $RightPath
    )

    $left = Normalize-JdmPath -PathValue $LeftPath
    $right = Normalize-JdmPath -PathValue $RightPath

    if ($null -eq $left -or $null -eq $right) {
        return $false
    }

    return $left -eq $right
}

function Test-SymlinkCapability {
    $isAdmin = Get-CurrentPrincipalIsAdmin
    if ($isAdmin) { return $true }

    if (Get-DevModeEnabled) {
        return $true
    }

    return $false
}

function Get-PreferredCurrentLinkTypes {
    if (Test-SymlinkCapability) {
        return @("SymbolicLink", "Junction")
    }

    return @("Junction")
}

function New-JdmCurrentLink {
    param(
        [Parameter(Mandatory)] [string] $TargetPath,
        [Parameter(Mandatory)] [string[]] $LinkTypes
    )

    $lastError = $null

    for ($i = 0; $i -lt $LinkTypes.Count; $i++) {
        $linkType = $LinkTypes[$i]

        if ($linkType -eq "Junction") {
            if ($i -eq 0) {
                Write-Step "Using junction fallback (no administrator rights required)"
            }
            else {
                Write-Step "Symbolic link creation failed; retrying as junction..."
            }
        }

        try {
            New-Item -ItemType $linkType -Path $CURRENT_LINK -Target $TargetPath -Force -ErrorAction Stop | Out-Null
            Write-Ok "$linkType updated: current -> $TargetPath"
            return [PSCustomObject]@{
                Success = $true
                LinkType = $linkType
                Error = $null
            }
        }
        catch {
            $lastError = $_
        }
    }

    return [PSCustomObject]@{
        Success = $false
        LinkType = $null
        Error = $lastError
    }
}

function Set-CurrentSymlink {
    param(
        [Parameter(Mandatory)] [string] $TargetPath
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Fail "Target path does not exist: $TargetPath"
        return $false
    }

    $previousTarget = Get-CurrentSymlinkTarget
    $linkTypes = Get-PreferredCurrentLinkTypes

    if (Test-Path $CURRENT_LINK) {
        Write-Step "Removing existing symlink..."
        Remove-Item $CURRENT_LINK -Force -Recurse
    }

    $createResult = New-JdmCurrentLink -TargetPath $TargetPath -LinkTypes $linkTypes
    if ($createResult.Success) {
        return $true
    }

    if ($previousTarget -and (Test-Path $previousTarget)) {
        Write-Step "Restoring previous Java link..."
        $restoreResult = New-JdmCurrentLink -TargetPath $previousTarget -LinkTypes $linkTypes
        if ($restoreResult.Success) {
            Write-Step "Previous Java link restored."
        }
        else {
            Write-Fail "Failed to restore previous Java link: $($restoreResult.Error)"
        }
    }

    Write-Fail "Failed to create current Java link: $($createResult.Error)"
    return $false
}

function Get-CurrentSymlinkTarget {
    if (-not (Test-Path $CURRENT_LINK)) {
        return $null
    }

    $item = Get-Item $CURRENT_LINK -ErrorAction SilentlyContinue

    if ($item.LinkType -in @("SymbolicLink", "Junction")) {
        return $item.Target
    }

    return $null
}

function Test-CurrentSymlinkMatchesTarget {
    param(
        [Parameter(Mandatory)] [string] $TargetPath
    )

    $currentTarget = Get-CurrentSymlinkTarget
    return Test-JdmPathEquals -LeftPath $currentTarget -RightPath $TargetPath
}

# ── Clean all hardcoded java paths from Machine and User PATH ─
# Then put jdm symlink bin first so it always wins
function Repair-JavaPath {

    $isAdmin = Get-CurrentPrincipalIsAdmin

    # Always fix User PATH
    $userPath = Get-JdmEnvVariable -Name "PATH" -Target User
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
    Set-JdmEnvVariable -Name "PATH" -Value $newUserPath -Target User
    Write-Ok "User PATH updated"

    # Fix Machine PATH only if admin
    if ($isAdmin) {
        $machinePath = Get-JdmEnvVariable -Name "PATH" -Target Machine
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
        Set-JdmEnvVariable -Name "PATH" -Value $newMachinePath -Target Machine
        Write-Ok "Machine PATH updated"
    }
    else {
        Write-Step "Not running as Admin - Machine PATH not cleaned"
        Write-Step "Re-run this switch from an Administrator PowerShell to fully clean Machine PATH"
    }
}

function Set-JavaHome {
    Set-JdmEnvVariable -Name "JAVA_HOME" -Value $CURRENT_LINK -Target User
    $env:JAVA_HOME = $CURRENT_LINK

    $isAdmin = Get-CurrentPrincipalIsAdmin
    if ($isAdmin) {
        Set-JdmEnvVariable -Name "JAVA_HOME" -Value $CURRENT_LINK -Target Machine
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
