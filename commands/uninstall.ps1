# ─────────────────────────────────────────────────────────────
#  jdm - commands/uninstall.ps1
#  Removes an installed Java version
#  Handles the edge case of removing the active version
# ─────────────────────────────────────────────────────────────

. "$PSScriptRoot\..\core\registry.ps1"
. "$PSScriptRoot\..\core\symlink.ps1"

# ── Main uninstall entry point ────────────────────────────────
# Input: version key e.g. "temurin-21"
function Invoke-Uninstall {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    Write-Title "jdm uninstall $Key"
    Write-Host ""

    # ── Step 1: Check version exists in registry ──────────────
    if (-not (Test-VersionInstalled -Key $Key)) {
        Write-Fail "'$Key' is not installed."
        Write-Host ""

        $all = Get-AllVersions
        if ($all.Count -gt 0) {
            Write-Host "  Installed versions:" -ForegroundColor Yellow
            foreach ($v in $all) {
                $marker = if ($v.isCurrent) { " (current)" } else { "" }
                Write-Host "    $($v.key)$marker" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  No versions installed." -ForegroundColor Gray
        }

        Write-Host ""
        return
    }

    # ── Step 2: Get version details ───────────────────────────
    $entry = Get-Version -Key $Key
    $current = Get-CurrentVersion
    $isCurrentVersion = ($current -eq $Key)

    # ── Step 3: Warn if removing active version ───────────────
    if ($isCurrentVersion) {
        Write-Host "  [!] '$Key' is the currently active version." -ForegroundColor Yellow
        Write-Host ""

        # Check if other versions exist to switch to
        $all = Get-AllVersions
        $others = $all | Where-Object { $_.key -ne $Key }

        if ($others.Count -eq 0) {
            Write-Host "  This is the only installed version." -ForegroundColor Yellow
            Write-Host "  Removing it will leave you with no active Java." -ForegroundColor Yellow
            Write-Host ""
            $confirm = Read-Host "  Are you sure? (y/n)"
            if ($confirm -ne "y") {
                Write-Step "Uninstall cancelled."
                return
            }
        }
        else {
            # Prompt user to pick a replacement
            Write-Host "  Select a replacement version to activate after removal:" -ForegroundColor White
            Write-Host ""

            for ($i = 0; $i -lt $others.Count; $i++) {
                Write-Host "    $($i + 1). $($others[$i].key)" -ForegroundColor White
            }

            Write-Host ""
            $choice = Read-Host "  Which one? (1-$($others.Count)) or 'q' to cancel"

            if ($choice -eq "q") {
                Write-Step "Uninstall cancelled."
                return
            }

            $index = [int]$choice - 1

            if ($index -lt 0 -or $index -ge $others.Count) {
                Write-Fail "Invalid choice. Uninstall cancelled."
                return
            }

            $replacement = $others[$index]
        }
    }
    else {
        # Not active — just confirm
        Write-Host "  Package : $($entry.vendor) $($entry.version)" -ForegroundColor White
        Write-Host "  Path    : $($entry.path)" -ForegroundColor White
        Write-Host ""
        $confirm = Read-Host "  Remove '$Key'? (y/n)"
        if ($confirm -ne "y") {
            Write-Step "Uninstall cancelled."
            return
        }
    }

    # ── Step 4: Remove files from disk ───────────────────────
    Write-Step "Removing files..."

    if (Test-Path $entry.path) {
        try {
            Remove-Item $entry.path -Recurse -Force
            Write-Ok "Removed $($entry.path)"
        }
        catch {
            Write-Fail "Failed to remove files: $_"
            Write-Fail "Try closing any terminals or apps using this Java version first."
            return
        }
    }
    else {
        Write-Step "Files already missing from disk, cleaning up registry only."
    }

    # ── Step 5: Remove from registry ─────────────────────────
    $removed = Remove-Version -Key $Key

    if (-not $removed) {
        Write-Fail "Failed to update registry after removal."
        return
    }

    # ── Step 6: Handle symlink if we removed active version ───
    if ($isCurrentVersion) {
        if ($others.Count -eq 0) {
            # No replacement — remove symlink entirely
            Remove-CurrentSymlink
            Write-Host ""
            Write-Host "  [!] No active Java version set." -ForegroundColor Yellow
            Write-Host "  Run 'jdm install temurin.21' to install a new version." -ForegroundColor Cyan
        }
        else {
            # Switch to replacement
            Write-Step "Switching to '$($replacement.key)'..."

            $replacementEntry = Get-Version -Key $replacement.key
            $switched = Switch-Version -TargetPath $replacementEntry.path

            if ($switched) {
                Set-CurrentVersion -Key $replacement.key | Out-Null
                Write-Ok "Now using '$($replacement.key)'"
            }
            else {
                Write-Fail "Could not switch to replacement. Run 'jdm use $($replacement.key)' manually."
            }
        }
    }

    # ── Done ──────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  [OK] '$Key' has been removed." -ForegroundColor Green
    Write-Host ""
}
