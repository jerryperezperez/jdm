<# jdm-e2e skill helper script

This optional helper orchestrates the repo's tools/run-tests.ps1 runner. It is intended to be executed by the external agent/skill runtime.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\jdm-e2e\jdm-e2e.ps1 -Mode auto -OutputDir .\artifacts\agent-<ts> [-PerformRuntimeChecks]
#>
param(
    [ValidateSet('auto','admin','non-admin')]
    [string]$Mode = 'auto',
    [string]$OutputDir = '.\artifacts',
    [switch]$PerformRuntimeChecks
)

# Ensure we are running from repository root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path -Path (Join-Path $scriptDir '..\..')
Set-Location -Path $repoRoot

$runner = Join-Path $repoRoot 'tools\run-tests.ps1'
if (-not (Test-Path $runner)) {
    Write-Error "Runner not found at $runner. Ensure tools/run-tests.ps1 exists in the repository."
    exit 2
}

Write-Host "Invoking repository runner: $runner" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Mode $Mode -PesterConfig '.\pester.configuration.ps1' -OutputDir $OutputDir -PerformRuntimeChecks:$PerformRuntimeChecks | Out-Null

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "Runner exited with code $exitCode" -ForegroundColor Red
    exit $exitCode
}

Write-Host "Runner completed successfully. Artifacts available at: $OutputDir" -ForegroundColor Green
exit 0
