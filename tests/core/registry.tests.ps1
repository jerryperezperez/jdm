# registry.tests.ps1
# Tests for core/registry.ps1 using temp registry files

Describe "Registry Tests" {
    BeforeAll {
        # Load registry module
        $modulePath = Join-Path $PSScriptRoot "..\..\module\core\registry.ps1"
        . $modulePath
        
        # Provide minimal stubs for functions used by registry.ps1
        # (jdm.ps1 is not loaded as it auto-executes and breaks test discovery)
        if (-not (Get-Command Write-Fail -ErrorAction SilentlyContinue)) {
            function Write-Fail { param($msg) }
        }
        if (-not (Get-Command Write-Step -ErrorAction SilentlyContinue)) {
            function Write-Step { param($msg) }
        }
    }
    
    # Override REGISTRY_PATH for all tests to use temp files
    BeforeEach {
        $script:tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
        $script:testRegistryPath = Join-Path $script:tempDir "registry.json"
        # Override the variable from registry.ps1 - functions reference it from current scope
        $REGISTRY_PATH = $script:testRegistryPath
        # Also set in script scope to ensure functions can access it
        Set-Variable -Name REGISTRY_PATH -Value $script:testRegistryPath -Scope Script -Force
    }

    AfterEach {
        if (Test-Path $script:tempDir) {
            Remove-Item $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Describe "Get-Registry" {
    
    It "returns null when registry file does not exist" {
        $result = Get-Registry
        $result | Should -BeNullOrEmpty
    }
    
    It "returns registry object for valid JSON" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{
                            id = "EclipseAdoptium.Temurin.JDK.21"
                            vendor = "temurin"
                            version = "21"
                            path = "C:\Program Files\Java\jdk-21"
                            installedAt = "2024-01-01"
                        }
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-Registry
        $result | Should -Not -BeNullOrEmpty
        $result.candidates.java.installed | Should -Contain "temurin-21"
        $result.candidates.java.current | Should -Be "temurin-21"
    }
    
    It "returns null for invalid JSON" {
        "invalid json content" | Set-Content $script:testRegistryPath
        
        Mock Write-Fail { }
        $result = Get-Registry
        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Fail -Times 1
    }
}

Describe "Set-Registry" {
    
    It "writes registry object to file and returns true" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        
        $result = Set-Registry -Registry $registry
        $result | Should -Be $true
        
        $fileContent = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
        $fileContent.candidates.java.current | Should -Be "temurin-21"
    }
    
    It "round-trips JSON correctly" {
        $original = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21", "corretto-17")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{
                            id = "EclipseAdoptium.Temurin.JDK.21"
                            vendor = "temurin"
                            version = "21"
                            path = "C:\Program Files\Java\jdk-21"
                            installedAt = "2024-01-01"
                        }
                    }
                }
            }
        }
        
        Set-Registry -Registry $original
        $readBack = Get-Registry
        $readBack.candidates.java.installed.Count | Should -Be 2
        $readBack.candidates.java.current | Should -Be "temurin-21"
    }
}

Describe "Test-VersionInstalled" {
    
    It "returns false when registry is missing" {
        $result = Test-VersionInstalled -Key "temurin-21"
        $result | Should -Be $false
    }
    
    It "returns true when version is in installed list" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21", "corretto-17")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Test-VersionInstalled -Key "temurin-21"
        $result | Should -Be $true
    }
    
    It "returns false when version is not in installed list" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Test-VersionInstalled -Key "corretto-17"
        $result | Should -Be $false
    }
}

Describe "Get-CurrentVersion" {
    
    It "returns null when registry is missing" {
        $result = Get-CurrentVersion
        $result | Should -BeNullOrEmpty
    }
    
    It "returns current version key when set" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-CurrentVersion
        $result | Should -Be "temurin-21"
    }
    
    It "returns null when current is not set" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = $null
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-CurrentVersion
        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-Version" {
    
    It "returns version entry for existing key" {
        $versionEntry = @{
            id = "EclipseAdoptium.Temurin.JDK.21"
            vendor = "temurin"
            version = "21"
            path = "C:\Program Files\Java\jdk-21"
            installedAt = "2024-01-01"
        }
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = $versionEntry
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-Version -Key "temurin-21"
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be "EclipseAdoptium.Temurin.JDK.21"
        $result.vendor | Should -Be "temurin"
        $result.version | Should -Be "21"
        $result.path | Should -Be "C:\Program Files\Java\jdk-21"
    }
    
    It "returns null and logs error for missing key" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        Mock Write-Fail { }
        $result = Get-Version -Key "corretto-17"
        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Fail -Times 1
    }
}

Describe "Get-AllVersions" {
    
    It "returns empty array when registry is missing" {
        $result = Get-AllVersions
        $result | Should -Be @()
        $result.Count | Should -Be 0
    }
    
    It "returns array with key and isCurrent properties" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21", "corretto-17")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{
                            id = "EclipseAdoptium.Temurin.JDK.21"
                            vendor = "temurin"
                            version = "21"
                            path = "C:\Program Files\Java\jdk-21"
                            installedAt = "2024-01-01"
                        }
                        "corretto-17" = @{
                            id = "Amazon.Corretto.17"
                            vendor = "corretto"
                            version = "17"
                            path = "C:\Program Files\Java\jdk-17"
                            installedAt = "2024-01-01"
                        }
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-AllVersions
        $result.Count | Should -Be 2
        
        $temurin = $result | Where-Object { $_.key -eq "temurin-21" }
        $temurin | Should -Not -BeNullOrEmpty
        $temurin.isCurrent | Should -Be $true
        
        $corretto = $result | Where-Object { $_.key -eq "corretto-17" }
        $corretto | Should -Not -BeNullOrEmpty
        $corretto.isCurrent | Should -Be $false
    }
    
    It "returns empty array when no versions exist" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @()
                    current = $null
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Get-AllVersions
        $result | Should -Be @()
        $result.Count | Should -Be 0
    }
}

Describe "Add-Version" {
    BeforeEach {
        # Create base registry
        $baseRegistry = @{
            candidates = @{
                java = @{
                    installed = @()
                    current = $null
                    versions = @{}
                }
            }
        }
        $baseRegistry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
    }
    
    It "adds new version to registry" {
        $result = [PSCustomObject]@{
            Id = "EclipseAdoptium.Temurin.JDK.21"
            Name = "Eclipse Temurin JDK 21"
        }
        
        $added = Add-Version -Key "temurin-21" -Result $result -InstallPath "C:\Program Files\Java\jdk-21" -Vendor "temurin" -Version "21"
        $added | Should -Be $true
        
        $registry = Get-Registry
        $registry.candidates.java.installed | Should -Contain "temurin-21"
        $registry.candidates.java.versions."temurin-21" | Should -Not -BeNullOrEmpty
        $registry.candidates.java.versions."temurin-21".id | Should -Be "EclipseAdoptium.Temurin.JDK.21"
    }
    
    It "sets current version when it's the first install" {
        $result = [PSCustomObject]@{
            Id = "EclipseAdoptium.Temurin.JDK.21"
            Name = "Eclipse Temurin JDK 21"
        }
        
        Mock Write-Step { }
        Add-Version -Key "temurin-21" -Result $result -InstallPath "C:\Program Files\Java\jdk-21" -Vendor "temurin" -Version "21"
        
        $registry = Get-Registry
        $registry.candidates.java.current | Should -Be "temurin-21"
        Should -Invoke Write-Step -Times 1
    }
    
    It "does not add duplicate to installed list" {
        $result = [PSCustomObject]@{
            Id = "EclipseAdoptium.Temurin.JDK.21"
            Name = "Eclipse Temurin JDK 21"
        }
        
        Add-Version -Key "temurin-21" -Result $result -InstallPath "C:\Program Files\Java\jdk-21" -Vendor "temurin" -Version "21"
        Add-Version -Key "temurin-21" -Result $result -InstallPath "C:\Program Files\Java\jdk-21" -Vendor "temurin" -Version "21"
        
        $registry = Get-Registry
        $registry.candidates.java.installed.Count | Should -Be 1
    }
    
    It "sets installedAt to current date" {
        $result = [PSCustomObject]@{
            Id = "EclipseAdoptium.Temurin.JDK.21"
            Name = "Eclipse Temurin JDK 21"
        }
        
        $today = Get-Date -Format "yyyy-MM-dd"
        Add-Version -Key "temurin-21" -Result $result -InstallPath "C:\Program Files\Java\jdk-21" -Vendor "temurin" -Version "21"
        
        $registry = Get-Registry
        $registry.candidates.java.versions."temurin-21".installedAt | Should -Be $today
    }
}

Describe "Set-CurrentVersion" {
    
    It "returns false when key is not installed" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        Mock Write-Fail { }
        $result = Set-CurrentVersion -Key "corretto-17"
        $result | Should -Be $false
        Should -Invoke Write-Fail -Times 1
    }
    
    It "updates current version when key is installed" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21", "corretto-17")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{}
                        "corretto-17" = @{}
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Set-CurrentVersion -Key "corretto-17"
        $result | Should -Be $true
        
        $updated = Get-Registry
        $updated.candidates.java.current | Should -Be "corretto-17"
    }
}

Describe "Remove-Version" {
    
    It "returns false when key is not installed" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{}
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        Mock Write-Fail { }
        $result = Remove-Version -Key "corretto-17"
        $result | Should -Be $false
        Should -Invoke Write-Fail -Times 1
    }
    
    It "removes non-current version from registry" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21", "corretto-17")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{}
                        "corretto-17" = @{}
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        $result = Remove-Version -Key "corretto-17"
        $result | Should -Be $true
        
        $updated = Get-Registry
        $updated.candidates.java.installed | Should -Not -Contain "corretto-17"
        $updated.candidates.java.versions.PSObject.Properties.Name | Should -Not -Contain "corretto-17"
        $updated.candidates.java.current | Should -Be "temurin-21"
    }
    
    It "clears current pointer when removing active version" {
        $registry = @{
            candidates = @{
                java = @{
                    installed = @("temurin-21")
                    current = "temurin-21"
                    versions = @{
                        "temurin-21" = @{}
                    }
                }
            }
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        
        Mock Write-Step { }
        $result = Remove-Version -Key "temurin-21"
        $result | Should -Be $true
        
        $updated = Get-Registry
        $updated.candidates.java.current | Should -BeNullOrEmpty
        Should -Invoke Write-Step -Times 1
    }
    }
}

