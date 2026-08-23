---
status: "accepted"
date: 2026-08-22
decision-makers: jerry
---

# Stream winget output in real-time during install

## Context and Problem Statement

When `jdm install` runs, winget's output is completely swallowed. The user sees jdm's "Installing ... via winget..." message and then the terminal hangs silently until winget finishes — which can take 30+ seconds for large JDKs. There's no progress feedback, no download percentage, nothing.

Two issues suppress winget's output:

1. The `--silent` flag tells winget to suppress its own progress/status output entirely.
2. PowerShell captures the output into the pipeline by default. Since `Install-WithWinget` doesn't explicitly write it anywhere, the output is either discarded or held until completion.

## Decision

Remove `--silent` and stream winget output through `ForEach-Object` for real-time display. The `--accept-package-agreements` and `--accept-source-agreements` flags prevent interactive prompts, so `--silent` is not needed for unattended installs.

## Consequences

* Good, because users see real-time download progress and installation status.
* Good, because `--accept-package-agreements` and `--accept-source-agreements` prevent interactive prompts, maintaining unattended install behavior.
* Good, because `ForEach-Object` streams each line as it arrives from winget.
* Bad, because winget output is verbose and may clutter the terminal for some users.
* Neutral, because existing tests mock `Install-WithWinget` entirely, so no test changes needed.

## Implementation

### Changes to `module/core/winget.ps1`

**Error handling for winget availability:**
```powershell
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail "winget is not installed or not in PATH"
    Write-Host "      Please install App Installer from Microsoft Store" -ForegroundColor Yellow
    return $false
}
```

**Streaming with visual separators:**
```powershell
Write-Host ""
Write-Host "      ── winget ──" -ForegroundColor DarkGray

& winget install $Id `
    --source winget `
    --accept-package-agreements `
    --accept-source-agreements 2>&1 | ForEach-Object {
    Write-Host "      $_" -ForegroundColor DarkGray
}

Write-Host "      ── end ──" -ForegroundColor DarkGray
Write-Host ""

if ($LASTEXITCODE -ne 0) {
    Write-Fail "winget install failed with exit code $LASTEXITCODE"
    return $false
}
```

### Approach Notes

The `ForEach-Object` pipeline streams each line as it arrives from winget. The `--accept-package-agreements` and `--accept-source-agreements` flags prevent interactive prompts, so `--silent` is not needed.

## Verification

- [ ] `jdm install temurin.21` shows winget download progress in real-time
- [ ] Output is visually indented and dimmed vs jdm's own messages
- [ ] Successful install still registers correctly in the registry
- [ ] Failed installs still show the error message
- [ ] All existing Pester tests pass (113 tests)
- [ ] Winget not installed scenario shows helpful error message

## Alternatives Considered

* **Keep `--silent` and pipe output**: Rejected because `--silent` suppresses winget's own progress bars, defeating the purpose.
* **Use `--disable-interactivity`**: Rejected because this flag doesn't exist in winget v1.29.290.
* **Use `Start-Process` with file tailing**: Rejected because file-based streaming is unreliable and complex.
* **No visual separators**: Rejected because users need to distinguish jdm output from winget output.
