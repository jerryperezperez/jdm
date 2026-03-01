# symlink.tests.ps1
# Tests for core/symlink.ps1 with mocked side effects

Describe "Symlink Tests" {
    BeforeAll {
        # Load symlink module
        $modulePath = Join-Path $PSScriptRoot "..\..\module\core\symlink.ps1"
        . $modulePath
        
        # Provide minimal stubs for functions used by symlink.ps1
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

    Describe "Test-SymlinkCapability" {
        It "returns true when admin wrapper returns true" {
            Mock Get-CurrentPrincipalIsAdmin { return $true }
            Mock Get-DevModeEnabled { return $false }
            
            $result = Test-SymlinkCapability
            $result | Should -Be $true
            
            Should -Invoke Get-CurrentPrincipalIsAdmin -Times 1
            Should -Invoke Get-DevModeEnabled -Times 0
        }
        
        It "returns true when admin is false but dev mode is enabled" {
            Mock Get-CurrentPrincipalIsAdmin { return $false }
            Mock Get-DevModeEnabled { return $true }
            
            $result = Test-SymlinkCapability
            $result | Should -Be $true
            
            Should -Invoke Get-CurrentPrincipalIsAdmin -Times 1
            Should -Invoke Get-DevModeEnabled -Times 1
        }
        
        It "returns false when both admin and dev mode are false" {
            Mock Get-CurrentPrincipalIsAdmin { return $false }
            Mock Get-DevModeEnabled { return $false }
            
            $result = Test-SymlinkCapability
            $result | Should -Be $false
            
            Should -Invoke Get-CurrentPrincipalIsAdmin -Times 1
            Should -Invoke Get-DevModeEnabled -Times 1
        }
    }

    Describe "Get-CurrentSymlinkTarget" {
        It "returns null when symlink path does not exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*current*" }
            Mock Get-Item { }
            
            $result = Get-CurrentSymlinkTarget
            $result | Should -BeNullOrEmpty
            
            Should -Invoke Test-Path -Times 1
            Should -Invoke Get-Item -Times 0
        }
        
        It "returns target when symlink exists and is valid" {
            $mockItem = [PSCustomObject]@{
                LinkType = "SymbolicLink"
                Target = "C:\Program Files\Java\jdk-21"
            }
            
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*current*" }
            Mock Get-Item { return $mockItem } -ParameterFilter { $Path -like "*current*" }
            
            $result = Get-CurrentSymlinkTarget
            $result | Should -Be "C:\Program Files\Java\jdk-21"
            
            Should -Invoke Test-Path -Times 1
            Should -Invoke Get-Item -Times 1
        }
        
        It "returns null when path exists but is not a symlink" {
            $mockItem = [PSCustomObject]@{
                LinkType = "Directory"
                Target = $null
            }
            
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*current*" }
            Mock Get-Item { return $mockItem } -ParameterFilter { $Path -like "*current*" }
            
            $result = Get-CurrentSymlinkTarget
            $result | Should -BeNullOrEmpty
            
            Should -Invoke Test-Path -Times 1
            Should -Invoke Get-Item -Times 1
        }
    }

    Describe "Switch-Version" {
        It "returns false when Set-CurrentSymlink fails" {
            Mock Set-CurrentSymlink { return $false }
            Mock Repair-JavaPath { }
            Mock Set-JavaHome { }
            Mock Write-Step { }
            
            $result = Switch-Version -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $false
            
            Should -Invoke Set-CurrentSymlink -Times 1 -ParameterFilter { $TargetPath -eq "C:\Program Files\Java\jdk-21" }
            Should -Invoke Repair-JavaPath -Times 0
            Should -Invoke Set-JavaHome -Times 0
        }
        
        It "returns true and calls Repair-JavaPath and Set-JavaHome when Set-CurrentSymlink succeeds and java.exe exists" {
            Mock Set-CurrentSymlink { return $true }
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*java.exe*" }
            Mock Repair-JavaPath { }
            Mock Set-JavaHome { }
            Mock Write-Step { }
            Mock Write-Ok { }
            
            $result = Switch-Version -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $true
            
            Should -Invoke Set-CurrentSymlink -Times 1 -ParameterFilter { $TargetPath -eq "C:\Program Files\Java\jdk-21" }
            Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -like "*java.exe*" }
            Should -Invoke Repair-JavaPath -Times 1
            Should -Invoke Set-JavaHome -Times 1
        }
        
        It "returns true but logs warning when Set-CurrentSymlink succeeds but java.exe is missing" {
            Mock Set-CurrentSymlink { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*java.exe*" }
            Mock Repair-JavaPath { }
            Mock Set-JavaHome { }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Fail { }
            
            $result = Switch-Version -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $true
            
            Should -Invoke Set-CurrentSymlink -Times 1
            Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -like "*java.exe*" }
            Should -Invoke Write-Fail -Times 1
            Should -Invoke Repair-JavaPath -Times 1
            Should -Invoke Set-JavaHome -Times 1
        }
    }

    Describe "Set-CurrentSymlink" {
        It "returns false when Test-SymlinkCapability returns false" {
            Mock Test-SymlinkCapability { return $false }
            Mock Write-Fail { }
            
            $result = Set-CurrentSymlink -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $false
            
            Should -Invoke Test-SymlinkCapability -Times 1
            Should -Invoke Write-Fail -Times 1
        }
        
        It "returns false when target path does not exist" {
            Mock Test-SymlinkCapability { return $true }
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
            Mock Write-Fail { }
            
            $result = Set-CurrentSymlink -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $false
            
            Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "C:\Program Files\Java\jdk-21" }
        }
        
        It "removes existing symlink and creates new one successfully" {
            Mock Test-SymlinkCapability { return $true }
            Mock Test-Path { 
                if ($Path -eq "C:\Program Files\Java\jdk-21") { return $true }
                if ($Path -like "*current*") { return $true }
                return $false
            }
            Mock Remove-Item { }
            Mock New-Item { return $null }
            Mock Write-Step { }
            Mock Write-Ok { }
            
            $result = Set-CurrentSymlink -TargetPath "C:\Program Files\Java\jdk-21"
            $result | Should -Be $true
            
            Should -Invoke Remove-Item -Times 1
            Should -Invoke New-Item -Times 1 -ParameterFilter { 
                $ItemType -eq "SymbolicLink" -and 
                $Path -like "*current*" -and 
                $Target -eq "C:\Program Files\Java\jdk-21"
            }
        }
    }

    Describe "Repair-JavaPath" {
        It "updates user PATH and machine PATH when admin" {
            Mock Get-CurrentPrincipalIsAdmin { return $true }
            Mock Get-JdmEnvVariable { 
                if ($Target -eq "User") { return "C:\Old\Path;C:\Java\bin" }
                if ($Target -eq "Machine") { return "C:\Machine\Path" }
            }
            Mock Set-JdmEnvVariable { }
            Mock Write-Ok { }
            
            Repair-JavaPath
            
            Should -Invoke Get-JdmEnvVariable -Times 2
            Should -Invoke Set-JdmEnvVariable -Times 2
            Should -Invoke Write-Ok -Times 2
        }
        
        It "updates only user PATH when not admin" {
            Mock Get-CurrentPrincipalIsAdmin { return $false }
            Mock Get-JdmEnvVariable { 
                if ($Target -eq "User") { return "C:\Old\Path;C:\Java\bin" }
            }
            Mock Set-JdmEnvVariable { }
            Mock Write-Ok { }
            Mock Write-Step { }
            
            Repair-JavaPath
            
            Should -Invoke Get-JdmEnvVariable -Times 1 -ParameterFilter { $Target -eq "User" }
            Should -Invoke Set-JdmEnvVariable -Times 1 -ParameterFilter { $Target -eq "User" }
            Should -Invoke Write-Ok -Times 1
            Should -Invoke Write-Step -Times 1
        }
    }

    Describe "Set-JavaHome" {
        It "sets JAVA_HOME for user and machine when admin" {
            Mock Get-CurrentPrincipalIsAdmin { return $true }
            Mock Set-JdmEnvVariable { }
            Mock Write-Ok { }
            
            Set-JavaHome
            
            Should -Invoke Set-JdmEnvVariable -Times 2
            Should -Invoke Write-Ok -Times 1
        }
        
        It "sets JAVA_HOME only for user when not admin" {
            Mock Get-CurrentPrincipalIsAdmin { return $false }
            Mock Set-JdmEnvVariable { }
            Mock Write-Ok { }
            
            Set-JavaHome
            
            Should -Invoke Set-JdmEnvVariable -Times 1 -ParameterFilter { $Target -eq "User" }
            Should -Invoke Write-Ok -Times 1
        }
    }
}
