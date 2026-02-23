# myTool - install.ps1
# One-time setup script
# Usage: .\install.ps1 (from inside the repo folder)

$ErrorActionPreference = "Stop"

$TOOL_NAME = "myTool"
$TOOL_DIR = "$env:USERPROFILE\.myTool"
$MODULE_DIR = "$TOOL_DIR\module"
$REGISTRY = "$TOOL_DIR\registry.json"
$SYMLINK_DIR = "$TOOL_DIR\candidates\java"
$CURRENT = "$SYMLINK_DIR\current"
$JAVA_BIN = "$CURRENT\bin"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$MODULE_SRC = "$SCRIPT_DIR\module"

function Write-Step { param($msg) Write-Host "  --> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Title { param($msg) Write-Host "`n$msg" -ForegroundColor Yellow }

function Test-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Initialize-Folders {
    Write-Step "Creating folder structure..."

    $folders = @(
        $TOOL_DIR,
        "$TOOL_DIR\candidates",
        "$TOOL_DIR\candidates\java",
        "$TOOL_DIR\tmp",
        $MODULE_DIR,
        "$MODULE_DIR\commands",
        "$MODULE_DIR\core"
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }

    Write-Ok "Folders created at $TOOL_DIR"
}

function Initialize-Registry {
    Write-Step "Initializing registry..."

    if (-not (Test-Path $REGISTRY)) {
        $empty = @{
            candidates = @{
                java = @{
                    current   = $null
                    installed = @()
                    versions  = @{}
                }
            }
        }
        $empty | ConvertTo-Json -Depth 10 | Set-Content $REGISTRY
        Write-Ok "Registry created"
    }
    else {
        Write-Ok "Registry already exists, skipping"
    }
}

function Copy-ModuleFiles {
    Write-Step "Copying module files..."

    if (-not (Test-Path $MODULE_SRC)) {
        Write-Fail "Module source not found at $MODULE_SRC"
        Write-Fail "Make sure you are running install.ps1 from inside the myTool repo folder."
        exit 1
    }

    Copy-Item "$MODULE_SRC\*" $MODULE_DIR -Recurse -Force
    Write-Ok "Module files copied to $MODULE_DIR"
}

function Add-ToUserPath {
    Write-Step "Adding myTool to user PATH..."

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

    if ($currentPath -notlike "*myTool*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$MODULE_DIR", "User")
        Write-Ok "Added $MODULE_DIR to PATH"
    }
    else {
        Write-Ok "Already in PATH, skipping"
    }
}

function Set-JavaEnvironment {
    Write-Step "Setting JAVA_HOME..."

    # User level
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT, "User")

    # Machine level (we are admin so this works)
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT, "Machine")

    Write-Ok "JAVA_HOME set to $CURRENT"

    # Add java\current\bin to Machine PATH
    Write-Step "Adding java to Machine PATH..."

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

    # Remove any old hardcoded java paths first
    $cleaned = $machinePath -split ";" | Where-Object {
        $_ -notmatch "jdk" -and
        $_ -notmatch "temurin" -and
        $_ -notmatch "corretto" -and
        $_ -notmatch "zulu" -and
        $_ -notmatch "\.myTool\\candidates" -and
        $_ -ne ""
    }

    # Add our symlink bin path
    $newPath = ($cleaned -join ";") + ";$JAVA_BIN"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    Write-Ok "Added $JAVA_BIN to Machine PATH"
}

function New-Launcher {
    Write-Step "Creating myTool launcher..."

    $launcher = "@echo off`npowershell.exe -File `"%USERPROFILE%\.myTool\module\myTool.ps1`" %*"
    Set-Content "$MODULE_DIR\myTool.cmd" $launcher

    Write-Ok "Launcher created"
}

# ── Main ──────────────────────────────────────────────────────
Write-Title "Installing myTool - Java Version Manager for Windows"
Write-Host ""

# Check admin
if (-not (Test-Admin)) {
    Write-Fail "Please run this script as Administrator."
    Write-Fail "Right-click PowerShell and select Run as Administrator."
    exit 1
}

# Check winget
if (-not (Test-Winget)) {
    Write-Fail "winget not found. Install App Installer from the Microsoft Store."
    exit 1
}

Write-Ok "Running as Administrator"
Write-Ok "winget is available"
Write-Host ""

Initialize-Folders
Initialize-Registry
Copy-ModuleFiles
New-Launcher
Add-ToUserPath
Set-JavaEnvironment

Write-Title "myTool installed successfully!"
Write-Host ""
Write-Host "  Open a new terminal and run:" -ForegroundColor White
Write-Host "  myTool help" -ForegroundColor Cyan
Write-Host "  myTool install temurin.21" -ForegroundColor Cyan
Write-Host ""
