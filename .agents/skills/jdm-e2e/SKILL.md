---
name: jdm-e2e
description: Runs a full end-to-end acceptance test of the jdm project on this machine — bootstraps via install.ps1, installs real JDKs through winget (offline mock fallback), validates registry.json and ~/.jdm/candidates, exercises every CLI command and its output, verifies uninstall leaves no leftover JDKs in non-excluded directories, then uninstalls jdm itself and confirms removal. Use this when the user says "run e2e test", "end-to-end test jdm", "smoke test jdm", "validate jdm install/uninstall", or asks to verify jdm works on a real machine. WARNING: modifies user PATH/JAVA_HOME and may download JDKs (~hundreds of MB).
---

# jdm-e2e Skill

This skill provides an end-to-end acceptance test for the jdm (Java Version Manager for Windows) project. It automates the complete lifecycle:

1. **Bootstrap** — Runs `./install.ps1` to install jdm from the local repo
2. **Install JDKs** — Uses `jdm install` via winget (with offline/mock fallback)
3. **Validate State** — Checks `~/.jdm/registry.json`, `~/.jdm/candidates/java/`, and symlink integrity
4. **Exercise Commands** — Validates output of `help`, `version`, `list`, `use`, `install`, `uninstall`, `uninstall --all-vendors`
5. **Verify Cleanup** — Confirms removals leave no tracked JDKs in non-IDE directories
6. **Self-Uninstall** — Runs `uninstall --self` and verifies jdm is gone

## When to Use

Trigger this skill when the user asks for:
- "run e2e test"
- "end-to-end test jdm"
- "smoke test jdm"
- "validate jdm install/uninstall"
- "test jdm on a real machine"

## How to Run

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\jdm-e2e\run-e2e.ps1
```

Or from within the skill directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\jdm-e2e\run-e2e.ps1
```

## What the Test Does

### Pre-flight Checks
- Verifies PowerShell 5.1+
- Checks for winget availability
- Tests network connectivity (falls back to mock mode if unavailable)
- Detects symlink capability (Admin or Developer Mode) — uses junction fallback if neither

### Bootstrap
- Executes `install.ps1` from the local repo (tests current code, not GitHub release)
- Verifies `~/.jdm/module/jdm.ps1` and `~/.jdm/module/jdm.cmd` exist
- Confirms user PATH and JAVA_HOME are configured

### JDK Installation
- **Real mode**: Installs `temurin.21` and `corretto.17` via winget
- **Mock mode**: Creates fake JDK directories with `bin/java.exe` and registers them via registry functions

### Validation
- Registry integrity: all paths exist, installed list matches versions, current pointer valid
- Symlink target matches registry current version
- Candidates directory structure matches registry
- Command outputs match expected format (help banner, version string, list markers, etc.)

### Removal Verification
- Single uninstall: removes specific version, updates symlink if it was current
- Bulk uninstall (`--all-vendors`): clears registry, removes symlink, cleans tmp files
- Disk sweep: uses `Get-JavaSnapshot` before/after to confirm only jdm-owned JDKs are removed (excludes IDE-bundled runtimes)

### Self-Uninstall
- Runs `uninstall --self` (auto-confirms)
- Verifies `~/.jdm` removed, jdm gone from user PATH, JAVA_HOME cleared
- Notes intentional leftovers: `~/.jdks` and machine-level PATH entries (require admin)

## Output

The runner prints a numbered pass/fail checklist. Exit code:
- `0` — All assertions passed
- Non-zero — At least one failure (summary at end)

## Requirements

- Windows 10+
- PowerShell 5.1+
- winget (App Installer from Microsoft Store) — for real mode
- Administrator or Developer Mode — for symlink creation (junction fallback works without)
- Network access — for real winget installs (~hundreds of MB downloads)

## Important Notes

⚠️ **This test modifies your machine:**
- Creates/updates `~/.jdm/`, `~/.jdks/`
- Modifies user PATH and JAVA_HOME
- Downloads real JDKs via winget (unless offline/mock mode)
- Removes everything at the end via `uninstall --self`

Run on a machine where this state change is acceptable (e.g., a test VM or a machine you're comfortable resetting). The test cleans up after itself, but machine-level PATH entries added by a previous elevated run will require manual admin cleanup.