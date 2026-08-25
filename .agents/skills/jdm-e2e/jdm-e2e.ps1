<# jdm-e2e skill helper script

This optional helper orchestrates the skill's internal run-tests.ps1 runner. It is intended to be executed by the external agent/skill runtime.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\jdm-e2e\jdm-e2e.ps1 -Mode auto -OutputDir .\artifacts\agent-<ts> [-PerformRuntimeChecks]
  powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\jdm-e2e\jdm-e2e.ps1 -Mode auto -OutputDir .\artifacts\e2e-test -PerformE2E
#>
param(
    [ValidateSet('auto','admin','non-admin')]
    [string]$Mode = 'auto',
    [string]$OutputDir = '.\artifacts',
    [switch]$PerformRuntimeChecks,
    [switch]$PerformE2E
)

# Ensure we are running from repository root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path -Path (Join-Path $scriptDir '..\..\..')
Set-Location -Path $repoRoot

if ($PerformE2E) {
    $runner = Join-Path $scriptDir 'scripts\run-e2e.ps1'
    if (-not (Test-Path $runner)) {
        Write-Error "E2E runner not found at $runner. Ensure scripts/run-e2e.ps1 exists in the skill."
        exit 2
    }

    Write-Host "Invoking E2E runner: $runner" -ForegroundColor Cyan
    $runnerArgs = @('-Mode', $Mode, '-OutputDir', $OutputDir)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner @runnerArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host "E2E runner exited with code $exitCode" -ForegroundColor Red
        exit $exitCode
    }
    Write-Host "E2E validation completed successfully. Artifacts available at: $OutputDir" -ForegroundColor Green
    exit 0
}

$runner = Join-Path $scriptDir 'scripts\run-tests.ps1'
if (-not (Test-Path $runner)) {
    Write-Error "Runner not found at $runner. Ensure scripts/run-tests.ps1 exists in the skill."
    exit 2
}

Write-Host "Invoking skill runner: $runner" -ForegroundColor Cyan
$pesterConfigPath = (Join-Path $repoRoot 'pester.configuration.ps1')
$runnerArgs = @('-Mode', $Mode, '-PesterConfig', $pesterConfigPath, '-OutputDir', $OutputDir)
if ($PerformRuntimeChecks) { $runnerArgs += '-PerformRuntimeChecks' }
& powershell -NoProfile -ExecutionPolicy Bypass -File $runner @runnerArgs | Out-Null

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "Runner exited with code $exitCode" -ForegroundColor Red
    exit $exitCode
}

Write-Host "Runner completed successfully. Artifacts available at: $OutputDir" -ForegroundColor Green
exit 0