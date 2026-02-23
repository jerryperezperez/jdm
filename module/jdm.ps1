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
    Write-Host "    uninstall VENDOR-VERSION Remove an installed JDK version" -ForegroundColor Gray
    Write-Host "    uninstall --self         Remove jdm from this machine" -ForegroundColor Gray
    Write-Host "    version                  Show jdm version" -ForegroundColor Gray
    Write-Host "    help                     Show this help message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    jdm install temurin.21" -ForegroundColor Cyan
    Write-Host "    jdm install corretto.17" -ForegroundColor Cyan
    Write-Host "    jdm use temurin-21" -ForegroundColor Cyan
    Write-Host "    jdm list" -ForegroundColor Cyan
    Write-Host "    jdm uninstall corretto-17" -ForegroundColor Cyan
    Write-Host "    jdm uninstall --self" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Supported vendors:" -ForegroundColor White
    Write-Host "    temurin    Eclipse Temurin (Adoptium)" -ForegroundColor Gray
    Write-Host "    corretto   Amazon Corretto" -ForegroundColor Gray
    Write-Host "    azul       Azul Zulu" -ForegroundColor Gray
    Write-Host "    microsoft  Microsoft OpenJDK" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-SelfUninstall {
    Write-Host ""
    Write-Host "  This will remove jdm and all its files from your machine." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The following will be removed:" -ForegroundColor White
    Write-Host "    - $env:USERPROFILE\.jdm\" -ForegroundColor Gray
    Write-Host "    - jdm from user PATH" -ForegroundColor Gray
    Write-Host "    - JAVA_HOME (user level)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  The following will NOT be removed:" -ForegroundColor White
    Write-Host "    - Your JDKs in $env:USERPROFILE\.jdks\" -ForegroundColor Gray
    Write-Host "    - Machine level PATH entries (requires manual Admin cleanup)" -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "  Are you sure you want to uninstall jdm? (y/n)"
    if ($confirm -ne "y") {
        Write-Step "Uninstall cancelled."
        return
    }

    Write-Step "Removing jdm from PATH..."
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $cleaned = $currentPath -split ";" | Where-Object { $_ -notmatch "jdm" -and $_ -ne "" }
    [Environment]::SetEnvironmentVariable("PATH", $cleaned -join ";", "User")
    Write-Ok "Removed from PATH"

    Write-Step "Removing JAVA_HOME..."
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, "User")
    Write-Ok "Removed JAVA_HOME"

    Write-Step "Removing jdm files..."
    Remove-Item "$env:USERPROFILE\.jdm" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Removed $env:USERPROFILE\.jdm"

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $hasJava = $machinePath -split ";" | Where-Object { $_ -match "jdk|java|temurin|corretto|zulu|jdm" }

    Write-Host ""
    Write-Ok "jdm has been uninstalled!"
    Write-Host ""

    if ($hasJava) {
        Write-Host "  [!] Warning: Machine level PATH still has Java entries:" -ForegroundColor Yellow
        $hasJava | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "  Run PowerShell as Administrator to clean these up." -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "  Your JDKs are still in $env:USERPROFILE\.jdks\" -ForegroundColor Gray
    Write-Host "  Delete that folder manually if you want to remove them too." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Open a new terminal for changes to take effect." -ForegroundColor Cyan
    Write-Host ""
}

# Command router
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
        elseif ($rest[0] -eq "--self") {
            Invoke-SelfUninstall
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
