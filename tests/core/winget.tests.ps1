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
    }

    Describe "Install-WithWinget path detection" {
        BeforeEach {
            Mock Get-Command { return [PSCustomObject]@{ Name = "winget" } } -ParameterFilter { $Name -eq "winget" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Fail { }
            Mock Test-Path { return $true }
            Mock New-Item { }
            Mock Set-Content { }
        }

        It "fails instead of selecting an arbitrary existing JDK path" {
            Mock Get-JavaSnapshot { return @{ first = $true; second = $true } }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = -1978335189 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $false
            Should -Invoke Set-Content -Times 0
            Should -Invoke Write-Fail -Times 1 -ParameterFilter { $msg -like "*uniquely identify*already-installed*" }
        }

        It "records a single existing JDK path when winget reports it is already installed" {
            Mock Get-JavaSnapshot { return @{ existing = $true } }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = -1978335189 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $true
            Should -Invoke Set-Content -Times 1 -ParameterFilter {
                $Path -like "*last_install_path.txt" -and $Value -eq "existing"
            }
        }

        It "creates the marker directory when tracking an existing JDK" {
            Mock Test-Path { return $false }
            Mock Get-JavaSnapshot { return @{ existing = $true } }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = -1978335189 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -like "*\.jdm\tmp" }
        }

        It "reports a winget install failure" {
            Mock Get-JavaSnapshot { return @{} }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = 1 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $false
            Should -Invoke Write-Fail -Times 1 -ParameterFilter { $msg -like "*winget install failed*" }
        }

        It "fails when an install produces multiple new JDK paths" {
            $script:snapshotCall = 0
            Mock Get-JavaSnapshot {
                $script:snapshotCall++
                if ($script:snapshotCall -eq 1) { return @{ existing = $true } }
                return @{ existing = $true; newOne = $true; newTwo = $true }
            }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $false
            Should -Invoke Set-Content -Times 0
            Should -Invoke Write-Fail -Times 1 -ParameterFilter { $msg -like "*uniquely identify*new JDK*" }
        }

        It "records the one new JDK path after a successful install" {
            $script:snapshotCall = 0
            Mock Get-JavaSnapshot {
                $script:snapshotCall++
                if ($script:snapshotCall -eq 1) { return @{ existing = $true } }
                return @{ existing = $true; newPath = $true }
            }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $true
            Should -Invoke Set-Content -Times 1 -ParameterFilter {
                $Path -like "*last_install_path.txt" -and $Value -eq "newPath"
            }
        }

        It "creates the marker directory after a successful install when missing" {
            $script:snapshotCall = 0
            Mock Test-Path { return $false }
            Mock Get-JavaSnapshot {
                $script:snapshotCall++
                if ($script:snapshotCall -eq 1) { return @{} }
                return @{ newPath = $true }
            }
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }

            $result = Install-WithWinget -Id "EclipseAdoptium.Temurin.JDK.21"

            $result | Should -Be $true
            Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -like "*\.jdm\tmp" }
            Should -Invoke Set-Content -Times 1 -ParameterFilter {
                $Path -like "*last_install_path.txt" -and $Value -eq "newPath"
            }
        }
    }
}
