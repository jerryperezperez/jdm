# install.tests.ps1
# Tests for commands/install.ps1

Describe "Install Command Tests" {
    BeforeAll {
        # Load modules
        $wingetPath = Join-Path $PSScriptRoot "..\..\module\core\winget.ps1"
        . $wingetPath

        $registryPath = Join-Path $PSScriptRoot "..\..\module\core\registry.ps1"
        . $registryPath

        $symlinkPath = Join-Path $PSScriptRoot "..\..\module\core\symlink.ps1"
        . $symlinkPath

        $installPath = Join-Path $PSScriptRoot "..\..\module\commands\install.ps1"
        . $installPath
        
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

    Describe "Invoke-Install" {
        BeforeEach {
            # Create temp directory for USERPROFILE
            $script:tempUserProfile = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
            $script:originalUserProfile = $env:USERPROFILE
            $env:USERPROFILE = $script:tempUserProfile.FullName
            
            # Create .jdm\tmp directory
            $tmpDir = Join-Path $script:tempUserProfile.FullName ".jdm\tmp"
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        }
        
        AfterEach {
            $env:USERPROFILE = $script:originalUserProfile
            if (Test-Path $script:tempUserProfile) {
                Remove-Item $script:tempUserProfile -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "shows error when no packages found" {
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return @() }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Search-Winget -Times 1
        Should -Invoke Write-Fail -Times 1
        }
        
        It "shows error when no JDK packages found" {
        $results = @(
            [PSCustomObject]@{ Name = "Temurin JRE 21"; Id = "EclipseAdoptium.Temurin.JRE.21" }
        )
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return $results }
        Mock Filter-JDK { return @() }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Filter-JDK -Times 1
        Should -Invoke Write-Fail -Times 1
        }
        
        It "cancels when user cancels at selection" {
        $results = @(
            [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" },
            [PSCustomObject]@{ Name = "Temurin JDK 21 LTS"; Id = "EclipseAdoptium.Temurin.JDK.21.LTS" }
        )
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return $results }
        Mock Filter-JDK { return $results }
        Mock Select-Result { return $null }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Select-Result -Times 1
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*cancelled*" }
        }
        
        It "cancels when user cancels at confirmation" {
        $result = [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return @($result) }
        Mock Filter-JDK { return @($result) }
        Mock Select-Result { return $result }
        Mock Test-VersionInstalled { return $false }
        Mock Read-Host { return "n" }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Read-Host -Times 1
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*cancelled*" }
        }
        
        It "skips install when version is already installed and user declines reinstall" {
        $result = [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return @($result) }
        Mock Filter-JDK { return @($result) }
        Mock Select-Result { return $result }
        Mock Get-RegistryKey { return "temurin-21" }
        Mock Test-VersionInstalled { return $true }
        Mock Read-Host { return "n" }
        Mock Install-WithWinget { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Test-VersionInstalled -Times 1
        Should -Invoke Install-WithWinget -Times 0
        Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -like "*Skipping*" }
        }
        
        It "successfully installs and registers version" {
        $result = [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
        $realPath = "C:\Program Files\Eclipse Adoptium\jdk-21"
        $markerFile = Join-Path $script:tempUserProfile.FullName ".jdm\tmp\last_install_path.txt"
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return @($result) }
        Mock Filter-JDK { return @($result) }
        Mock Select-Result { return $result }
        Mock Get-RegistryKey { return "temurin-21" }
        Mock Test-VersionInstalled { return $false }
        Mock Read-Host { return "y" }
        Mock Install-WithWinget { 
            # Create marker file as Install-WithWinget would
            Set-Content $markerFile $realPath
            return $true
        }
        Mock Get-VendorFromId { return "temurin" }
        Mock Get-VersionFromId { return "21" }
        Mock Get-CurrentVersion { return $null }
        Mock Add-Version { return $true }
        Mock Switch-Version { return $true }
        Mock Set-CurrentVersion { return $true }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Install-WithWinget -Times 1
        Should -Invoke Add-Version -Times 1 -ParameterFilter { 
            $Key -eq "temurin-21" -and 
            $InstallPath -eq $realPath
        }
        Should -Invoke Switch-Version -Times 1
        Should -Invoke Set-CurrentVersion -Times 1
        }
        
        It "prompts user to switch when current version exists" {
        $result = [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
        $realPath = "C:\Program Files\Eclipse Adoptium\jdk-21"
        $markerFile = Join-Path $script:tempUserProfile.FullName ".jdm\tmp\last_install_path.txt"
        
        Mock Build-Query { return "temurin.21" }
        Mock Search-Winget { return @($result) }
        Mock Filter-JDK { return @($result) }
        Mock Select-Result { return $result }
        Mock Get-RegistryKey { return "temurin-21" }
        Mock Test-VersionInstalled { return $false }
        Mock Read-Host { 
            if ($Prompt -like "*Proceed*") { return "y" }
            if ($Prompt -like "*Set*") { return "n" }
        }
        Mock Install-WithWinget { 
            Set-Content $markerFile $realPath
            return $true
        }
        Mock Get-VendorFromId { return "temurin" }
        Mock Get-VersionFromId { return "21" }
        Mock Get-CurrentVersion { return "corretto-17" }
        Mock Add-Version { return $true }
        Mock Switch-Version { }
        Mock Set-CurrentVersion { }
        Mock Write-Title { }
        Mock Write-Host { }
        Mock Write-Step { }
        Mock Write-Ok { }
        
        Invoke-Install -UserInput "temurin.21"
        
        Should -Invoke Read-Host -Times 2
        Should -Invoke Add-Version -Times 1
        Should -Invoke Switch-Version -Times 0
        }
    }

    Describe "Select-Result" {
        It "returns single result when only one is provided" {
        $result = [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" }
        
        $selected = Select-Result -Results @($result)
        $selected | Should -Not -BeNullOrEmpty
        $selected.Id | Should -Be "EclipseAdoptium.Temurin.JDK.21"
        }
        
        It "prompts user and returns selected result" {
        $results = @(
            [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" },
            [PSCustomObject]@{ Name = "Temurin JDK 21 LTS"; Id = "EclipseAdoptium.Temurin.JDK.21.LTS" }
        )
        
        Mock Read-Host { return "1" }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        $selected = Select-Result -Results $results
        $selected | Should -Not -BeNullOrEmpty
        $selected.Id | Should -Be "EclipseAdoptium.Temurin.JDK.21"
        
        Should -Invoke Read-Host -Times 1
        }
        
        It "returns null when user cancels" {
        $results = @(
            [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" },
            [PSCustomObject]@{ Name = "Temurin JDK 21 LTS"; Id = "EclipseAdoptium.Temurin.JDK.21.LTS" }
        )
        
        Mock Read-Host { return "q" }
        Mock Write-Host { }
        
        $selected = Select-Result -Results $results
        $selected | Should -BeNullOrEmpty
        
        Should -Invoke Read-Host -Times 1
        }
        
        It "returns null when invalid choice is made" {
        $results = @(
            [PSCustomObject]@{ Name = "Temurin JDK 21"; Id = "EclipseAdoptium.Temurin.JDK.21" },
            [PSCustomObject]@{ Name = "Temurin JDK 21 LTS"; Id = "EclipseAdoptium.Temurin.JDK.21.LTS" }
        )
        
        Mock Read-Host { return "99" }
        Mock Write-Host { }
        Mock Write-Fail { }
        
        $selected = Select-Result -Results $results
        $selected | Should -BeNullOrEmpty
        
        Should -Invoke Read-Host -Times 1
        Should -Invoke Write-Fail -Times 1
        }
    }
}

