# jdm - install.ps1
# One-time setup script
# Usage: .\install.ps1 (from inside the repo folder)

$ErrorActionPreference = "Stop"

$JDM_DIR = "$env:USERPROFILE\.jdm"
$MODULE_DIR = "$JDM_DIR\module"
$REGISTRY = "$JDM_DIR\registry.json"
$SYMLINK_DIR = "$JDM_DIR\candidates\java"
$CURRENT = "$SYMLINK_DIR\current"
$JAVA_BIN = "$CURRENT\bin"
$REPO_OWNER = "jerryperezperez"
$REPO_NAME = "jdm"
$REPO_REF = "main"
$BOOTSTRAP_DIR = Join-Path $env:TEMP "$REPO_NAME-bootstrap"
$ARCHIVE_PATH = Join-Path $BOOTSTRAP_DIR "$REPO_NAME-$REPO_REF.zip"
$EXTRACT_DIR = Join-Path $BOOTSTRAP_DIR "$REPO_NAME-$REPO_REF"

if ($MyInvocation.MyCommand.Path) {
  $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
  $SCRIPT_DIR = $null
}

$MODULE_SRC = $null
if ($SCRIPT_DIR) {
  $localModule = Join-Path $SCRIPT_DIR "module"
  if (Test-Path $localModule) {
    $MODULE_SRC = $localModule
  }
}

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

function Resolve-ModuleSource {
  if ($MODULE_SRC -and (Test-Path $MODULE_SRC)) {
    return $MODULE_SRC
  }

  Write-Step "Fetching jdm source from GitHub..."

  if (-not (Test-Path $BOOTSTRAP_DIR)) {
    New-Item -ItemType Directory -Path $BOOTSTRAP_DIR -Force | Out-Null
  }

  $archiveUrl = "https://codeload.github.com/$REPO_OWNER/$REPO_NAME/zip/refs/heads/$REPO_REF"

  if (Test-Path $ARCHIVE_PATH) {
    Remove-Item $ARCHIVE_PATH -Force -ErrorAction SilentlyContinue
  }

  if (Test-Path $EXTRACT_DIR) {
    Remove-Item $EXTRACT_DIR -Recurse -Force -ErrorAction SilentlyContinue
  }

  Invoke-WebRequest -Uri $archiveUrl -OutFile $ARCHIVE_PATH
  Expand-Archive -Path $ARCHIVE_PATH -DestinationPath $BOOTSTRAP_DIR -Force

  $downloadedModule = Join-Path $EXTRACT_DIR "module"

  if (-not (Test-Path $downloadedModule)) {
    throw "Downloaded source is missing the module directory."
  }

  $script:MODULE_SRC = $downloadedModule
  return $script:MODULE_SRC
}

function Add-UserPathEntry {
  param(
    [Parameter(Mandatory)] [string] $Entry
  )

  $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
  $entries = @()

  if ($currentPath) {
    $entries = $currentPath -split ";" | Where-Object { $_ -ne "" }
  }

  if ($entries -notcontains $Entry) {
    $entries += $Entry
    [Environment]::SetEnvironmentVariable("PATH", ($entries -join ";"), "User")
    Write-Ok "Added $Entry to user PATH"
  }
  else {
    Write-Ok "Already in user PATH, skipping $Entry"
  }
}

function Initialize-Folders {
  Write-Step "Creating folder structure..."

  $folders = @(
    $JDM_DIR,
    "$JDM_DIR\candidates",
    "$JDM_DIR\candidates\java",
    "$JDM_DIR\tmp",
    $MODULE_DIR,
    "$MODULE_DIR\commands",
    "$MODULE_DIR\core"
  )

  foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
      New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
  }

  Write-Ok "Folders created at $JDM_DIR"
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

  $source = Resolve-ModuleSource

  if (-not (Test-Path $source)) {
    Write-Fail "Module source not found at $source"
    Write-Fail "Make sure the GitHub source download completed successfully."
    exit 1
  }

  Copy-Item "$source\*" $MODULE_DIR -Recurse -Force
  Write-Ok "Module files copied to $MODULE_DIR"
}

function Add-ToUserPath {
  Write-Step "Adding jdm to user PATH..."

  Add-UserPathEntry -Entry $MODULE_DIR
  Add-UserPathEntry -Entry $JAVA_BIN
}

function Set-JavaEnvironment {
  Write-Step "Setting JAVA_HOME..."

  [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT, "User")
  $env:JAVA_HOME = $CURRENT

  Write-Ok "JAVA_HOME set for current user to $CURRENT"

  if (Test-Admin) {
    Write-Step "Setting machine JAVA_HOME..."
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $CURRENT, "Machine")
    Write-Ok "JAVA_HOME set for machine to $CURRENT"

    Write-Step "Adding java to Machine PATH..."

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

    # Remove any old hardcoded java paths first
    $cleaned = $machinePath -split ";" | Where-Object {
      $_ -notmatch "jdk" -and
      $_ -notmatch "temurin" -and
      $_ -notmatch "corretto" -and
      $_ -notmatch "zulu" -and
      $_ -notmatch "\.jdm\\candidates" -and
      $_ -ne ""
    }

    # Add our symlink bin path
    $newPath = ($cleaned -join ";") + ";$JAVA_BIN"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    Write-Ok "Added $JAVA_BIN to Machine PATH"
  }
  else {
    Write-Step "Skipping machine-level PATH updates (run as Administrator for system-wide setup)"
  }
}

function New-Launcher {
  Write-Step "Creating jdm launcher..."

  $launcher = "@echo off`npowershell.exe -File `"%USERPROFILE%\.jdm\module\jdm.ps1`" %*"
  Set-Content "$MODULE_DIR\jdm.cmd" $launcher

  Write-Ok "Launcher created"
}

# ── Main ──────────────────────────────────────────────────────
Write-Title "Installing jdm - Java Version Manager for Windows"
Write-Host ""

# Check admin
if (-not (Test-Winget)) {
  Write-Fail "winget not found. Install App Installer from the Microsoft Store."
  exit 1
}

if (Test-Admin) {
  Write-Ok "Running as Administrator"
}
else {
  Write-Step "Not running as Administrator; continuing with user-level setup."
}
Write-Ok "winget is available"
Write-Host ""

Initialize-Folders
Initialize-Registry
Copy-ModuleFiles
New-Launcher
Add-ToUserPath
Set-JavaEnvironment

Write-Title "jdm installed successfully!"
Write-Host ""
Write-Host "  Open a new terminal and run:" -ForegroundColor White
Write-Host "  jdm help" -ForegroundColor Cyan
Write-Host "  jdm install temurin.21" -ForegroundColor Cyan
Write-Host ""
