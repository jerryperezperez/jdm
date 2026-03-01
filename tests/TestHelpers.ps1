# TestHelpers.ps1
# Shared utilities for jdm Pester tests

# Load helper functions from jdm.ps1
$modulePath = Join-Path $PSScriptRoot "..\module\jdm.ps1"
if (Test-Path $modulePath) {
    . $modulePath
}

# Create a temporary registry file for testing
function New-TestRegistry {
    param(
        [string] $TempDir
    )
    
    $registryPath = Join-Path $TempDir "registry.json"
    
    # Create a minimal valid registry structure
    $registry = @{
        candidates = @{
            java = @{
                installed = @()
                current = $null
                versions = @{}
            }
        }
    }
    
    $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
    return $registryPath
}

# Create a populated test registry with sample data
function New-PopulatedTestRegistry {
    param(
        [string] $TempDir,
        [array] $Versions = @("temurin-21", "corretto-17")
    )
    
    $registryPath = Join-Path $TempDir "registry.json"
    
    $versions = @{}
    foreach ($key in $Versions) {
        $vendor = $key -split "-" | Select-Object -First 1
        $version = $key -split "-" | Select-Object -Last 1
        
        $versions[$key] = @{
            id = "EclipseAdoptium.Temurin.JDK.$version"
            vendor = $vendor
            version = $version
            path = "C:\Program Files\Java\jdk-$version"
            installedAt = "2024-01-01"
        }
    }
    
    $registry = @{
        candidates = @{
            java = @{
                installed = $Versions
                current = if ($Versions.Count -gt 0) { $Versions[0] } else { $null }
                versions = $versions
            }
        }
    }
    
    $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
    return $registryPath
}

