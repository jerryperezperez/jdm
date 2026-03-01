# jdm.tests.ps1
# Tests for jdm.ps1 - CLI entry point
# Note: the command router (switch block) is not tested here because it runs
# at dot-source time via $args and requires integration-level testing.

Describe "jdm Tests" {
    BeforeAll {
        # Stub out the dot-sourced dependencies so we can load jdm.ps1 in isolation
        function Invoke-Install { param($UserInput) }
        function Invoke-Use { param($Key) }
        function Invoke-List { }
        function Invoke-Uninstall { param($Key) }

        # Load only the function definitions by patching the dot-source calls
        $jdmPath = Join-Path $PSScriptRoot "..\module\jdm.ps1"
        $content = Get-Content $jdmPath -Raw

        # Remove the dot-source lines and the switch router block so only
        # function definitions are evaluated
        $content = $content -replace '(?m)^\. ".*?".*$', ''
        $content = $content -replace '(?ms)# Command router.*', ''

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
        It "calls Write-Host without throwing" {
            { Write-Step "doing something" } | Should -Not -Throw
        }

        It "accepts any string message" {
            { Write-Step "test message 123" } | Should -Not -Throw
        }
    }

    Describe "Write-Ok" {
        It "calls Write-Host without throwing" {
            { Write-Ok "all good" } | Should -Not -Throw
        }
    }

    Describe "Write-Fail" {
        It "calls Write-Host without throwing" {
            { Write-Fail "something broke" } | Should -Not -Throw
        }
    }

    Describe "Write-Title" {
        It "calls Write-Host without throwing" {
            { Write-Title "My Title" } | Should -Not -Throw
        }
    }

    # ── Show-Help ──────────────────────────────────────────────────────────────

    Describe "Show-Help" {
        It "runs without throwing" {
            { Show-Help } | Should -Not -Throw
        }

        It "outputs content to the host" {
            $output = & { Show-Help } 6>&1
            $output | Should -Not -BeNullOrEmpty
        }

        It "output includes jdm version string" {
            $output = & { Show-Help } 6>&1
            ($output -join "") | Should -Match "jdm"
        }

        It "output mentions install command" {
            $output = & { Show-Help } 6>&1
            ($output -join "") | Should -Match "install"
        }

        It "output mentions use command" {
            $output = & { Show-Help } 6>&1
            ($output -join "") | Should -Match "use"
        }

        It "output mentions list command" {
            $output = & { Show-Help } 6>&1
            ($output -join "") | Should -Match "list"
        }

        It "output mentions uninstall command" {
            $output = & { Show-Help } 6>&1
            ($output -join "") | Should -Match "uninstall"
        }

        It "output mentions supported vendors" {
            $output = & { Show-Help } 6>&1
            $joined = $output -join ""
            $joined | Should -Match "temurin"
            $joined | Should -Match "corretto"
            $joined | Should -Match "azul"
            $joined | Should -Match "microsoft"
        }
    }

    # ── Invoke-SelfUninstall ───────────────────────────────────────────────────

    Describe "Invoke-SelfUninstall" {
        It "cancels when user does not confirm" {
            Mock Read-Host { return "n" }
            Mock Write-Step { }

            { Invoke-SelfUninstall } | Should -Not -Throw

            Should -Invoke Read-Host -Times 1
            Should -Invoke Write-Step -Times 1 -ParameterFilter {
                $msg -match "cancelled"
            }
        }

        It "does not modify PATH when user cancels" {
            Mock Read-Host { return "n" }
            Mock Write-Step { }
            Mock Set-Item { }

            Invoke-SelfUninstall

            # Environment should not be touched on cancel
            Should -Invoke Set-Item -Times 0
        }

        It "proceeds with uninstall when user confirms with y" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Remove-Item { }
            Mock Write-Host { }

            # Mock environment variable calls
            $originalGetEnv = [Environment]::GetEnvironmentVariable
            Mock -CommandName "Invoke-Expression" { }

            # Intercept the actual environment calls
            $env:PATH_BACKUP = $env:PATH

            { Invoke-SelfUninstall } | Should -Not -Throw
        }

        It "calls Write-Step for each uninstall stage when confirmed" {
            Mock Read-Host { return "y" }
            Mock Write-Step { }
            Mock Write-Ok { }
            Mock Remove-Item { }
            Mock Write-Host { }

            Invoke-SelfUninstall

            Should -Invoke Write-Step -Times 3
        }

        It "calls Remove-Item to delete jdm folder when confirmed" {
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
    }
}
