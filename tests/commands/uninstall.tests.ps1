# uninstall.tests.ps1
# Tests for commands/uninstall.ps1

Describe "Uninstall Command Tests" {
    BeforeAll {
        # Load modules
        $registryPath = Join-Path $PSScriptRoot "..\..\module\core\registry.ps1"
        . $registryPath

        $symlinkPath = Join-Path $PSScriptRoot "..\..\module\core\symlink.ps1"
        . $symlinkPath

        $uninstallPath = Join-Path $PSScriptRoot "..\..\module\commands\uninstall.ps1"
        . $uninstallPath

        # Provide minimal stubs for functions used by these modules
        # (jdm.ps1 is not loaded as it auto-executes and breaks test discovery)
        if (-not (Get-Command Write-Title -ErrorAction SilentlyContinue)) {
            function Write-Title { param($msg) }
        }
        if (-not (Get-Command Write-Host -ErrorAction SilentlyContinue)) {
            function Write-Host { param($Object, $ForegroundColor) }
        }
        if (-not (Get-Command Write-Fail -ErrorAction SilentlyContinue)) {
            function Write-Fail { param($msg) }
        }
        if (-not (Get-Command Write-Step -ErrorAction SilentlyContinue)) {
            function Write-Step { param($msg) }
        }
        if (-not (Get-Command Write-Ok -ErrorAction SilentlyContinue)) {
            function Write-Ok { param($msg) }
        }
    }

    Describe "Invoke-Uninstall" {
    It "shows error when version is not found" {
        Mock Test-VersionInstalled { return $false }
        Mock Get-AllVersions { return @() }
        Mock Remove-Version { }
        Mock Remove-Item { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }

        Invoke-Uninstall -Key "azul.21"

        Should -Invoke Test-VersionInstalled -Times 1 -ParameterFilter { $Key -eq "azul.21" }
        Should -Invoke Get-AllVersions -Times 1
        Should -Invoke Remove-Version -Times 0
        Should -Invoke Remove-Item -Times 0
        Should -Invoke Write-Fail -Times 1
    }

    It "removes non-current version after confirmation" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }

        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "corretto.17" }
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Uninstall-WithWinget { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }

        Invoke-Uninstall -Key "temurin.21"

        Should -Invoke Test-VersionInstalled -Times 1
        Should -Invoke Get-CurrentVersion -Times 1
        Should -Invoke Read-Host -Times 1
        Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Should -Invoke Uninstall-WithWinget -Times 1 -ParameterFilter { $Id -eq "EclipseAdoptium.Temurin.JDK.21" }
        Should -Invoke Remove-Version -Times 1 -ParameterFilter { $Key -eq "temurin.21" }
    }

    It "shows message when files are already missing" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }

        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "corretto.17" }
        Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Uninstall-WithWinget { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }

        Invoke-Uninstall -Key "temurin.21"

        Should -Invoke Remove-Item -Times 0
        Should -Invoke Uninstall-WithWinget -Times 1 -ParameterFilter { $Id -eq "EclipseAdoptium.Temurin.JDK.21" }
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*already missing*" }
        Should -Invoke Remove-Version -Times 1
    }


    It "removes symlink when removing only installed version" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }

        $allVersions = @(
            [PSCustomObject]@{ key = "temurin.21"; isCurrent = $true }
        )

        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "temurin.21" }
        Mock Get-AllVersions { return $allVersions }
        Mock Test-Path { return $true }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Uninstall-WithWinget { return $true }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Remove-CurrentSymlink { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }

        Invoke-Uninstall -Key "temurin-21"

        Should -Invoke Remove-Version -Times 1
        Should -Invoke Uninstall-WithWinget -Times 1 -ParameterFilter { $Id -eq "EclipseAdoptium.Temurin.JDK.21" }
        Should -Invoke Remove-CurrentSymlink -Times 1
        Should -Invoke Switch-Version -Times 0
        Should -Invoke Set-CurrentVersion -Times 0
    }

    It "cancels when user cancels removal confirmation" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }

        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Read-Host { return "n" }
        Mock Remove-Item { }
        Mock Remove-Version { }
        Mock Uninstall-WithWinget { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }

        Invoke-Uninstall -Key "temurin.21"

        Should -Invoke Read-Host -Times 1
        Should -Invoke Remove-Item -Times 0
        Should -Invoke Uninstall-WithWinget -Times 0
        Should -Invoke Remove-Version -Times 0
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*cancelled*" }
    }

    It "cancels when user cancels replacement selection" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }

        $allVersions = @(
            [PSCustomObject]@{ key = "temurin.21"; isCurrent = $true },
            [PSCustomObject]@{ key = "corretto.17"; isCurrent = $false }
        )

        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "temurin.21" }
        Mock Get-AllVersions { return $allVersions }
        Mock Read-Host {
            if ($Prompt -like "*Which one*") { return "q" }
        }
        Mock Remove-Item { }
        Mock Remove-Version { }
        Mock Uninstall-WithWinget { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }

        Invoke-Uninstall -Key "temurin-21"

        Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -like "*Which one*" }
        Should -Invoke Remove-Item -Times 0
        Should -Invoke Uninstall-WithWinget -Times 0
        Should -Invoke Remove-Version -Times 0
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*cancelled*" }
    }
    }

    Describe "Invoke-UninstallAll" {
        BeforeEach {
            Mock Write-Title { }
            Mock Write-Host { }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Fail { }
            Mock Read-Host { return "y" }
            Mock Uninstall-WithWinget { return $true }
            Mock Remove-Item { }
            Mock Remove-Version { return $true }
            Mock Remove-CurrentSymlink { }
            Mock Get-ChildItem { return @() }
            Mock Test-Path { return $false }
        }

        It "returns 0 and removes nothing when no JDKs are installed" {
            Mock Get-AllVersions { return @() }

            $result = Invoke-UninstallAll

            $result | Should -Be 0
            Should -Invoke Remove-Version -Times 0
            Should -Invoke Uninstall-WithWinget -Times 0
        }

        It "cancels on 'n' and makes no changes" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" }
            )
            Mock Get-AllVersions { return $entries }
            Mock Read-Host { return "n" }

            $result = Invoke-UninstallAll

            $result | Should -Be 0
            Should -Invoke Remove-Version -Times 0
            Should -Invoke Remove-Item -Times 0
            Should -Invoke Uninstall-WithWinget -Times 0
        }

        It "calls Uninstall-WithWinget once per entry and removes every registry entry" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" },
                [PSCustomObject]@{ key = "corretto.17"; id = "Amazon.Corretto.17"; path = "C:\Program Files\Java\jdk-17" }
            )
            Mock Get-AllVersions { return $entries }

            $result = Invoke-UninstallAll

            $result | Should -Be 0
            Should -Invoke Uninstall-WithWinget -Times 2
            Should -Invoke Remove-Version -Times 2
        }

        It "continues to remaining JDKs when a single removal fails" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" },
                [PSCustomObject]@{ key = "corretto.17"; id = "Amazon.Corretto.17"; path = "C:\Program Files\Java\jdk-17" }
            )
            Mock Get-AllVersions { return $entries }
            Mock Uninstall-WithWinget { return $false } -ParameterFilter { $Id -eq "EclipseAdoptium.Temurin.JDK.21" }

            $result = Invoke-UninstallAll

            Should -Invoke Uninstall-WithWinget -Times 2
            Should -Invoke Remove-Version -Times 2
            $result | Should -Be 1
        }

        It "deletes the empty vendor directory when no other JDK remains" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" }
            )
            Mock Get-AllVersions { return $entries }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\Program Files\Java" }
            Mock Get-ChildItem { return @() } -ParameterFilter { $Path -eq "C:\Program Files\Java" }

            $result = Invoke-UninstallAll

            $result | Should -Be 0
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java" }
        }

        It "keeps the vendor directory when a sibling JDK still has bin\java.exe" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" }
            )
            Mock Get-AllVersions { return $entries }

            $sibling = [PSCustomObject]@{ FullName = "C:\Program Files\Java\jdk-17" }
            Mock Get-ChildItem { return @($sibling) } -ParameterFilter { $Path -eq "C:\Program Files\Java" }
            Mock Test-Path {
                param($Path)
                if ($Path -eq "C:\Program Files\Java") { return $true }
                if ($Path -eq "C:\Program Files\Java\jdk-17\bin\java.exe") { return $true }
                return $false
            }

            $result = Invoke-UninstallAll

            $result | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -ParameterFilter { $Path -eq "C:\Program Files\Java" }
        }

        It "invokes Remove-CurrentSymlink and prints a notice when zero remain" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" }
            )
            $script:allCalls = 0
            Mock Get-AllVersions {
                $script:allCalls++
                if ($script:allCalls -eq 1) { return $entries }
                return @()
            }

            Invoke-UninstallAll

            Should -Invoke Remove-CurrentSymlink -Times 1
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "*No active Java version set*" }
        }

        It "returns non-zero when any removal failed" {
            $entries = @(
                [PSCustomObject]@{ key = "temurin.21"; id = "EclipseAdoptium.Temurin.JDK.21"; path = "C:\Program Files\Java\jdk-21" }
            )
            Mock Get-AllVersions { return $entries }
            Mock Uninstall-WithWinget { return $false }

            $result = Invoke-UninstallAll

            $result | Should -Be 1
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "*had issues*" }
        }
    }
}
