# ─────────────────────────────────────────────────────────────
#  jdm - core/registry.ps1
#  Read and write the registry.json file
#  All state about installed versions lives here
# ─────────────────────────────────────────────────────────────

$REGISTRY_PATH = "$env:USERPROFILE\.jdm\registry.json"

# ── Normalize a version key to dot format ─────────────────────
# ADR-0001: Use dot format consistently for version keys
# Input:  "temurin-21" or "temurin.21"
# Output: "temurin.21"
function Normalize-VersionKey {
    param(
        [Parameter(Mandatory)] [string] $Key
    )
    return $Key -replace "-", "."
}

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
# Input:  registry key e.g. "temurin.21" or "temurin-21" (backward compat)
# Output: $true / $false
function Test-VersionInstalled {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    $normalized = Normalize-VersionKey -Key $Key
    $hyphenForm = $normalized -replace "\.", "-"

    # Check all three forms: normalized dot, original input, and hyphen form
    return $registry.candidates.java.installed -contains $normalized -or
           $registry.candidates.java.installed -contains $Key -or
           $registry.candidates.java.installed -contains $hyphenForm
}

# ── Get the current active version key ───────────────────────
# Output: e.g. "temurin-21" or $null
function Get-CurrentVersion {
    $registry = Get-Registry
    if (-not $registry) { return $null }

    return $registry.candidates.java.current
}

# ── Get a specific version entry from the registry ───────────
# Input:  registry key e.g. "temurin.21" or "temurin-21" (backward compat)
# Output: version object { id, vendor, version, path, installedAt }
function Get-Version {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $null }

    $normalized = Normalize-VersionKey -Key $Key
    $hyphenForm = $normalized -replace "\.", "-"
    $versions = $registry.candidates.java.versions

    # Try normalized (dot) form first, then hyphen form, then original key for backward compat
    $entry = $versions.PSObject.Properties[$normalized]
    if (-not $entry -and $hyphenForm -ne $normalized) {
        $entry = $versions.PSObject.Properties[$hyphenForm]
    }
    if (-not $entry) {
        $entry = $versions.PSObject.Properties[$Key]
    }

    if (-not $entry) {
        Write-Fail "Version '$Key' not found in registry."
        return $null
    }

    return $entry.Value
}

# ── Get all installed versions ────────────────────────────────
# Output: array of version objects with their keys attached (always dot format)
function Get-AllVersions {
    $registry = Get-Registry
    if (-not $registry) { return @() }

    $result = @()
    $current = $registry.candidates.java.current
    $normalizedCurrent = if ($current) { Normalize-VersionKey -Key $current } else { $null }
    $versions = $registry.candidates.java.versions

    foreach ($prop in $versions.PSObject.Properties) {
        $normalizedKey = Normalize-VersionKey -Key $prop.Name
        $entry = $prop.Value
        $entry | Add-Member -NotePropertyName "key"       -NotePropertyValue $normalizedKey  -Force
        $entry | Add-Member -NotePropertyName "isCurrent" -NotePropertyValue ($normalizedKey -eq $normalizedCurrent) -Force
        $result += $entry
    }

    return ,@($result)
}

# ── Add a new version to the registry ────────────────────────
# Input:  key (e.g. "temurin.21"), winget result object, install path
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

    $normalized = Normalize-VersionKey -Key $Key

    # Build version entry
    $entry = [PSCustomObject]@{
        id          = $Result.Id
        vendor      = $Vendor
        version     = $Version
        path        = $InstallPath
        installedAt = (Get-Date -Format "yyyy-MM-dd")
    }

    # Add to versions map (normalized dot key)
    $registry.candidates.java.versions | Add-Member `
        -NotePropertyName $normalized `
        -NotePropertyValue $entry `
        -Force

    # Add to installed list if not already there
    $installed = [System.Collections.ArrayList]$registry.candidates.java.installed
    if (-not ($installed -contains $normalized)) {
        $installed.Add($normalized) | Out-Null
    }
    $registry.candidates.java.installed = $installed.ToArray()

    return Set-Registry -Registry $registry
}

# ── Update the current active version ────────────────────────
# Input:  registry key e.g. "temurin.21" (normalized internally)
function Set-CurrentVersion {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    $normalized = Normalize-VersionKey -Key $Key

    if (-not (Test-VersionInstalled -Key $normalized)) {
        Write-Fail "Cannot set current: '$Key' is not installed."
        return $false
    }

    $registry.candidates.java.current = $normalized
    return Set-Registry -Registry $registry
}

# ── Remove a version from the registry ───────────────────────
# Input:  registry key e.g. "temurin.21" or "temurin-21" (backward compat)
function Remove-Version {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $registry = Get-Registry
    if (-not $registry) { return $false }

    $normalized = Normalize-VersionKey -Key $Key
    $hyphenForm = $normalized -replace "\.", "-"

    # Try to find and remove by normalized, hyphen, or original key
    $foundKey = $null
    if ($registry.candidates.java.versions.PSObject.Properties[$normalized]) {
        $foundKey = $normalized
    }
    elseif ($hyphenForm -ne $normalized -and $registry.candidates.java.versions.PSObject.Properties[$hyphenForm]) {
        $foundKey = $hyphenForm
    }
    elseif ($registry.candidates.java.versions.PSObject.Properties[$Key]) {
        $foundKey = $Key
    }

    if (-not $foundKey) {
        Write-Fail "Cannot remove: '$Key' is not installed."
        return $false
    }

    # Remove from versions map
    $registry.candidates.java.versions.PSObject.Properties.Remove($foundKey)

    # Remove from installed list (try all forms)
    $installed = [System.Collections.ArrayList]$registry.candidates.java.installed
    $installed.Remove($normalized) | Out-Null
    $installed.Remove($hyphenForm) | Out-Null
    $installed.Remove($Key) | Out-Null
    $registry.candidates.java.installed = $installed.ToArray()

    # If we removed the current version, clear it
    if ($registry.candidates.java.current) {
        $currentNormalized = Normalize-VersionKey -Key $registry.candidates.java.current
        if ($currentNormalized -eq $normalized) {
            $registry.candidates.java.current = $null
            Write-Step "Warning: removed the active version. Run 'jdm use <version>' to set a new one."
        }
    }

    return Set-Registry -Registry $registry
}
