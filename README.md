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

`jdm` fills this gap. It wraps `winget` to install JDKs and manages version switching through a Windows link, so you can change the active version with one command.

---

## Terminal Output

`jdm install` launches winget and waits for it to finish. jdm then detects the JDK's install path and records it. Winget may show its own progress in a separate process window.

---

## How It Works

`jdm` asks winget to install each JDK in winget's normal install location; it does not move the JDK files into a jdm folder. It records the detected install path and version key in `~/.jdm/registry.json`.

The link `~/.jdm/candidates/java/current` points to the active JDK. `JAVA_HOME` and PATH are set to use that link, so switching versions changes the link target.

```
~/.jdm/
  candidates/
    java/
      current/          ← symlink → active version
  registry.json         ← tracks all installed versions
  module/               ← jdm PowerShell scripts
```

---

## Requirements

- Windows 10 or later
- PowerShell 5.1+ *(pre-installed on Windows 10/11)*
- [winget](https://apps.microsoft.com/detail/9nblggh4nns1) (App Installer — available from the Microsoft Store)
- Administrator privileges or Developer Mode enable symbolic links; jdm can use a junction fallback without them.

> **Note on links:** jdm prefers a symbolic link when Windows permits it and falls back to a junction otherwise. This usually lets you switch versions without elevation. The bootstrap installer can run in a normal PowerShell session.

By default, setup changes your user-level environment. Running setup or `jdm use` as Administrator can also change machine-level JAVA_HOME and PATH.

---

## Installation

**Terminal (PowerShell, recommended hosted install):**

```powershell
irm https://raw.githubusercontent.com/jerryperezperez/jdm/v0.2.0/install.ps1 | iex
```

If you want `jdm` to also update machine-level environment variables during install, run either command from an elevated PowerShell session. That is optional.

**GUI installer:**

Download `jdmInstaller.exe` from the [Releases](https://github.com/jerryperezperez/jdm/releases) page and double-click. Same installer flow, wrapped for non-terminal users via `ps2exe`.

If switching a Java version fails while creating its link, enable Developer Mode or rerun the affected `jdm use` command in an elevated PowerShell window.

---

## Usage

```powershell
# Install multiple JDKs
jdm install temurin.21
jdm install corretto.17

# Show versions tracked by jdm
jdm list

# Switch active version
jdm use corretto.17
java -version

# Remove a version
jdm uninstall temurin.21

# Remove every JDK tracked by jdm (prompts for confirmation)
jdm uninstall --all-vendors

# Remove jdm itself; this leaves JDKs installed
jdm uninstall --self

# Show version
jdm version
```

> **Note:** Version keys use dot format (`vendor.version`, e.g., `temurin.21`) consistently across all commands. Hyphen format (`temurin-21`) is accepted by `use` and `uninstall` for backward compatibility but is deprecated and will be removed in a future release.

The first JDK you install is activated automatically. When you install another JDK, jdm asks whether to make it active. If winget returns several JDK matches, jdm asks you to choose one. `-Force` skips the prompts, selects the first match, and accepts the default install and activation choices, so use it only when you are comfortable with those choices.

### Existing JDKs

`jdm list` shows versions in jdm's registry; it does not inventory every JDK on the machine. There is no general-purpose import command for arbitrary JDK folders.

If winget reports that the requested package is already installed, jdm reuses a detected path only when it finds exactly one Java installation in the locations it scans (Program Files, Program Files (x86), LocalAppData, and AppData). If it finds zero or multiple paths, it stops rather than guessing. Installations outside those locations may not be detected. Existing JDKs that are not registered with jdm are not included in `jdm uninstall --all-vendors`.

### Removing JDKs and jdm

- `jdm uninstall temurin.21` removes that tracked JDK. If it is active and other tracked versions remain, jdm asks which one to activate next.
- `jdm uninstall --all-vendors` attempts to remove every tracked JDK; it does not remove untracked JDKs.
- `jdm uninstall --self` removes jdm and its user settings but leaves JDKs installed. Machine-level PATH entries may need separate Administrator cleanup.

If bulk uninstall reports failures, check the listed winget packages and install paths afterward. The command continues cleanup after failures, and a failed JDK may no longer appear in `jdm list`.

### PATH behavior

When switching versions, jdm removes existing PATH entries whose text matches Java, JDK, or supported vendor names, then puts the jdm link first. This does not delete those JDK files, but it can remove unrelated PATH entries with matching names. When run as Administrator, it also updates machine PATH. Consider saving your current PATH and using a normal PowerShell session unless you want system-wide changes.

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
       Path    : C:\Program Files\Eclipse Adoptium\jdk-21...

       corretto.17
       Vendor  : corretto
       Version : 17
       Path    : C:\Program Files\Amazon Corretto\jdk-17...
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
