# jdm - core/winget.ps1
# Wraps winget search and install commands

function Search-Winget {
    param(
        [Parameter(Mandatory)] [string] $Query
    )

    Write-Step "Searching for '$Query'..."

    $env:WINGET_DISABLE_PROGRESS_BAR = "1"
    $raw = winget search $Query --source winget --accept-source-agreements 2>&1

    if ($raw -match "No package found" -or $raw -match "No results found") {
        return @()
    }

    $results = @()
    $lines = $raw -split "`n"
    $parsing = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match "^\s*-\s*$") { continue }

        if ($trimmed -match "^-{5,}") {
            $parsing = $true
            continue
        }

        if (-not $parsing) { continue }

        if ($trimmed -match "([\w]+\.[\w]+\.[\w.]+)") {
            $id = $matches[1].Trim()
            $name = $trimmed -replace "\s+$id.*", "" | ForEach-Object { $_.Trim() }

            $results += [PSCustomObject]@{
                Name    = $name
                Id      = $id
                Version = "unknown"
            }
        }
    }

    return $results
}

function Filter-JDK {
    param(
        [Parameter(Mandatory)] [array] $Results
    )

    return $Results | Where-Object { $_.Id -match "JDK" -or $_.Name -match "JDK" }
}

function Build-Query {
    param([string] $UserQuery)
    $query = $UserQuery -replace "-", "."
    return $query.Trim()
}

function Get-VendorFromId {
    param(
        [Parameter(Mandatory)] [string] $Id
    )

    if ($Id -match "Temurin") { return "temurin" }
    if ($Id -match "Corretto") { return "corretto" }
    if ($Id -match "Zulu") { return "azul" }
    if ($Id -match "Microsoft") { return "microsoft" }

    $parts = $Id -split "\."
    if ($parts.Count -ge 2) { return $parts[1].ToLower() }

    return "unknown"
}

function Get-VersionFromId {
    param(
        [Parameter(Mandatory)] [string] $Id
    )

    if ($Id -match "\.(\d+)\.") {
        return $matches[1]
    }

    return "unknown"
}

function Get-RegistryKey {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Result
    )

    $vendor = Get-VendorFromId  -Id $Result.Id
    $version = Get-VersionFromId -Id $Result.Id

    return "$vendor-$version"
}

# ── Snapshot all java.exe paths currently on disk ────────────
function Get-JavaSnapshot {
    $searchRoots = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LOCALAPPDATA",
        "$env:APPDATA"
    )

    $snapshot = @{}

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        $hits = Get-ChildItem -Path $root -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue
        foreach ($hit in $hits) {
            $jdkRoot = $hit.Directory.Parent.FullName
            $snapshot[$jdkRoot] = $true
        }
    }

    return $snapshot
}

function Install-WithWinget {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $TargetPath
    )

    Write-Step "Installing $Id via winget..."

    # Snapshot existing java installations BEFORE install
    Write-Step "Scanning existing Java installations..."
    $before = Get-JavaSnapshot

    # Install without --location since MSI installers ignore it
    winget install $Id `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "winget install failed with exit code $LASTEXITCODE"
        return $false
    }

    Write-Ok "Winget install completed"

    # Snapshot AFTER install and find what's new
    Write-Step "Detecting new installation..."
    $after = Get-JavaSnapshot

    $newPaths = $after.Keys | Where-Object { -not $before.ContainsKey($_) }

    if ($newPaths.Count -eq 0) {
        Write-Fail "Could not detect new JDK installation. It may already be installed."
        return $false
    }

    $realPath = $newPaths | Select-Object -First 1
    Write-Ok "Detected new JDK at: $realPath"

    # Write real path to marker file for install.ps1 to read
    $tmpDir = "$env:USERPROFILE\.jdm\tmp"
    if (-not (Test-Path $tmpDir)) {
        New-Item -ItemType Directory $tmpDir -Force | Out-Null
    }
    Set-Content "$tmpDir\last_install_path.txt" $realPath

    return $true
}
