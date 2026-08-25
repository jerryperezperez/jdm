<#
tools/run-tests.ps1
Conservative runner script intended to be called by an external agent/skill.
It detects privilege (admin / dev-mode non-admin / non-admin), sets an env var so tests can adapt,
and runs Invoke-Pester with the repository's pester.configuration.ps1. By default it performs non-destructive checks only.

Usage examples (agent):
  # Auto-detect and run tests (non-destructive):
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-tests.ps1 -Mode Auto -PesterConfig .\pester.configuration.ps1 -OutputDir .\artifacts

  # Auto-detect and run tests and additional runtime checks (CAUTION: may attempt network/install ops)
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-tests.ps1 -Mode Auto -PesterConfig .\pester.configuration.ps1 -OutputDir .\artifacts -PerformRuntimeChecks
#>

param(
    [ValidateSet('auto','admin','non-admin')]
    [string]$Mode = 'auto',

    [string]$PesterConfig = '.\pester.configuration.ps1',

    [string]$OutputDir = '.\artifacts',

    [switch]$PerformRuntimeChecks
)

function Test-IsAdmin {
    try {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-DevModeEnabled {
    try {
        $devMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
        return ($devMode -and $devMode.AllowDevelopmentWithoutDevLicense -eq 1)
    }
    catch {
        return $false
    }
}

function Test-CanCreateSymlink {
    $tmpDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
    $target = Join-Path $tmpDir 'target'
    New-Item -Path $target -ItemType Directory | Out-Null
    $link = Join-Path $tmpDir 'link'
    try {
        # Attempt to create a symbolic link (non-admin allowed in Dev Mode)
        New-Item -Path $link -ItemType SymbolicLink -Value $target -ErrorAction Stop | Out-Null
        $ok = Test-Path $link
    }
    catch {
        $ok = $false
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $ok
}

# --- detect privilege ---
$detected = 'NonAdmin'
if (Test-IsAdmin) { $detected = 'Administrator' }
elseif (Test-DevModeEnabled) { $detected = 'DevModeNonAdmin' }
elseif (Test-CanCreateSymlink) { $detected = 'DevModeNonAdmin' }

# select mode
if ($Mode -ne 'auto') { $selectedMode = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($Mode) }
else { $selectedMode = $detected }

# normalize selectedMode to one of expected tokens
switch ($selectedMode) {
    'Administrator' { $selectedMode = 'Administrator' }
    'Devmodenonadmin' { $selectedMode = 'DevModeNonAdmin' }
    'DevModeNonAdmin' { $selectedMode = 'DevModeNonAdmin' }
    'NonAdmin' { $selectedMode = 'NonAdmin' }
    default { $selectedMode = 'NonAdmin' }
}

# prepare artifacts
$absOutput = Resolve-Path -Path $OutputDir -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }
if (-not $absOutput) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null ; $absOutput = (Resolve-Path -Path $OutputDir).Path }

# export env var so Pester tests can adapt
$env:JDM_TEST_MODE = $selectedMode

Write-Host "Detected privilege: $detected" -ForegroundColor Cyan
Write-Host "Selected mode: $selectedMode" -ForegroundColor Cyan
Write-Host "Artifacts will be written to: $absOutput" -ForegroundColor Cyan

# run Pester (non-destructive by default)
if (-not (Test-Path $PesterConfig)) {
    Write-Error "Pester configuration not found at $PesterConfig"
    exit 2
}

Write-Host "Running Pester tests (config: $PesterConfig)..." -ForegroundColor Green
try {
    # Running Pester and letting the project's configuration handle JUnit/coverage outputs
    Invoke-Pester -Configuration $PesterConfig -PassThru | Tee-Object -Variable pesterResult | Out-Null
}
catch {
    Write-Warning "Invoke-Pester threw an error: $_"
}

# minimal non-destructive runtime checks
$runtimeSummary = [ordered]@{}
$runtimeSummary.Mode = $selectedMode
$runtimeSummary.Timestamp = (Get-Date).ToString('o')
$runtimeSummary.HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$moduleFilesExist = @('.\module\jdm.ps1', '.\module\core\symlink.ps1') | ForEach-Object { Test-Path $_ }
$runtimeSummary.ModuleFilesExist = -not ($moduleFilesExist -contains $false)

if ($PerformRuntimeChecks) {
    Write-Host "Performing additional runtime checks (may be destructive)" -ForegroundColor Yellow
    # Example non-destructive checks; do not install anything by default
    $runtimeSummary.WingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    # Placeholder for more advanced runtime checks (install/use/uninstall) - implement with caution
}
else {
    Write-Host "Skipping potentially destructive runtime checks. Use -PerformRuntimeChecks to enable." -ForegroundColor Yellow
}

# write agent_summary.json
$summary = [ordered]@{
    detectedPrivilege = $detected
    selectedMode = $selectedMode
    pesterResult = if ($pesterResult) { @{Passed = $pesterResult.PassedCount; Failed = $pesterResult.FailedCount; Skipped = $pesterResult.SkippedCount } } else { $null }
    runtime = $runtimeSummary
}

$summaryPath = Join-Path $absOutput 'agent_summary.json'
$summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryPath -Encoding UTF8
Write-Host "Wrote summary to $summaryPath" -ForegroundColor Green

if ($pesterResult -and $pesterResult.FailedCount -gt 0) {
    Write-Host "Pester reported failures: $($pesterResult.FailedCount)" -ForegroundColor Red
    exit 3
}

Write-Host "Runner finished." -ForegroundColor Green
exit 0
