# ─────────────────────────────────────────────────────────────
#  jdm - commands/list.ps1
#  Displays all installed Java versions
#  Highlights the current active version
# ─────────────────────────────────────────────────────────────

. "$PSScriptRoot\..\core\registry.ps1"
. "$PSScriptRoot\..\core\symlink.ps1"

# ── Main list entry point ─────────────────────────────────────
function Invoke-List {

    Write-Title "jdm list"
    Write-Host ""

    # ── Step 1: Load all versions from registry ───────────────
    $all = Get-AllVersions

    if ($all.Count -eq 0) {
        Write-Host "  No Java versions installed yet." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Get started:" -ForegroundColor Gray
        Write-Host "    jdm install temurin.21" -ForegroundColor Cyan
        Write-Host "    jdm install corretto.17" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    # ── Step 2: Verify symlink is healthy ─────────────────────
    $symlinkTarget = Get-CurrentSymlinkTarget
    $current = Get-CurrentVersion

    if ($current -and -not $symlinkTarget) {
        Write-Host "  [!] Warning: symlink is missing. Run 'jdm use $current' to fix." -ForegroundColor Yellow
        Write-Host ""
    }

    # ── Step 3: Display installed versions ───────────────────
    Write-Host "  Installed Java versions:" -ForegroundColor White
    Write-Host ""

    foreach ($v in $all) {
        if ($v.isCurrent) {
            # Active version — highlighted
            Write-Host "  --> $($v.key)" -NoNewline -ForegroundColor Cyan
            Write-Host "  (current)" -ForegroundColor Green
            Write-Host "       Vendor  : $($v.vendor)"  -ForegroundColor Gray
            Write-Host "       Version : $($v.version)" -ForegroundColor Gray
            Write-Host "       Path    : $($v.path)"    -ForegroundColor Gray
        }
        else {
            # Inactive version
            Write-Host "       $($v.key)" -ForegroundColor White
            Write-Host "       Vendor  : $($v.vendor)"  -ForegroundColor Gray
            Write-Host "       Version : $($v.version)" -ForegroundColor Gray
            Write-Host "       Path    : $($v.path)"    -ForegroundColor Gray
        }
        Write-Host ""
    }

    # ── Step 4: Show helpful commands at the bottom ───────────
    Write-Host "  To switch versions : jdm use <version>" -ForegroundColor Gray
    Write-Host "  To install more    : jdm install temurin.21" -ForegroundColor Gray
    Write-Host "  To remove a version: jdm uninstall <version>" -ForegroundColor Gray
    Write-Host ""
}
