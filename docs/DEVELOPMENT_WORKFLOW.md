# Git development workflow

## Source of the 2.2.0 baseline

On 16 November 2026, the existing Git checkout at `C:\Dev\REMNEXA` received the maintainer's current development snapshot from `%OneDrive%\Software\REMNEXA-2.2.0`.

- Existing stable branch: `main`.
- Existing baseline commit: `652360ebd8751be5f66b579e9e7d18854d8bb4de` (2.1.3).
- Development branch: `feature/2.2.0-development`, based on that commit.
- Remote: `origin`, `https://github.com/gaibkhanov/REMNEXA`.
- Git: 2.56.0.windows.4, using the maintainer's existing author configuration.
- Source application SHA-256: `7D6B5B91F2F8A4C78AAB2ECD6A2BBFD23FF2FDBB3EB90173150E9D822754AEB4` for `REMNEXA.ps1`.

All 95 imported source, asset, configuration, documentation and test files matched the source snapshot's SHA-256 manifest before import. The application code remains the 2.2.0 development implementation; subsequent handover edits concern Git ignores and documentation.

Three malformed source locations in the old checkout were normalized using the verified development files:

- `Antivirus/Public/Get-AVConfig.ps1/Get-AVConfig.ps1` → `Antivirus/Public/Get-AVConfig.ps1`.
- `Examples/Invoke-AntivirusWorkflow.ps1/Invoke-AntivirusWorkflow.ps1` → `Examples/Invoke-AntivirusWorkflow.ps1`.
- `config/antivirus.json/antivirus.json` → `config/antivirus.json`.

The previous files remain recoverable from the original Git commit. Separate local copies and the import hash report were also preserved outside this repository. No existing Git history, release or OneDrive file was overwritten.

## Local payloads and backups

The existing portable PowerShell runtime, ClamAV engine/signatures and local analyzer module were copied to the checkout for continued local development. Each copied file was compared with its source by SHA-256: 998 files total, including the 95 source files. These copied third-party payloads are not newly downloaded or independently authenticated vendor releases.

`runtime/`, `ClamAV/`, `tools/Modules/`, local NuGet packages, historical `Backup-*` directories and local distribution manifests are ignored by Git. They are not repository source or a reproducible release manifest. No historical backup trees were copied into the checkout. The existing OneDrive backups remain available in their original locations.

The OneDrive directory remains a runnable snapshot. It is not automatically synchronized with Git. Future edits should use `C:\Dev\REMNEXA`; copy an explicitly tested build to a distribution folder when needed. Both copies still use the application's existing local settings/log directory unless a future change explicitly adds isolated profiles.

## Working on later changes

Use a feature branch, review `git status` and `git diff`, run the relevant tests, then make a focused local commit. Preserve the stable `main` branch and existing history. Pushing source branches, opening pull requests, merging and publishing production releases are distinct actions; a local commit does not publish anything on GitHub.

PowerShell 7.5+ is required. The local optional runtime allows the following checks from the checkout:

```powershell
.\runtime\pwsh.exe -NoProfile -File .\tools\Invoke-RemnexaTests.ps1
.\runtime\pwsh.exe -NoProfile -File .\REMNEXA.ps1 -SelfTest
```

Pester must be available to the development host. The existing local Pester 3.4.0 is supported by the test runner; CI pins Pester 5.7.1. The checked-in GitHub Actions workflow has not yet run for this imported branch. A prior local analyzer aggregation run hit an internal null-reference error; sequential per-file analysis succeeded. Do not interpret static-analysis warnings as resolved merely because the error count is zero.

## Validation in the Git checkout

The imported checkout was checked using its own copied PowerShell runtime:

- Pester 3.4.0: 79 passed, 0 failed, 0 skipped.
- Application self-test: all 12 checks passed, reporting version 2.2.0 and all 282 localization keys in six languages.
- Syntax parsing: 64 first-party PowerShell files, no syntax errors.
- PSScriptAnalyzer 1.24.0 error-severity gate: all 64 files, 0 errors.
- Source-file hash comparisons confirmed the imported application code against the OneDrive snapshot. Optional copied payload files were also individually verified.
- A limited credential-pattern scan found no matching private-key headers or common access-token formats in the 93 source/documentation text files. This is not a guarantee that every possible secret format is detectable.

The full warning-level analyzer run in the new checkout encountered the known intermittent internal null-reference failure while examining `tests/Navigation.Tests.ps1`. The separate error-severity gate completed successfully. A fresh complete warning report, Pester 5 and remote GitHub Actions remain unverified for this checkout. No destructive system tests, real uninstall operations or production releases were performed for this import.

## Release status

This is the versioned 2.2.0 development baseline. It is not REMNEXA 3.0.0, a validated installer or a production release. Model inference, full AI features and a release candidate remain open as documented in the roadmap. Production publication requires successful validation and explicit maintainer approval.
