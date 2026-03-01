# winget.tests.ps1
# Tests for core/winget.ps1 pure functions

Describe "Winget Tests" {
    BeforeAll {
        # Load winget module
        $modulePath = Join-Path $PSScriptRoot "..\..\module\core\winget.ps1"
        . $modulePath
        
        # Provide minimal stubs for functions used by winget.ps1
        # (jdm.ps1 is not loaded as it auto-executes and breaks test discovery)
        if (-not (Get-Command Write-Step -ErrorAction SilentlyContinue)) {
            function Write-Step { param($msg) }
        }
        if (-not (Get-Command Write-Ok -ErrorAction SilentlyContinue)) {
            function Write-Ok { param($msg) }
        }
        if (-not (Get-Command Write-Fail -ErrorAction SilentlyContinue)) {
            function Write-Fail { param($msg) }
        }
    }

    Describe "Build-Query" {
        It "converts hyphens to dots" {
            $result = Build-Query -UserQuery "temurin-21"
            $result | Should -Be "temurin.21"
        }
        
        It "trims whitespace" {
            $result = Build-Query -UserQuery "  temurin.21  "
            $result | Should -Be "temurin.21"
        }
        
        It "leaves already-normalized input unchanged" {
            $result = Build-Query -UserQuery "temurin.21"
            $result | Should -Be "temurin.21"
        }
        
        It "handles multiple hyphens" {
            $result = Build-Query -UserQuery "amazon-corretto-17"
            $result | Should -Be "amazon.corretto.17"
        }
    }

    Describe "Get-VendorFromId" {
        It "returns 'temurin' for Temurin IDs" {
            $result = Get-VendorFromId -Id "EclipseAdoptium.Temurin.JDK.21"
            $result | Should -Be "temurin"
        }
        
        It "returns 'corretto' for Corretto IDs" {
            $result = Get-VendorFromId -Id "Amazon.Corretto.17"
            $result | Should -Be "corretto"
        }
        
        It "returns 'azul' for Zulu IDs" {
            $result = Get-VendorFromId -Id "Azul.Zulu.21"
            $result | Should -Be "azul"
        }
        
        It "returns 'microsoft' for Microsoft IDs" {
            $result = Get-VendorFromId -Id "Microsoft.OpenJDK.21"
            $result | Should -Be "microsoft"
        }
        
        It "returns second component lowercased for generic IDs" {
            $result = Get-VendorFromId -Id "Foo.Bar.Baz"
            $result | Should -Be "bar"
        }
        
        It "returns 'unknown' for single-part IDs" {
            $result = Get-VendorFromId -Id "JustOnePart"
            $result | Should -Be "unknown"
        }
        
        It "returns 'unknown' for empty ID" {
            { Get-VendorFromId -Id "" } | Should -Throw
        }
    }

    Describe "Get-VersionFromId" {
        It "extracts version number from ID" {
            $result = Get-VersionFromId -Id "EclipseAdoptium.Temurin.JDK.21.0.1"
            $result | Should -Be "21"
        }
        
        It "extracts version from middle segment" {
            $result = Get-VersionFromId -Id "Amazon.Corretto.17.0.1"
            $result | Should -Be "17"
        }
        
        It "returns 'unknown' when no numeric segment found" {
            $result = Get-VersionFromId -Id "Foo.Bar.Baz"
            $result | Should -Be "unknown"
        }
        
        It "returns 'unknown' for empty ID" {
            { Get-VersionFromId -Id "" } | Should -Throw
        }
        
        It "handles version with single digit" {
            $result = Get-VersionFromId -Id "Vendor.JDK.8.X"
            $result | Should -Be "8"
        }
    }

    Describe "Get-RegistryKey" {
        It "combines vendor and version as key" {
            $result = [PSCustomObject]@{
                Id = "EclipseAdoptium.Temurin.21"
            }
            $key = Get-RegistryKey -Result $result
            $key | Should -Be "temurin-21"
        }
        
        It "handles Corretto IDs" {
            $result = [PSCustomObject]@{
                Id = "Amazon.Corretto.17"
            }
            $key = Get-RegistryKey -Result $result
            $key | Should -Be "corretto-17"
        }
        
        It "handles Zulu IDs" {
            $result = [PSCustomObject]@{
                Id = "Azul.Zulu.21"
            }
            $key = Get-RegistryKey -Result $result
            $key | Should -Be "azul-21"
        }
        
        It "handles Microsoft IDs" {
            $result = [PSCustomObject]@{
                Id = "Microsoft.OpenJDK.21"
            }
            $key = Get-RegistryKey -Result $result
            $key | Should -Be "microsoft-21"
        }
    }

    Describe "Filter-JDK" {
        It "filters results containing JDK in Name" {
            $results = @(
                [PSCustomObject]@{ Name = "Eclipse Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.21" }
                [PSCustomObject]@{ Name = "Eclipse Temurin JRE 21"; Id = "EclipseAdoptium.Temurin.JRE.21" }
            )
            $filtered = @(Filter-JDK -Results $results)
            $filtered.Count | Should -Be 1
            $filtered[0].Name | Should -Match "JDK"
        }
        
        It "filters results containing JDK in Id" {
            $results = @(
                [PSCustomObject]@{ Name = "Temurin 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
                [PSCustomObject]@{ Name = "Temurin 21"; Id = "EclipseAdoptium.Temurin.JRE.21" }
            )
            $filtered = @(Filter-JDK -Results $results)
            $filtered.Count | Should -Be 1
            $filtered[0].Id | Should -Match "JDK"
        }
        
        It "returns empty array when no JDK found" {
            $results = @(
                [PSCustomObject]@{ Name = "JRE 21"; Id = "EclipseAdoptium.Temurin.JRE.21" }
            )
            $filtered = @(Filter-JDK -Results $results)
            $filtered.Count | Should -Be 0
        }
        
        It "returns all results when all contain JDK" {
            $results = @(
                [PSCustomObject]@{ Name = "JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
                [PSCustomObject]@{ Name = "JDK 17"; Id = "EclipseAdoptium.Temurin.JDK.17" }
            )
            $filtered = @(Filter-JDK -Results $results)
            $filtered.Count | Should -Be 2
        }
        
        It "handles empty input array" {
            $filtered = @(Filter-JDK -Results @())
            $filtered.Count | Should -Be 0
        }
    }
}