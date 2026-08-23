# jdm.tests.ps1
# Tests for module/jdm.ps1

Describe "jdm Tests" {
    BeforeAll {
        # Define stubs for external commands to prevent dot-source errors
        function Invoke-Install { param($UserInput) }
        function Invoke-Use { param($Key) }
        function Invoke-List { }
        function Invoke-Uninstall { param($Key) }
        function Invoke-UninstallAll { }

        # Dot-source the REAL file to track coverage
        # Ensure your jdm.ps1 has the 'if ($MyInvocation.InvocationName -ne ".")' guard!
        $jdmPath = Join-Path $PSScriptRoot "..\module\jdm.ps1"
        . $jdmPath
    }

    # ── Write-* helpers ────────────────────────────────────────────────────────

    Describe "Write-Step" {
        It "runs without throwing" {
            { Write-Step "test" } | Should -Not -Throw
        }
    }

    # ── Show-Help ──────────────────────────────────────────────────────────────

    Describe "Show-Help" {
        It "displays the correct version" {
            $output = & { Show-Help } 6>&1 | Out-String
            $output | Should -Match "jdm v0.2.0"
        }
    }

    # ── Invoke-SelfUninstall ───────────────────────────────────────────────────

    Describe "Invoke-SelfUninstall" {
        It "stops if user does not confirm with 'y'" {
            Mock Read-Host { return "n" }
            Mock Write-Host { }
            Mock Write-Step { }

            Invoke-SelfUninstall

            # Standalone call (NO PIPE)
            Should -Invoke Write-Step -Times 1 -ParameterFilter { $msg -match "cancelled" }
        }

        It "calls Write-Step 3 times and Write-Ok 3 times on successful uninstall" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            Should -Invoke Write-Step -Times 3
            Should -Invoke Write-Ok -Times 3
        }

        It "executes without error when user confirms" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            { Invoke-SelfUninstall } | Should -Not -Throw
        }

        It "calls Write-Host multiple times with detailed messages" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            Invoke-SelfUninstall

            # Write-Host is called at the beginning (blank line), during uninstall, and at the end (multiple messages)
            Should -Invoke Write-Host -Times 21
        }

        It "warns when machine PATH still contains java entries" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Write-Host { }
            Mock Remove-Item { }

            # inject a fake machine path value via variable that our test loader patches
            $script:TestMachinePath = "C:\\foo;jdkbar"

            Invoke-SelfUninstall

            Should -Invoke Write-Host -ParameterFilter { $Object -like "*Warning: Machine level PATH*" }
        }
    }

    # ── Invoke-Jdm (Router) ────────────────────────────────────────────────────

    Describe "Invoke-Jdm" {
        It "routes 'install' correctly" {
            Mock Invoke-Install { }

            Invoke-Jdm -command "install" -rest @("temurin.21")

            Should -Invoke Invoke-Install -Times 1 -ParameterFilter { $UserInput -eq "temurin.21" }
        }

        It "routes 'uninstall --self' to Invoke-SelfUninstall" {
            Mock Invoke-SelfUninstall { }

            Invoke-Jdm -command "uninstall" -rest @("--self")

            Should -Invoke Invoke-SelfUninstall -Times 1
        }

        It "routes 'uninstall --all-vendors' to Invoke-UninstallAll" {
            Mock Invoke-UninstallAll { }

            Invoke-Jdm -command "uninstall" -rest @("--all-vendors")

            Should -Invoke Invoke-UninstallAll -Times 1
        }

        It "shows error for unknown commands" {
            Mock Write-Fail { }
            Mock Show-Help { }
            Mock Write-Host { }

            Invoke-Jdm -command "invalid" -rest @()

            Should -Invoke Write-Fail -Times 1
            Should -Invoke Show-Help -Times 1
        }
    }
}
