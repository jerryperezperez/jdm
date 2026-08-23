# AGENTS.md

Guidance for OpenCode sessions working in **jdm** (Java Version Manager for Windows) — a pure PowerShell 5.1+ module, no .NET/Java build step.

## Commands

- **Lint:** `Invoke-ScriptAnalyzer -Path ./module -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
- **Test (all):** `Invoke-Pester -Configuration ./pester.configuration.ps1` — runs everything under `./tests`, emits JUnit + JaCoCo coverage XML to `./coverage`.
- **Test (single file):** `Invoke-Pester -Path ./tests/commands/install.tests.ps1`
- **Build EXE:** `Invoke-PS2EXE -InputFile .\module\jdm.ps1 -OutputFile .\dist\jdm.exe -noConsole` (requires `Install-Module PS2EXE`).
- **CI order is enforced:** lint → test → sonarqube (each job `needs` the prior). Tests won't run until lint is clean.
- **Test logic is duplicated:** `_test.yml` is a reusable workflow nothing calls; `build.yml` carries its own inline copy of the Pester + coverage-gate steps. Change both or drop the unused one.

## Architecture

- `module/jdm.ps1` is the CLI entry point / command router. **It guards dot-sourcing** with `if ($MyInvocation.InvocationName -ne '.')`; this guard is required so Pester can dot-source it without firing the CLI. Do not remove it.
- `module/commands/*.ps1` — `install`, `use`, `list`, `uninstall` (each exposes one `Invoke-*` function).
- `module/core/*.ps1` — `registry` (state), `winget` (search/install wrapper), `symlink` (JAVA_HOME/PATH).
- Tests mirror this layout: `tests/commands/*` and `tests/core/*`. Test files dot-source the real module files and stub the `Write-*` helpers / external commands.
- **No in-repo state.** Installed-version state lives in `$env:USERPROFILE\.jdm\registry.json`; the active JDK is a symlink at `~/.jdm/candidates/java/current`. JDKs are installed via `winget` into Program Files / `~/.jdks`. `install.ps1` is the bootstrap that copies the module to `~/.jdm` and sets PATH/JAVA_HOME.
- Requires Windows + `winget`. Creating the version symlink needs **Administrator or Developer Mode**.

## Conventions & gotchas

- **Version keys use dot format** `vendor.version` (e.g. `temurin.21`) everywhere except `use`/`uninstall`, which still accept deprecated hyphen format (`temurin-21`). Normalization happens in `core/registry.ps1` `Normalize-VersionKey` (ADR-0001).
- **Version string is hardcoded** in `module/jdm.ps1` (`$jdm_VERSION`) and `jdm.psd1` (`ModuleVersion`), and the README install one-liner pins a tag. Bump all three on release. (README references `v0.3.0` streaming behavior while the code is `0.2.0` — docs are ahead of the build.)
- **PSScriptAnalyzer** runs at Error+Warning severity but excludes `PSAvoidUsingWriteHost`, `PSUseApprovedVerbs`, `PSUseSingularNouns`, `PSUseShouldProcessForStateChangingFunctions`, and `PSUseBOMForUnicodeEncodedFile` — so `Write-Host` and non-approved verbs are intentional, not lint failures.
- **Coverage thresholds disagree:** `pester.configuration.ps1` sets an 80% target, but CI computes and enforces its own 70% line-coverage gate from the JaCoCo XML. Aim for the stricter 80%.
- `opencode.json` lists `instructions: ["src/main/java/AGENTS.md"]`, which does **not exist** — configured instruction loading is effectively a no-op. It also contains live `GITHUB_PERSONAL_ACCESS_TOKEN` and `SONARQUBE_TOKEN` in plaintext; never echo or commit them.
