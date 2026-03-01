# list.tests.ps1
# Tests for commands/list.ps1

Describe "List Command Tests" {
    BeforeAll {
        # Load modules
        $registryPath = Join-Path $PSScriptRoot "..\..\module\core\registry.ps1"
        . $registryPath

        $symlinkPath = Join-Path $PSScriptRoot "..\..\module\core\symlink.ps1"
        . $symlinkPath

        $listPath = Join-Path $PSScriptRoot "..\..\module\commands\list.ps1"
        . $listPath
        
        # Provide minimal stubs for functions used by these modules
        # (jdm.ps1 is not loaded as it auto-executes and breaks test discovery)
        if (-not (Get-Command Write-Title -ErrorAction SilentlyContinue)) {
            function Write-Title { param($msg) }
        }
        if (-not (Get-Command Write-Host -ErrorAction SilentlyContinue)) {
            function Write-Host { param($Object, $ForegroundColor, $NoNewline) }
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

    Describe "Invoke-List" {
    It "shows empty message when no versions are installed" {
        Mock Get-AllVersions { return @() }
        Mock Get-CurrentSymlinkTarget { }
        Mock Get-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-List
        
        Should -Invoke Get-AllVersions -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter { 
            $Object -like "*No Java versions installed*"
        }
    }
    
    It "displays single version with current marker" {
        $version = [PSCustomObject]@{
            key = "temurin-21"
            isCurrent = $true
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
        }
        
        Mock Get-AllVersions { return @($version) }
        Mock Get-CurrentSymlinkTarget { return "C:\Program Files\Java\jdk-21" }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-List
        
        Should -Invoke Get-AllVersions -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter { 
            $Object -like "*--> temurin-21*"
        }
    }
    
    It "displays multiple versions with correct current marker" {
        $versions = @(
            [PSCustomObject]@{
                key = "temurin-21"
                isCurrent = $true
                vendor = "temurin"
                version = "21"
                path = "C:\Program Files\Java\jdk-21"
            },
            [PSCustomObject]@{
                key = "corretto-17"
                isCurrent = $false
                vendor = "corretto"
                version = "17"
                path = "C:\Program Files\Java\jdk-17"
            }
        )
        
        Mock Get-AllVersions { return $versions }
        Mock Get-CurrentSymlinkTarget { return "C:\Program Files\Java\jdk-21" }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-List
        
        Should -Invoke Get-AllVersions -Times 1
        # Verify Write-Host was called with the current marker pattern
        Should -Invoke Write-Host -ParameterFilter { 
            $Object -like "*--> temurin-21*"
        }
        # Verify Write-Host was called for the non-current version (without marker)
        Should -Invoke Write-Host -ParameterFilter { 
            $Object -like "*corretto-17*" -and $Object -notlike "*-->*"
        }
    }
    
    It "shows warning when symlink is missing but current version is set" {
        $version = [PSCustomObject]@{
            key = "temurin-21"
            isCurrent = $true
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
        }
        
        Mock Get-AllVersions { return @($version) }
        Mock Get-CurrentSymlinkTarget { return $null }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-List
        
        Should -Invoke Get-CurrentSymlinkTarget -Times 1
        Should -Invoke Get-CurrentVersion -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter { 
            $Object -like "*Warning: symlink is missing*"
        }
    }
    
    It "does not show warning when symlink exists" {
        $version = [PSCustomObject]@{
            key = "temurin-21"
            isCurrent = $true
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
        }
        
        Mock Get-AllVersions { return @($version) }
        Mock Get-CurrentSymlinkTarget { return "C:\Program Files\Java\jdk-21" }
        Mock Get-CurrentVersion { return "temurin-21" }
        Mock Write-Title { }
        Mock Write-Host { }
        
        Invoke-List
        
        Should -Invoke Get-CurrentSymlinkTarget -Times 1
        Should -Not -Invoke Write-Host -ParameterFilter { 
            $Object -like "*Warning: symlink is missing*"
        }
    }
    }
}

