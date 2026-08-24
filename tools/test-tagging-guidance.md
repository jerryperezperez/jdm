Test tagging guidance for jdm Pester tests

Purpose
- Provide a minimal, practical tagging strategy so an external agent/skill can filter tests based on privilege.

Recommended tags
- AdminOnly: tests that require elevated privileges or will perform actions requiring Administrator rights.
- DevModeOnly: tests that assume Developer Mode is enabled but do not require full admin rights.
- NonAdmin: tests that should run as a standard user; verify fallback behavior.
- Standard: tests that can run in any privilege context and should always be run.

How to apply
- Add tags to Describe/Context/It blocks in Pester tests, for example:

Describe 'symlink behavior' -Tag NonAdmin,Standard {
    It 'creates symlink when DevMode is enabled' -Tag DevModeOnly { ... }
    It 'falls back when symlink not possible' -Tag NonAdmin { ... }
}

How the external agent should use tags
- Administrator: run without filtering (all tags)
- DevModeNonAdmin: run tests tagged Standard, DevModeOnly, NonAdmin
- NonAdmin: run tests tagged Standard, NonAdmin

Notes
- Tag names are suggestions; pick a convention and apply it consistently across tests in tests/commands and tests/core.
- If changing many tests is expensive, an interim approach is to export an env var (JDM_TEST_MODE) and adapt a small number of tests to read that variable and skip/adjust behavior accordingly.
