# Contributing to REMNEXA

Thanks for helping improve REMNEXA. The current baseline is a Windows PowerShell application; keep changes small, reviewable and compatible with existing command-line and interactive workflows.

## Development setup

- Windows 10 or 11.
- PowerShell 7.5 or newer (`pwsh.exe`). Windows PowerShell 5.1 can parse some files but cannot run the application.
- Pester 5.7.1 or newer for tests and PSScriptAnalyzer for static analysis. The repository workflow pins the versions used in CI.

The maintainer's active checkout is `C:\Dev\REMNEXA`. Build 2.2.0 was imported from the verified OneDrive development snapshot without rewriting the existing Git history. The import and current validation evidence are recorded in [the development workflow](docs/DEVELOPMENT_WORKFLOW.md). Keep later changes in this checkout on feature branches; the OneDrive copy is not automatically synchronized.

## Before opening a change

1. Start from the latest `main` in a feature branch.
2. Run `./tools/Invoke-RemnexaTests.ps1`; it supports the installed Pester 3 or Pester 5 and returns a failing process status when any test fails. Run `./tools/RunPSScriptAnalyzer.ps1 -ProjectRoot . -ModuleRoot ./tools/Modules` for the local static-analysis report.
3. Add a regression test for every fixed defect. Keep tests in temporary directories and isolated test registries; never run destructive checks on a daily-use Windows installation.
4. Preserve existing features and document any behavior change, compatibility limit or irreversible operation.
5. Do not include personal logs, local settings, `runtime/`, ClamAV binaries/signatures, or historical `Backup-*` directories in source changes.

## Security-sensitive changes

Changes involving file paths, registry, services, scheduled tasks, elevation, downloads, quarantine or restore require a threat review and tests for invalid input, partial failure and cancellation. Unknown ownership should fail closed. Never pass generated text to a shell or disable Windows security controls.

## Pull requests and releases

Keep commits focused and explain the user-visible result and test evidence. Pull requests may propose release candidates; production publication and release creation require maintainer approval. Do not rewrite existing release history.

The checked-in workflow and this guide are part of the isolated audit snapshot and have not yet been validated by a GitHub Actions run.
