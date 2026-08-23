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

Replace `--silent` with `--disable-interactivity` and stream winget output through `Tee-Object` for real-time display. This allows download progress bars and status messages to display while still preventing user prompts.

## Consequences

* Good, because users see real-time download progress and installation status.
* Good, because `--disable-interactivity` still prevents interactive prompts, maintaining unattended install behavior.
* Good, because `Tee-Object` captures output for error handling while displaying it immediately.
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

$rawOutput = & winget install $Id `
    --source winget `
    --accept-package-agreements `
    --accept-source-agreements `
    --disable-interactivity 2>&1 | Tee-Object -Variable wingetOutput

Write-Host "      ── end ──" -ForegroundColor DarkGray
Write-Host ""

if ($LASTEXITCODE -ne 0) {
    Write-Fail "winget install failed with exit code $LASTEXITCODE"
    return $false
}

if ($wingetOutput) {
    $wingetOutput | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
}
```

### Approach Notes

The `Tee-Object` hybrid approach was chosen over alternatives:

1. **`ForEach-Object` pipeline alone**: Swallows `$LASTEXITCODE`, making error detection unreliable.
2. **`Start-Process` with file redirection**: Doesn't provide real-time output; writes to file only after completion.
3. **`Tee-Object -Variable`**: Captures output for error handling while allowing real-time display via `ForEach-Object` loop.

## Verification

- [ ] `jdm install temurin.21` shows winget download progress in real-time
- [ ] Output is visually indented and dimmed vs jdm's own messages
- [ ] Successful install still registers correctly in the registry
- [ ] Failed installs still show the error message
- [ ] All existing Pester tests pass (113 tests)
- [ ] Winget not installed scenario shows helpful error message

## Alternatives Considered

* **Keep `--silent` and pipe output**: Rejected because `--silent` suppresses winget's own progress bars, defeating the purpose.
* **Use `Start-Process` with tailing**: Rejected because it's complex and doesn't provide true real-time output.
* **No visual separators**: Rejected because users need to distinguish jdm output from winget output.
