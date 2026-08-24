---
name: jdm-e2e
description: Runs a full end-to-end validation of the jdm Java version manager, including install, switch, uninstall, bulk removal, and cleanup. Use this when the user wants to exercise all jdm flags in a real Windows environment or leave the machine ready for the next E2E test run.
---

# jdm end-to-end validation (skill)

Use this skill anytime the goal is to exercise the real jdm command surface rather than mocked unit tests. The objective is to validate the actual install/switch/remove lifecycle and then leave the machine clean.

## Preconditions
- Run on Windows with PowerShell and `winget` available.
- Run from the repository root unless a command explicitly says otherwise.
- Prefer dot-format version keys such as `temurin.21` and `corretto.21`; hyphen aliases are backward compatible but not the preferred validation form.
- Treat every step as a deterministic pass/fail gate. Do not proceed until the previous command has been verified.
- Determine privilege mode before starting the destructive uninstall/cleanup steps:
  - Normal user mode can handle: installing jdm itself, user-level PATH/JAVA_HOME updates, the jdm registry/user state under `$env:USERPROFILE\.jdm`, and the switch-based validation flow that manipulates the current symlink/junction.
  - Administrator mode is required for complete removal of JDKs installed under `Program Files` and for final cleanup of machine-level installation artifacts; if admin is unavailable, leave the user-level state clean but mark filesystem removal as blocked/incomplete rather than claiming the full E2E lifecycle passed.

## Privilege rules for this skill
- Normal mode tasks:
  - `./install.ps1` for user-level jdm setup
  - `jdm install ...` and `jdm use ...` for validation within the user-managed jdm state
  - user PATH / `JAVA_HOME` updates under the current user
  - final user-level cleanup of `$env:USERPROFILE\.jdm`, `$env:USERPROFILE\.jdks`, and the current Java link/junction under the user profile
- Admin-required tasks:
  - deleting JDK directories under `C:\Program Files\...` created by winget
  - `jdm uninstall <version>` when the target JDK lives in Program Files and removal needs filesystem deletion
  - `jdm uninstall --all-vendors` when the goal is to leave the machine fully clean and remove all installed vendor directories
  - machine-level cleanup of any system-installed Java artifacts that require elevated permissions
- If the task asks for the full install/switch/remove lifecycle, the skill should attempt the normal-user steps first and then explicitly stop at the admin-only steps if elevated permissions are not available. Report the blocker with the exact command and the files/directories that remain.

## Required end-to-end flow

### 1. Install jdm itself
1. Run `./install.ps1` from the repo root.
2. Verify the install completed without error and the launcher is available.
3. Confirm `jdm version` or `jdm help` prints the expected version banner.
4. If the command fails, stop and report the blocker.

Expected checks:
- `jdm` resolves on PATH
- `jdm version` prints a version number
- The user-level install directory exists under `$env:USERPROFILE\.jdm`

### 2. Install multiple JDKs to exercise switching
Install at least three distinct JDKs so real switching is actually exercised. Use a realistic matrix such as:
- `jdm install temurin.21`
- `jdm install corretto.21`
- `jdm install azul.26`

For each install:
1. Confirm the command exits successfully.
2. Check `jdm list` includes the installed version.
3. Confirm the version path exists on disk.
4. Confirm the current version is active and the `java -version` output matches that vendor/version.

Expected checks:
- `jdm list` includes each installed version
- `Test-Path` for the installed JDK root returns true
- `java -version` output matches the expected vendor and version after activation

### 3. Switch among installed versions
Run a switching loop to validate the active symlink and environment update flow:
1. `jdm use temurin.21`
2. `java -version` should show Temurin 21
3. `jdm use corretto.21`
4. `java -version` should show Amazon Corretto 21
5. `jdm use azul.26`
6. `java -version` should show Azul Zulu 26
7. Return to the version you want as the final active state before uninstall tests

Expected checks:
- The active symlink target changes to the selected JDK path
- `JAVA_HOME` points to the selected version
- `PATH` resolves `java` and `javac` from the selected JDK

### 4. Uninstall a single JDK and verify removal
Pick one of the installed versions and remove it:
- `jdm uninstall corretto.21`

Then validate:
1. The command exits without error.
2. The target directory is removed from the JDK install location.
3. The uninstall target is no longer listed in `jdm list`.
4. `java -version` no longer resolves to the removed JDK if it was the active version.

Expected checks:
- `Test-Path <removed-dir>` returns false
- `jdm list` does not include the removed version
- The registry does not contain the removed version key

### 5. Remove all installed vendors
Run the bulk removal flow:
- `jdm uninstall --all-vendors`

Then validate:
1. The command prompts for confirmation and proceeds only when approved.
2. All JDKs are removed from the filesystem.
3. `jdm list` shows no installed versions.
4. The registry `installed` list is empty or the registry state is effectively clean.

Expected checks:
- no JDK directories remain under the user install root
- registry contains no active version
- the active Java symlink/current path is absent or points nowhere

### 6. Final cleanup for the next E2E run
At the end of the validation flow, ensure the machine is left in a clean state for the next run.

Required cleanup steps:
- Remove the user-level jdm state directory: `$env:USERPROFILE\.jdm`
- Remove any leftover JDK installation directories under `$env:USERPROFILE\.jdks`
- Remove the active Java symlink/current link if it still exists
- Remove any PATH entries that were added for jdm/JAVA_HOME during the run
- Clear `JAVA_HOME` in the user environment if it was set by the test flow

If the environment is intentionally left as a real installation for future work, document that explicitly. Otherwise, the skill should finish by fully cleaning the environment.

## Deterministic pass/fail checklist
Use this checklist for every run:
- [ ] `./install.ps1` succeeded
- [ ] `jdm version` or `jdm help` succeeded
- [ ] Three JDKs were installed and appear in `jdm list`
- [ ] `jdm use` successfully switched active Java between versions
- [ ] `java -version` matched the selected vendor/version each time
- [ ] A single JDK uninstall removed the JDK and the directory no longer exists
- [ ] Bulk uninstall removed all JDKs and left the list empty
- [ ] Final cleanup removed `~/.jdm`, `~/.jdks`, and environment changes

## Important behavior notes
- This skill is intentionally destructive in the final cleanup phase. It should only be used when the user wants a real end-to-end validation run and is okay with state removal.
- Do not stop after the first successful install; the full value of the test is in the multi-version switching and cleanup path.
- When the user says "run all the jdm flags" or "walk the full install/switch/remove lifecycle", this is the skill to invoke.

## Agent helper and integration (added)
This skill includes a lightweight helper and recommended runner to allow an external agent to invoke a privilege-aware test run without modifying repository source files.

- Recommended repo runner: `tools/run-tests.ps1` (already present in this repo). It:
  - Detects privilege level (Administrator | DevModeNonAdmin | NonAdmin)
  - Sets an environment variable (`JDM_TEST_MODE`) so tests can adapt
  - Runs `Invoke-Pester` with the repository's `pester.configuration.ps1` and writes JUnit & JaCoCo outputs to the `coverage/` folder
  - Produces an `agent_summary.json` artifact describing detected privilege, Pester results, and runtime checks

- Optional helper for agents: `.agents/skills/jdm-e2e/jdm-e2e.ps1` — a small orchestrator that calls the runner with the desired mode and output folder.

Invocation example (agent host):
`powershell -NoProfile -ExecutionPolicy Bypass -File .\\.agents\\skills\\jdm-e2e\\jdm-e2e.ps1 -Mode auto -OutputDir .\\artifacts\\agent-<ts>`

Artifacts produced by the runner:
- `artifacts/agent_summary.json` (structured summary)
- `coverage/test-results.xml` (JUnit)
- `coverage/coverage.xml` (JaCoCo)
- runner log (plain text)

Notes for implementers
- The skill should not hard-modify repository source files. It should run tests and runtime checks and collect results.
- For non-admin checks that cannot be run on the agent host (e.g., symlink creation blocked by platform policies), the skill should document the limitation in `agent_summary.json` and continue with other checks.

Security
- Do not capture or echo secrets (tokens) present in `opencode.json` or environment variables.

Test tagging guidance
- To help external agents filter tests by privilege, use Pester tags: `AdminOnly`, `DevModeOnly`, `NonAdmin`, `Standard`. Alternatively use the `JDM_TEST_MODE` env var so tests can adapt.

