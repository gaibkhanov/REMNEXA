[English](DEVELOPMENT_WORKFLOW.md) | [Deutsch](DEVELOPMENT_WORKFLOW.de.md)

# Development workflow

The canonical source is the [REMNEXA repository](https://github.com/gaibkhanov/REMNEXA). Use a local checkout of your choice; project documentation must not depend on a contributor's personal filesystem.

## Branches and scope

- `main`: existing stable baseline.
- `feature/2.2.0-development`: current 2.2.0 development work.
- `feature/2.2.0-release-candidate`: 2.2.0-rc.1 hardening and source-package preparation.
- Further feature branches: focused changes based on an identified commit.

Inspect `git status`, branch, remote and diff before editing. Preserve uncommitted changes. Do not overwrite releases, rewrite shared history, force-push or merge into the stable branch without the required maintainer approval.

The development source excludes optional runtime payloads, ClamAV executables/signatures, backups and private logs. Do not copy entire machine-specific application folders into Git.

## Local checks

Use PowerShell 7.5+; install Pester (minimum 3.4.0 for the local runner) and PSScriptAnalyzer 1.24.0 in the development environment.

```powershell
pwsh -NoProfile -File .\tools\Invoke-RemnexaTests.ps1
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
git diff --check
```

Run these from the repository root. If analyzer modules live outside the normal module search path, pass their containing directory through `-ModuleRoot`. The analyzer runner reports all findings and fails on errors; warnings still require review.

The self-test inventories selected system capabilities but does not uninstall applications or establish that every operation is safe. Tests must use isolated fixtures/mocks for sensitive operations.

## CI

[quality.yml](../.github/workflows/quality.yml) targets `windows-latest`, pins Pester 5.7.1 and PSScriptAnalyzer 1.24.0, runs Pester and an analyzer error gate, and requires PowerShell 7.5+.

Its path filters run on PowerShell/test/workflow/configuration/locale changes; documentation-only pushes do not automatically trigger that workflow. A manual dispatch is available. Configured CI is not proof of a successful run; check actual results before merging.

The workflow also builds/verifies the source candidate and uploads its ZIP/checksum as a workflow artifact. This is not a GitHub release. Build commands and local candidate results are in the [candidate report](CLAMAV_SMART_UPDATES.md).

## Review and publication

1. Describe the behavior change and affected interfaces.
2. Run relevant checks and record real versions/counts, failures and remaining limits.
3. Maintain English/German documentation and six-language UI resources where affected.
4. Inspect staged changes for secrets, private paths, generated artifacts and accidental deletions.
5. Commit focused changes and push only the intended branch; verify the remote commit.
6. Prepare release artifacts only after separate compatibility, packaging, security and recovery validation.

See [2.2.0 verification](VERSION_2.2.0.md), [analysis baseline](STATIC_ANALYSIS_BASELINE.md) and [backup guide](BACKUP_AND_CHECKPOINTS.md). A source push is not a stable release or permission to publish one.
