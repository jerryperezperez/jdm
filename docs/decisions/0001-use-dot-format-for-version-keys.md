---
status: "accepted"
date: 2026-08-22
decision-makers: jerry
---

# Use dot format consistently for version keys in jdm CLI

## Context and Problem Statement

`jdm install` expects dot format (`temurin.21`), but `jdm use`, `jdm uninstall`, and `jdm list` use hyphen format (`temurin-21`). This inconsistency confuses users. The dot format is the natural choice because:

1. It matches the user's input to `install`, which is the most common entry point.
2. It aligns with the `winget` package ID convention (`EclipseAdoptium.Temurin.21.JDK`).
3. It avoids requiring users to remember two different format conventions for the same entity.

The internal registry currently stores version keys as hyphen format (e.g., `temurin-21`), produced by `Get-RegistryKey` in `winget.ps1`. Changing this affects display, input parsing, and backward compatibility with existing registries.

## Decision

Use dot format (`vendor.version`, e.g., `temurin.21`) as the canonical user-facing format for all CLI commands: `install`, `use`, `list`, `uninstall`. Accept both dot and hyphen input for `use` and `uninstall` to maintain backward compatibility with existing registries that contain hyphen keys.

## Consequences

* Good, because users only need to learn one format across all commands.
* Good, because dot format aligns with `winget` ID conventions and is what `install` already accepts.
* Good, because backward compatibility is preserved: existing registries with hyphen keys continue to work.
* Bad, because there is a brief period where new installs produce dot keys while old entries remain hyphen, creating mixed registries until users reinstall or we add migration.
* Neutral, because the migration is transparent: `list` will show both formats, and `use`/`uninstall` accept both.

## Implementation Plan

### Phase 1: Core normalization layer

**`module/core/registry.ps1`**:
- Add `Normalize-VersionKey` function: converts hyphen to dot format (e.g., `temurin-21` -> `temurin.21`). This is the single source of truth for format conversion.
- Update `Test-VersionInstalled` to normalize the input key before lookup, AND check both original and normalized forms for backward compat.
- Update `Get-Version` to normalize the input key and try both forms.
- Update `Set-CurrentVersion` to normalize.
- Update `Remove-Version` to normalize.

**`module/core/winget.ps1`**:
- Update `Get-RegistryKey` to produce dot format: change `return "$vendor-$version"` to `return "$vendor.$version"`.

### Phase 2: Command layer

**`module/commands/use.ps1`**:
- Normalize `$Key` at entry: `$Key = Normalize-VersionKey -Key $Key`
- Update help text/error messages to show dot format.

**`module/commands/uninstall.ps1`**:
- Normalize `$Key` at entry.
- Update help text/error messages to show dot format.

**`module/commands/list.ps1`**:
- Display keys as returned by `Get-AllVersions` (which will now be dot format for new entries, hyphen for old).
- Add a `Normalize-VersionKey` call in `Get-AllVersions` so the display is always dot format regardless of stored format.

**`module/commands/install.ps1`**:
- No logic changes needed -- `Build-Query` already normalizes input.
- Update display messages to show dot format for the key.

### Phase 3: Help text and docs

**`module/jdm.ps1`**:
- Update `Show-Help`: change `use VENDOR-VERSION` to `use VENDOR.VERSION`, `uninstall VENDOR-VERSION` to `uninstall VENDOR.VERSION`.
- Update examples: `jdm use temurin.21`, `jdm uninstall corretto.17`.
- Update `Invoke-Jdm` switch block: error messages use dot format.

**`README.md`**:
- Update all usage examples to use dot format consistently.
- Update example sessions to show dot format in output.

### Phase 4: Tests

- Update all test files that assert hyphen keys to assert dot keys where the code path goes through `Get-RegistryKey` or `Normalize-VersionKey`.
- Add new tests for `Normalize-VersionKey` (accepts dot -> returns dot; accepts hyphen -> returns dot).
- Add test for backward compat: `Test-VersionInstalled` works with both formats.
- Add test for `use` command accepting dot format input.
- Add test for `uninstall` command accepting dot format input.

### Patterns to follow

- All normalization goes through `Normalize-VersionKey`. No ad-hoc string replacement in commands.
- Registry lookup functions accept both formats internally, but the canonical stored format is dot.

### Patterns to avoid

- Do NOT change the on-disk JSON structure of existing entries. Old hyphen keys stay hyphen in the JSON.
- Do NOT break `Build-Query` or the winget search flow.
- Do NOT require migration of existing registries.

## Verification

- [ ] `jdm install temurin.21` works (already works, regression test).
- [ ] `jdm use temurin.21` works.
- [ ] `jdm use temurin-21` still works (backward compat).
- [ ] `jdm uninstall temurin.21` works.
- [ ] `jdm uninstall temurin-21` still works (backward compat).
- [ ] `jdm list` displays keys in dot format (e.g., `temurin.21`).
- [ ] Help text shows dot format for all commands.
- [ ] README examples use dot format consistently.
- [ ] All existing Pester tests pass.
- [ ] New tests cover `Normalize-VersionKey` and backward compat paths.

## Alternatives Considered

* **Migrate all existing registry keys to dot format**: Rejected because it adds complexity (need migration logic, risk of data loss) with no user benefit. Old hyphen keys work fine with the normalization layer.
* **Keep internal storage as hyphen, only normalize display**: Rejected because it means every command needs display transformation, and `use`/`uninstall` would still silently fail if users type the natural dot format.
* **Fully switch internal keys to dot with no backward compat**: Rejected because it would break existing users' registries silently.

## More Information

- The `Build-Query` function in `winget.ps1` already normalizes hyphens to dots for winget search, proving this pattern is already established in the codebase.
