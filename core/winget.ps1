# jdm - core/winget.ps1
# Wraps winget search and install commands

function Search-Winget {
    param(
        [Parameter(Mandatory)] [string] $Query
    )

    Write-Step "Searching winget for '$Query'..."

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

        # Extract Id using regex - matches patterns like EclipseAdoptium.Temurin.21.JDK
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
    # Dots work fine with winget, convert dashes to dots
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

function Install-WithWinget {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $TargetPath
    )

    Write-Step "Downloading and installing $Id..."
    Write-Step "Target path: $TargetPath"

    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }

    # Run winget directly without capturing output
    # so the user sees download progress
    winget install $Id `
        --location $TargetPath `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Winget install completed"
        return $true
    }
    else {
        Write-Fail "winget install failed with exit code $LASTEXITCODE"
        return $false
    }
}
