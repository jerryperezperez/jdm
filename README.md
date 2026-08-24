[![Quality gate status](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Bugs](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=bugs)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Code Smells](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=code_smells)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Duplicated Lines (%)](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=duplicated_lines_density)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![software_quality_security_issues](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=software_quality_security_issues)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm) [![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=jerryperezperez_jdm&metric=vulnerabilities)](https://sonarcloud.io/summary/new_code?id=jerryperezperez_jdm)

# jdm — Java Version Manager for Windows

> The SDKMAN you always wanted, but for Windows.

`jdm` is a native Windows Java version manager. Install and switch between multiple JDK versions from different vendors — Temurin, Corretto, Azul, Microsoft — using simple CLI commands. No WSL. No Linux layer. No headaches.

---

## Why jdm?

[SDKMAN](https://sdkman.io/) is the gold standard for managing Java SDKs on Linux and macOS. Windows developers have never had an equivalent. Existing tools each fall short in a different way:

| Tool | Problem |
|------|---------|
| Scoop | General package manager — not focused on SDK version switching |
| Jabba | Abandoned since 2021, unmaintained |
| winget | No version switching — installs as a system app |
| SDKMANforWindows | Never reached a usable state, abandoned |

`jdm` fills this gap. It wraps `winget` for safe, verified downloads and manages version switching via Windows symlinks — so switching Java versions is a single command, and takes effect in every new terminal without touching system-level config again.

---

## Terminal Output

Starting with v0.3.0, `jdm install` streams winget's download and installation progress directly to your terminal. You'll see:

- Download progress bars
- Installation status messages
- Error details (if any)

Winget output is indented and dimmed to distinguish it from jdm's own messages.

---

## How It Works

`jdm` installs JDKs into `~/.jdks/` and tracks them in a local `registry.json`. A symlink at `~/.jdm/candidates/java/current` always points to the active version. `JAVA_HOME` and `PATH` are configured once during setup to point at that symlink — switching versions just updates where the symlink points, so your environment variables never need to change again.

```
~/.jdm/
  candidates/
    java/
      temurin.21/       ← installed JDK files
      corretto.17/      ← installed JDK files
      current/          ← symlink → active version
  registry.json         ← tracks all installed versions
  module/               ← jdm PowerShell scripts
```

---

## Requirements

- Windows 10 or later
- PowerShell 5.1+ *(pre-installed on Windows 10/11)*
- [winget](https://apps.microsoft.com/detail/9nblggh4nns1) (App Installer — available from the Microsoft Store)
- **Administrator privileges OR Developer Mode enabled** *(required for symlink creation when switching versions)*

> **Note on symlinks:** Windows requires either Administrator rights or Developer Mode (`Settings -> For developers -> Developer Mode`) to create directory symlinks. The bootstrap installer can run in a normal PowerShell session, but `jdm use` and the first automatic activation of a JDK still need one of those permissions.

---

## Installation

**Terminal (PowerShell, recommended hosted install):**

```powershell
irm https://raw.githubusercontent.com/jerryperezperez/jdm/v0.2.0/install.ps1 | iex
```

If you want `jdm` to also update machine-level environment variables during install, run either command from an elevated PowerShell session. That is optional.

**GUI installer:**

Download `jdmInstaller.exe` from the [Releases](https://github.com/jerryperezperez/jdm/releases) page and double-click. Same installer flow, wrapped for non-terminal users via `ps2exe`.

If installation succeeds but switching a Java version later fails with a permission error, enable Developer Mode or rerun the affected `jdm use` command in an elevated PowerShell window.

---

## Usage

```powershell
# Install a JDK
jdm install temurin.21
jdm install corretto.17
jdm install azul.21

# Switch active version
jdm use temurin.21
jdm use corretto.17

# List installed versions
jdm list

# Remove a version
jdm uninstall corretto.17

# Remove ALL installed JDKs (bulk, prompts for confirmation)
jdm uninstall --all-vendors

# Remove jdm itself
jdm uninstall --self

# Show version
jdm version
```

> **Note:** Version keys use dot format (`vendor.version`, e.g., `temurin.21`) consistently across all commands. Hyphen format (`temurin-21`) is accepted by `use` and `uninstall` for backward compatibility but is deprecated and will be removed in a future release.

### Example session

```
$ jdm install temurin.21

  --> Searching for 'temurin.21'...

  Found multiple matches:

    1. Eclipse Temurin 21 JDK  (EclipseAdoptium.Temurin.21.JDK)
    2. Eclipse Temurin 21 JRE  (EclipseAdoptium.Temurin.21.JRE)

  Which one? (1-2): 1

  --> Installing EclipseAdoptium.Temurin.21.JDK via winget...
  [OK] JDK installed at: C:\Program Files\Eclipse Adoptium\jdk-21...
  [OK] Installed : temurin.21
  [OK] Active    : temurin.21 (current)

  Open a new terminal and run: java -version
```

```
$ jdm list

  Installed Java versions:

  --> temurin.21  (current)
       Vendor  : temurin
       Version : 21
       Path    : C:\Users\user\.jdm\candidates\java\temurin.21

       corretto.17
       Vendor  : corretto
       Version : 17
       Path    : C:\Users\user\.jdm\candidates\java\corretto.17
```

---

## Supported Vendors

| Alias | Vendor |
|-------|--------|
| `temurin` | Eclipse Temurin (Adoptium) |
| `corretto` | Amazon Corretto |
| `azul` | Azul Zulu |
| `microsoft` | Microsoft OpenJDK |

---

## Project Structure

```
jdm/
  install.ps1               ← bootstrapper (one-liner installer)
  module/
    jdm.ps1                 ← CLI entry point / command router
    commands/
      install.ps1           ← install flow
      use.ps1               ← version switching
      list.ps1              ← list installed versions
      uninstall.ps1         ← remove a version / self-uninstall
    core/
      registry.ps1          ← read/write registry.json
      winget.ps1            ← winget search + install wrapper
      symlink.ps1           ← symlink management, JAVA_HOME, PATH
```

---

## Building the Executable

To build the standalone `.exe` locally:

```powershell
Install-Module -Name PS2EXE -Scope CurrentUser -Force
New-Item -ItemType Directory -Path .\dist -Force
Invoke-PS2EXE -InputFile .\module\jdm.ps1 -OutputFile .\dist\jdm.exe -noConsole
```

---

## License

[GNU Affero General Public License v3.0](./LICENSE)
