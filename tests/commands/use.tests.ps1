# use.tests.ps1
# Tests for commands/use.ps1

Describe "Use Command Tests" {
    BeforeAll {
        # Load modules
        $registryPath = Join-Path $PSScriptRoot "..\..\module\core\registry.ps1"
        . $registryPath

        $symlinkPath = Join-Path $PSScriptRoot "..\..\module\core\symlink.ps1"
        . $symlinkPath

        $usePath = Join-Path $PSScriptRoot "..\..\module\commands\use.ps1"
        . $usePath
        
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

    Describe "Invoke-Use" {
    It "shows error and lists installed versions when version is not installed" {
        Mock Test-VersionInstalled { return $false }
        Mock Get-AllVersions { 
            return @(
                [PSCustomObject]@{ key = "temurin-21"; isCurrent = $true }
                [PSCustomObject]@{ key = "corretto-17"; isCurrent = $false }
            )
        }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Use -Key "azul-21"
        
        Should -Invoke Test-VersionInstalled -Times 1 -ParameterFilter { $Key -eq "azul-21" }
        Should -Invoke Get-AllVersions -Times 1
        Should -Invoke Switch-Version -Times 0
        Should -Invoke Set-CurrentVersion -Times 0
        Should -Invoke Write-Fail -Times 1
    }
    
    It "shows message when version is already current" {
        Mock Test-VersionInstalled { return $true }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-Use -Key "temurin-21"
        
        Should -Invoke Test-VersionInstalled -Times 1
        Should -Invoke Get-CurrentVersion -Times 1
        Should -Invoke Switch-Version -Times 0
        Should -Invoke Set-CurrentVersion -Times 0
    }
    
    It "shows error when install path is missing on disk" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Get-Version { return $versionEntry }
        Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Use -Key "temurin-21"
        
        Should -Invoke Get-Version -Times 1 -ParameterFilter { $Key -eq "temurin-21" }
        Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Should -Invoke Switch-Version -Times 0
        Should -Invoke Set-CurrentVersion -Times 0
        Should -Invoke Write-Fail -Times 2
    }
    
    It "switches version successfully on happy path" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Get-Version { return $versionEntry }
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Switch-Version { return $true }
        Mock Set-CurrentVersion { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-Use -Key "temurin-21"
        
        Should -Invoke Test-VersionInstalled -Times 1 -ParameterFilter { $Key -eq "temurin-21" }
        Should -Invoke Get-CurrentVersion -Times 1
        Should -Invoke Get-Version -Times 1 -ParameterFilter { $Key -eq "temurin-21" }
        Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Should -Invoke Switch-Version -Times 1 -ParameterFilter { $TargetPath -eq "C:\Program Files\Java\jdk-21" }
        Should -Invoke Set-CurrentVersion -Times 1 -ParameterFilter { $Key -eq "temurin-21" }
    }
    
    It "shows error when Switch-Version fails" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Get-Version { return $versionEntry }
        Mock Test-Path { return $true }
        Mock Switch-Version { return $false }
        Mock Set-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Use -Key "temurin-21"
        
        Should -Invoke Switch-Version -Times 1
        Should -Invoke Set-CurrentVersion -Times 0
        Should -Invoke Write-Fail -Times 1
    }
    
    It "shows error when Set-CurrentVersion fails after successful switch" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Get-Version { return $versionEntry }
        Mock Test-Path { return $true }
        Mock Switch-Version { return $true }
        Mock Set-CurrentVersion { return $false }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Use -Key "temurin-21"
        
        Should -Invoke Switch-Version -Times 1
        Should -Invoke Set-CurrentVersion -Times 1
        Should -Invoke Write-Fail -Times 1
    }
    }
}

