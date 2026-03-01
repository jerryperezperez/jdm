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
        
        Invoke-Uninstall -Key "azul-21"
        
        Should -Invoke Test-VersionInstalled -Times 1 -ParameterFilter { $Key -eq "azul-21" }
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
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Test-VersionInstalled -Times 1
        Should -Invoke Get-CurrentVersion -Times 1
        Should -Invoke Read-Host -Times 1
        Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Should -Invoke Remove-Version -Times 1 -ParameterFilter { $Key -eq "temurin-21" }
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
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Remove-Item -Times 0
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*already missing*" }
        Should -Invoke Remove-Version -Times 1
    }
    
    It "switches to replacement when removing active version" {
        $versionEntry = [PSCustomObject]@{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        
        $replacementEntry = [PSCustomObject]@{
            id = "Amazon.Corretto.17"
            vendor = "corretto"
            version = "17"
            path = "C:\Program Files\Java\jdk-17"
            installedAt = "2024-01-01"
        }
        
        $allVersions = @(
            [PSCustomObject]@{ key = "temurin-21"; isCurrent = $true },
            [PSCustomObject]@{ key = "corretto-17"; isCurrent = $false }
        )
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { 
            if ($Key -eq "temurin-21") { return $versionEntry }
            if ($Key -eq "corretto-17") { return $replacementEntry }
        }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Get-AllVersions { return $allVersions }
        Mock Test-Path { 
            param($Path)
            return $true 
        }
        Mock Read-Host { 
            param($Prompt)
            if ($Prompt -like "*Which one*") { return "1" }
            return ""
        }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Switch-Version { return $true }
        Mock Set-CurrentVersion { return $true }
        Mock Remove-CurrentSymlink { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        Mock Write-Fail { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -like "*Which one*" }
        Should -Invoke Remove-Version -Times 1
        Should -Invoke Switch-Version -Times 1 -ParameterFilter { $TargetPath -eq "C:\Program Files\Java\jdk-17" }
        Should -Invoke Set-CurrentVersion -Times 1 -ParameterFilter { $Key -eq "corretto-17" }
        Should -Invoke Remove-CurrentSymlink -Times 0
        # Verify Write-Fail was not called (no invalid choice error)
        Should -Invoke Write-Fail -Times 0
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
            [PSCustomObject]@{ key = "temurin-21"; isCurrent = $true }
        )
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Get-AllVersions { return $allVersions }
        Mock Test-Path { return $true }
        Mock Read-Host { return "y" }
        Mock Remove-Item { }
        Mock Remove-Version { return $true }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Remove-CurrentSymlink { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Remove-Version -Times 1
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
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Read-Host -Times 1
        Should -Invoke Remove-Item -Times 0
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
            [PSCustomObject]@{ key = "temurin-21"; isCurrent = $true },
            [PSCustomObject]@{ key = "corretto-17"; isCurrent = $false }
        )
        
        Mock Test-VersionInstalled { return $true }
        Mock Get-Version { return $versionEntry }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Get-AllVersions { return $allVersions }
        Mock Read-Host { 
            if ($Prompt -like "*Which one*") { return "q" }
        }
        Mock Remove-Item { }
        Mock Remove-Version { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        
        Invoke-Uninstall -Key "temurin-21"
        
        Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -like "*Which one*" }
        Should -Invoke Remove-Item -Times 0
        Should -Invoke Remove-Version -Times 0
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*cancelled*" }
    }
    }
}

