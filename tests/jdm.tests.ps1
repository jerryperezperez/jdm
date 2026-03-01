# jdm.tests.ps1
# Tests for module/jdm.ps1 - CLI entry point and command router

Describe "jdm Tests" {
    BeforeAll {
        # Stub out dot-sourced dependencies before loading jdm.ps1
        function Invoke-Install { param($UserInput) }
        function Invoke-Use { param($Key) }
        function Invoke-List { }
        function Invoke-Uninstall { param($Key) }

        # Strip the dot-source lines and the final entry point call
        # so we can load only the function definitions cleanly
        $jdmPath = Join-Path $PSScriptRoot "..\module\jdm.ps1"
        $content = Get-Content $jdmPath -Raw

        $content = $content -replace '(?m)^\. ".*?".*$', ''
        $content = $content -replace '(?m)^Invoke-Jdm.*$', ''

        $tempFile = Join-Path $env:TEMP "jdm.tests.temp.ps1"
        $content | Set-Content $tempFile -Encoding UTF8
        . $tempFile
    }

    AfterAll {
        $tempFile = Join-Path $env:TEMP "jdm.tests.temp.ps1"
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }

    # ── Write-* helpers ────────────────────────────────────────────────────────

    Describe "Write-Step" {
        It "runs without throwing" {
            { Write-Step "doing something" } | Should -Not -Throw
        }
    }

    Describe "Write-Ok" {
        It "runs without throwing" {
            { Write-Ok "all good" } | Should -Not -Throw
        }
    }

    Describe "Write-Fail" {
        It "runs without throwing" {
            { Write-Fail "something broke" } | Should -Not -Throw
        }
    }

    Describe "Write-Title" {
        It "runs without throwing" {
            { Write-Title "My Title" } | Should -Not -Throw
        }
    }

    # ── Show-Help ──────────────────────────────────────────────────────────────

    Describe "Show-Help" {
        It "runs without throwing" {
            { Show-Help } | Should -Not -Throw
        }

        It "mentions all commands" {
            $output = & { Show-Help } 6>&1 | Out-String
            $output | Should -Match "install"
            $output | Should -Match "use"
            $output | Should -Match "list"
            $output | Should -Match "uninstall"
            $output | Should -Match "version"
            $output | Should -Match "help"
        }

        It "mentions all supported vendors" {
            $output = & { Show-Help } 6>&1 | Out-String
            $output | Should -Match "temurin"
            $output | Should -Match "corretto"
            $output | Should -Match "azul"
            $output | Should -Match "microsoft"
        }

        It "includes version string" {
            $output = & { Show-Help } 6>&1 | Out-String
            $output | Should -Match "jdm v\d+\.\d+\.\d+"
        }

        It "includes usage examples" {
            $output = & { Show-Help } 6>&1 | Out-String
            $output | Should -Match "jdm install temurin"
            $output | Should -Match "jdm use temurin"
            $output | Should -Match "jdm list"
            $output | Should -Match "jdm uninstall"
        }
    }

    # ── Invoke-SelfUninstall ───────────────────────────────────────────────────

    Describe "Invoke-SelfUninstall" {
        It "cancels and does not proceed when user enters n" {
            Mock Read-Host { return "n" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Read-Host   -Times 1
            Should -Invoke Write-Step  -Times 1 -ParameterFilter { $msg -match "cancelled" }
            Should -Invoke Remove-Item -Times 0
        }

        It "cancels when user enters anything other than y" {
            Mock Read-Host { return "no" }
            Mock Write-Step { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Remove-Item -Times 0
        }

        It "proceeds without throwing when user enters y" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            { Invoke-SelfUninstall } | Should -Not -Throw
        }

        It "calls Write-Step 3 times when confirmed" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Write-Step -Times 3
        }

        It "removes the .jdm folder when confirmed" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Remove-Item -Times 1 -ParameterFilter {
                $Path -match "\.jdm"
            }
        }

        It "calls Write-Ok 3 times when confirmed" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Write-Ok -Times 3
        }
    }

    # ── Invoke-Jdm router ──────────────────────────────────────────────────────

    Describe "Invoke-Jdm" {

        Describe "install command" {
            It "calls Invoke-Install with correct argument" {
                Mock Invoke-Install { }

                Invoke-Jdm -command "install" -rest @("temurin.21")

                Should -Invoke Invoke-Install -Times 1 -ParameterFilter {
                    $UserInput -eq "temurin.21"
                }
            }

            It "shows usage error when no argument provided" {
                Mock Invoke-Install { }
                Mock Write-Fail { }
                Mock Write-Host { }

                Invoke-Jdm -command "install" -rest @()

                Should -Invoke Invoke-Install -Times 0
                Should -Invoke Write-Fail     -Times 1
            }
        }

        Describe "use command" {
            It "calls Invoke-Use with correct argument" {
                Mock Invoke-Use { }

                Invoke-Jdm -command "use" -rest @("temurin-21")

                Should -Invoke Invoke-Use -Times 1 -ParameterFilter {
                    $Key -eq "temurin-21"
                }
            }

            It "shows usage error when no argument provided" {
                Mock Invoke-Use { }
                Mock Write-Fail { }
                Mock Write-Host { }

                Invoke-Jdm -command "use" -rest @()

                Should -Invoke Invoke-Use -Times 0
                Should -Invoke Write-Fail -Times 1
            }
        }

        Describe "list command" {
            It "calls Invoke-List" {
                Mock Invoke-List { }

                Invoke-Jdm -command "list" -rest @()

                Should -Invoke Invoke-List -Times 1
            }
        }

        Describe "uninstall command" {
            It "calls Invoke-Uninstall with correct argument" {
                Mock Invoke-Uninstall { }

                Invoke-Jdm -command "uninstall" -rest @("temurin-21")

                Should -Invoke Invoke-Uninstall -Times 1 -ParameterFilter {
                    $Key -eq "temurin-21"
                }
            }

            It "calls Invoke-SelfUninstall when --self flag is passed" {
                Mock Invoke-SelfUninstall { }

                Invoke-Jdm -command "uninstall" -rest @("--self")

                Should -Invoke Invoke-SelfUninstall -Times 1
            }

            It "shows usage error when no argument provided" {
                Mock Invoke-Uninstall { }
                Mock Write-Fail { }
                Mock Write-Host { }

                Invoke-Jdm -command "uninstall" -rest @()

                Should -Invoke Invoke-Uninstall -Times 0
                Should -Invoke Write-Fail       -Times 1
            }
        }

        Describe "version command" {
            It "outputs version string without throwing" {
                Mock Write-Host { }

                { Invoke-Jdm -command "version" -rest @() } | Should -Not -Throw

                Should -Invoke Write-Host -Times 3
            }
        }

        Describe "help command" {
            It "calls Show-Help for 'help'" {
                Mock Show-Help { }

                Invoke-Jdm -command "help" -rest @()

                Should -Invoke Show-Help -Times 1
            }

            It "calls Show-Help for '--help'" {
                Mock Show-Help { }

                Invoke-Jdm -command "--help" -rest @()

                Should -Invoke Show-Help -Times 1
            }

            It "calls Show-Help for '-h'" {
                Mock Show-Help { }

                Invoke-Jdm -command "-h" -rest @()

                Should -Invoke Show-Help -Times 1
            }

            It "calls Show-Help when no command given" {
                Mock Show-Help { }

                Invoke-Jdm -command "" -rest @()

                Should -Invoke Show-Help -Times 1
            }
        }

        Describe "default/unknown command" {
            It "shows error and help for unknown command" {
                Mock Write-Fail { }
                Mock Write-Host { }
                Mock Show-Help { }

                Invoke-Jdm -command "foobar" -rest @()

                Should -Invoke Write-Fail -Times 1
                Should -Invoke Show-Help  -Times 1
            }

            It "includes the unknown command name in the error message" {
                $script:captured = $null
                Mock Write-Fail { $script:captured = $msg }
                Mock Write-Host { }
                Mock Show-Help { }

                Invoke-Jdm -command "badcmd" -rest @()

                $script:captured | Should -Match "badcmd"
            }
        }
    }
}
