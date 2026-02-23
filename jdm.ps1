# jdm - CLI entry point and command router

. "$PSScriptRoot\commands\install.ps1"
. "$PSScriptRoot\commands\use.ps1"
. "$PSScriptRoot\commands\list.ps1"
. "$PSScriptRoot\commands\uninstall.ps1"

function Write-Step { param($msg) Write-Host "  --> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Title { param($msg) Write-Host "`n$msg" -ForegroundColor Yellow }

$jdm_VERSION = "0.1.0"

function Show-Help {
    Write-Host ""
    Write-Host "  jdm v$jdm_VERSION - Java Version Manager for Windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host "    jdm COMMAND [arguments]" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host "    install VENDOR.VERSION   Install a JDK version" -ForegroundColor Gray
    Write-Host "    use     VENDOR-VERSION   Switch active Java version" -ForegroundColor Gray
    Write-Host "    list                     List installed versions" -ForegroundColor Gray
    Write-Host "    uninstall VENDOR-VERSION Remove an installed version" -ForegroundColor Gray
    Write-Host "    version                  Show jdm version" -ForegroundColor Gray
    Write-Host "    help                     Show this help message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    jdm install temurin.21" -ForegroundColor Cyan
    Write-Host "    jdm install corretto.17" -ForegroundColor Cyan
    Write-Host "    jdm use temurin-21" -ForegroundColor Cyan
    Write-Host "    jdm list" -ForegroundColor Cyan
    Write-Host "    jdm uninstall corretto-17" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Supported vendors:" -ForegroundColor White
    Write-Host "    temurin    Eclipse Temurin (Adoptium)" -ForegroundColor Gray
    Write-Host "    corretto   Amazon Corretto" -ForegroundColor Gray
    Write-Host "    azul       Azul Zulu" -ForegroundColor Gray
    Write-Host "    microsoft  Microsoft OpenJDK" -ForegroundColor Gray
    Write-Host ""
}

$command = $args[0]
$rest = $args[1..($args.Length - 1)]

switch ($command) {

    "install" {
        if (-not $rest[0]) {
            Write-Fail "Usage: jdm install VENDOR.VERSION"
            Write-Host "  Example: jdm install temurin.21" -ForegroundColor Cyan
        }
        else {
            Invoke-Install -UserInput $rest[0]
        }
    }

    "use" {
        if (-not $rest[0]) {
            Write-Fail "Usage: jdm use VENDOR-VERSION"
            Write-Host "  Example: jdm use temurin-21" -ForegroundColor Cyan
        }
        else {
            Invoke-Use -Key $rest[0]
        }
    }

    "list" {
        Invoke-List
    }

    "uninstall" {
        if (-not $rest[0]) {
            Write-Fail "Usage: jdm uninstall VENDOR-VERSION"
            Write-Host "  Example: jdm uninstall temurin-21" -ForegroundColor Cyan
        }
        else {
            Invoke-Uninstall -Key $rest[0]
        }
    }

    "version" {
        Write-Host ""
        Write-Host "  jdm v$jdm_VERSION" -ForegroundColor Cyan
        Write-Host ""
    }

    { $_ -in "help", "--help", "-h", "" } {
        Show-Help
    }

    default {
        Write-Host ""
        Write-Fail "Unknown command: '$command'"
        Show-Help
    }
}
