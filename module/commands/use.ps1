# ─────────────────────────────────────────────────────────────
#  jdm - commands/use.ps1
#  Switches the active Java version
#  Updates the symlink and registry current pointer
# ─────────────────────────────────────────────────────────────

. "$PSScriptRoot\..\core\registry.ps1"
. "$PSScriptRoot\..\core\symlink.ps1"

# ── Main use entry point ──────────────────────────────────────
# Input: version key e.g. "temurin-21" or "corretto-17"
function Invoke-Use {
  param(
    [Parameter(Mandatory)] [string] $Key
  )

  Write-Title "jdm use $Key"
  Write-Host ""

  # ── Step 1: Check version exists in registry ──────────────
  if (-not (Test-VersionInstalled -Key $Key)) {
    Write-Fail "'$Key' is not installed."
    Write-Host ""

    # Show what IS installed as a helpful hint
    $all = Get-AllVersions
    if ($all.Count -gt 0) {
      Write-Host "  Installed versions:" -ForegroundColor Yellow
      foreach ($v in $all) {
        $marker = if ($v.isCurrent) { " (current)" } else { "" }
        Write-Host "    $($v.key)$marker" -ForegroundColor Gray
      }
      Write-Host ""
      Write-Host "  Usage: jdm use <version>" -ForegroundColor Cyan
    }
    else {
      Write-Host "  No versions installed. Run 'jdm install temurin.21' to get started." -ForegroundColor Cyan
    }

    return
  }

  # ── Step 2: Check if already current ─────────────────────
  $current = Get-CurrentVersion

  if ($current -eq $Key) {
    Write-Host "  '$Key' is already the active version." -ForegroundColor Yellow
    Write-Host ""
    return
  }

  # ── Step 3: Get the install path from registry ────────────
  $entry = Get-Version -Key $Key

  if (-not $entry) {
    Write-Fail "Registry entry for '$Key' is missing or corrupt."
    return
  }

  if (-not (Test-Path $entry.path)) {
    Write-Fail "Install path not found: $($entry.path)"
    Write-Fail "The registry entry exists but the files are missing. Try reinstalling."
    return
  }

  # ── Step 4: Update the symlink ────────────────────────────
  $switched = Switch-Version -TargetPath $entry.path

  if (-not $switched) {
    Write-Fail "Failed to switch version. See errors above."
    return
  }

  # ── Step 5: Update registry current pointer ───────────────
  $updated = Set-CurrentVersion -Key $Key

  if (-not $updated) {
    Write-Fail "Symlink updated but registry not saved. Run 'jdm use $Key' again."
    return
  }

  # ── Done ──────────────────────────────────────────────────
  Write-Host "  [OK] Switched from '$current' → '$Key'" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Open a new terminal and run: java -version" -ForegroundColor Cyan
  Write-Host ""
}
