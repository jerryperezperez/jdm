# ─────────────────────────────────────────────────────────────
#  jdm - core/registry.ps1
#  Read and write the registry.json file
#  All state about installed versions lives here
# ─────────────────────────────────────────────────────────────

$REGISTRY_PATH = "$env:USERPROFILE\.jdm\registry.json"

# ── Read the full registry ────────────────────────────────────
# Output: registry object or $null if not found/corrupt
function Get-Registry {
    if (-not (Test-Path $REGISTRY_PATH)) {
        Write-Fail "Registry not found at $REGISTRY_PATH. Is jdm installed?"
        return $null
    }

    try {
        $raw = Get-Content $REGISTRY_PATH -Raw
        $registry = $raw | ConvertFrom-Json
        return $registry
    }
    catch {
        Write-Fail "Registry is corrupt or invalid JSON. Path: $REGISTRY_PATH"
        return $null
    }
}

# ── Write the full registry back to disk ─────────────────────
# Input: registry object
function Set-Registry {
    param(
        [Parameter(Mandatory)] [object] $Registry
    )

    try {
        $Registry | ConvertTo-Json -Depth 10 | Set-Content $REGISTRY_PATH
        return $true
    }
    catch {
        Write-Fail "Failed to write registry: $_"
        return $false
    }
}

# ── Check if a version is already installed ───────────────────
# Input:  registry key e.g. "temurin-21"
# Output: $true / $false
function Test-VersionInstalled {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    return $registry.candidates.java.installed -contains $Key
}

# ── Get the current active version key ───────────────────────
# Output: e.g. "temurin-21" or $null
function Get-CurrentVersion {
    $registry = Get-Registry
    if (-not $registry) { return $null }

    return $registry.candidates.java.current
}

# ── Get a specific version entry from the registry ───────────
# Input:  registry key e.g. "temurin-21"
# Output: version object { id, vendor, version, path, installedAt }
function Get-Version {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $null }

    $versions = $registry.candidates.java.versions
    $entry = $versions.PSObject.Properties[$Key]

    if (-not $entry) {
        Write-Fail "Version '$Key' not found in registry."
        return $null
    }

    return $entry.Value
}

# ── Get all installed versions ────────────────────────────────
# Output: array of version objects with their keys attached
function Get-AllVersions {
    $registry = Get-Registry
    if (-not $registry) { return @() }

    $result = @()
    $current = $registry.candidates.java.current
    $versions = $registry.candidates.java.versions

    foreach ($prop in $versions.PSObject.Properties) {
        $entry = $prop.Value
        $entry | Add-Member -NotePropertyName "key"       -NotePropertyValue $prop.Name  -Force
        $entry | Add-Member -NotePropertyName "isCurrent" -NotePropertyValue ($prop.Name -eq $current) -Force
        $result += $entry
    }

    return $result
}

# ── Add a new version to the registry ────────────────────────
# Input:  key (e.g. "temurin-21"), winget result object, install path
function Add-Version {
    param(
        [Parameter(Mandatory)] [string]       $Key,
        [Parameter(Mandatory)] [PSCustomObject] $Result,
        [Parameter(Mandatory)] [string]       $InstallPath,
        [Parameter(Mandatory)] [string]       $Vendor,
        [Parameter(Mandatory)] [string]       $Version
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    # Build version entry
    $entry = [PSCustomObject]@{
        id          = $Result.Id
        vendor      = $Vendor
        version     = $Version
        path        = $InstallPath
        installedAt = (Get-Date -Format "yyyy-MM-dd")
    }

    # Add to versions map
    $registry.candidates.java.versions | Add-Member `
        -NotePropertyName $Key `
        -NotePropertyValue $entry `
        -Force

    # Add to installed list if not already there
    $installed = [System.Collections.ArrayList]$registry.candidates.java.installed
    if (-not ($installed -contains $Key)) {
        $installed.Add($Key) | Out-Null
    }
    $registry.candidates.java.installed = $installed.ToArray()

    # If this is the first version, set as current automatically
    if (-not $registry.candidates.java.current) {
        $registry.candidates.java.current = $Key
        Write-Step "Set '$Key' as current version (first install)"
    }

    return Set-Registry -Registry $registry
}

# ── Update the current active version ────────────────────────
# Input:  registry key e.g. "temurin-21"
function Set-CurrentVersion {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    if (-not (Test-VersionInstalled -Key $Key)) {
        Write-Fail "Cannot set current: '$Key' is not installed."
        return $false
    }

    $registry.candidates.java.current = $Key
    return Set-Registry -Registry $registry
}

# ── Remove a version from the registry ───────────────────────
# Input:  registry key e.g. "temurin-21"
function Remove-Version {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    if (-not (Test-VersionInstalled -Key $Key)) {
        Write-Fail "Cannot remove: '$Key' is not installed."
        return $false
    }

    # Remove from versions map
    $registry.candidates.java.versions.PSObject.Properties.Remove($Key)

    # Remove from installed list
    $installed = [System.Collections.ArrayList]$registry.candidates.java.installed
    $installed.Remove($Key)
    $registry.candidates.java.installed = $installed.ToArray()

    # If we removed the current version, clear it
    if ($registry.candidates.java.current -eq $Key) {
        $registry.candidates.java.current = $null
        Write-Step "Warning: removed the active version. Run 'jdm use <version>' to set a new one."
    }

    return Set-Registry -Registry $registry
}
