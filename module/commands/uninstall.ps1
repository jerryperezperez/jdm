# ─────────────────────────────────────────────────────────────
#  jdm - commands/uninstall.ps1
#  Removes an installed Java version
#  Handles the edge case of removing the active version
# ─────────────────────────────────────────────────────────────

. "$PSScriptRoot\..\core\registry.ps1"
. "$PSScriptRoot\..\core\symlink.ps1"
. "$PSScriptRoot\..\core\winget.ps1"

# ── Main uninstall entry point ────────────────────────────────
# Input: version key e.g. "temurin.21" (dot format preferred, hyphen accepted for backward compat)
function Invoke-Uninstall {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    # ADR-0001: Normalize to dot format for consistent internal handling
    $Key = Normalize-VersionKey -Key $Key

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

# ── Vendor directory cleanup helper ─────────────────────────
# Removes the vendor directory (parent of a JDK path) when no other
# java.exe-bearing, non-IDE subdirectory remains. Never recurses
# above the vendor directory.
function Remove-EmptyVendorDir {
    param(
        [Parameter(Mandatory)] [string] $JdkPath
    )

    $vendorDir = Split-Path $JdkPath -Parent
    if (-not (Test-Path $vendorDir)) { return }

    $keep = $false
    $children = Get-ChildItem -Path $vendorDir -Directory -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        $javaExe = Join-Path $child.FullName "bin\java.exe"
        if (Test-Path $javaExe -ErrorAction SilentlyContinue) {
            if (-not (Test-IsIdeRuntime -Path $child.FullName)) {
                $keep = $true
                break
            }
        }
    }

    if (-not $keep) {
        try {
            Remove-Item $vendorDir -Recurse -Force
            Write-Ok "Removed empty vendor directory: $vendorDir"
        }
        catch {
            Write-Fail "Failed to remove vendor directory $vendorDir : $_"
        }
    }
}

# ── Bulk uninstall of all tracked JDKs ──────────────────────
# Returns the number of failed removals (0 = success).
function Invoke-UninstallAll {
    $entries = @(Get-AllVersions)

    if ($entries.Count -eq 0) {
        Write-Host ""
        Write-Host "  No JDKs are currently installed." -ForegroundColor Gray
        Write-Host ""
        return 0
    }

    Write-Host ""
    Write-Host "  This will remove all $($entries.Count) tracked JDK(s)." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Remove all $($entries.Count) JDK(s)? (y/n)"
    if ($confirm -ne "y") {
        Write-Step "Bulk uninstall cancelled."
        Write-Host ""
        return 0
    }

    $failures = @()
    $removedCount = 0

    foreach ($entry in $entries) {
        $entryFailed = $false
        $entryReason = ""

        Write-Title "Removing $($entry.key)"

        # 1. Uninstall via winget (best-effort)
        $ok = $false
        try {
            $ok = Uninstall-WithWinget -Id $entry.id
        }
        catch {
            $ok = $false
        }
        if (-not $ok) {
            $entryFailed = $true
            $entryReason = "winget uninstall failed or winget unavailable"
        }

        # 2. Remove files from disk (best-effort)
        if ($entry.path -and (Test-Path $entry.path)) {
            try {
                Remove-Item $entry.path -Recurse -Force
            }
            catch {
                if (-not $entryFailed) {
                    $entryFailed = $true
                    $entryReason = "failed to remove files: $_"
                }
            }
        }
        elseif ($entry.path -and -not (Test-Path $entry.path)) {
            Write-Step "Files already missing from disk for $($entry.key)."
        }

        # 3. Remove registry entry (best-effort)
        $removed = $false
        try {
            $removed = Remove-Version -Key $entry.key
        }
        catch {
            $removed = $false
        }
        if (-not $removed) {
            if (-not $entryFailed) {
                $entryFailed = $true
                $entryReason = "failed to remove registry entry"
            }
        }

        if (-not $entryFailed) {
            $removedCount++
        }
        else {
            $failures += [PSCustomObject]@{
                key    = $entry.key
                id     = $entry.id
                reason = $entryReason
            }
        }

        # Vendor dir cleanup (after removing this JDK's folder)
        if ($entry.path) {
            Remove-EmptyVendorDir -JdkPath $entry.path
        }
    }

    # Clear active version/symlink when nothing remains
    $remaining = @(Get-AllVersions)
    if ($remaining.Count -eq 0) {
        Remove-CurrentSymlink
        Write-Host ""
        Write-Host "  [!] No active Java version set." -ForegroundColor Yellow
        Write-Host "  Run 'jdm install temurin.21' to install a new version." -ForegroundColor Cyan
    }

    # Summary
    Write-Host ""
    Write-Host "  [DONE] Removed $removedCount of $($entries.Count) JDK(s)." -ForegroundColor Green
    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "  The following removals had issues:" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host "    $($f.key) (id: $($f.id)) - $($f.reason)" -ForegroundColor Red
        }
    }
    Write-Host ""

    return $failures.Count
}
