[English](VERSION_2.2.0.md) | [Deutsch](VERSION_2.2.0.de.md)

# REMNEXA 2.2.0 development report

**Status:** development source, not a published stable release or REMNEXA 3.0. The current development branch is `feature/2.2.0-development`. Start from the [README](../README.md).

## Implemented changes

- Read-only Windows/CPU/memory/fixed-drive overview, collected on demand.
- Six external language resources, German fallback and completeness checks.
- Core modules for settings, logging, native processes, permissions, outcomes and selected validation.
- Atomic validated writes for supported application/antivirus configuration.
- ClamAV HTTPS/SHA-256 checks, staged engine installation and configuration-commit recovery.
- Fixed allowlist/schema validation before supported privacy-backup restores.
- Linked-path rejection and intentional WindowsApps retention during cleanup.
- Accurate Registry failure/parent-coverage accounting, concrete access errors and remaining-item logs.
- Removal completion/history saved at 100% before optional system assessment.
- Contextual service/antivirus reporting, without duplicate Defender warnings or assumed protection from registration alone.
- Verified new restore-point reporting rather than treating throttled creation as success.
- Action-specific administrator explanations and direct Antivirus elevation routing.
- Validated pagination and one visible exit choice at each input prompt.
- AI data contracts only; they do not provide inference or chat.

## Recorded verification baseline

These results describe the application baseline before the documentation-only revision. They are not newly executed tests of this documentation change.

| Check | Recorded result |
| --- | --- |
| Pester 3.4.0 on PowerShell 7.6.9 | 79 passed, 0 failed, 0 skipped. |
| Application self-test | 12 passed. |
| Translation resources | 282 keys across each of six languages. |
| First-party PowerShell parsing | 64 files, 0 syntax errors. |
| PSScriptAnalyzer 1.24.0 error-only gate | 64 files, 0 errors. |
| Earlier sequential full analysis of this application code | 0 errors, 322 warnings, 49 informational findings. |
| Full warning-level run in Git checkout | Intermittent null-reference failure on a navigation test file; not a completed clean run. |
| GitHub Actions / Pester 5.7.1 | Configured, successful run not verified in this report. |

Sensitive tests use mocks or isolated directories; these results do not establish successful real uninstallations, complete rollback or all Windows versions. Read the [analysis baseline](STATIC_ANALYSIS_BASELINE.md).

## Known limits

Filesystem checks retain a time-of-check/time-of-use window. Ownership attribution is partly heuristic. ClamAV signature-update failures after engine installation are outside the engine transaction. Source checkpoints skip reparse points and do not lock the source.

No complete Windows VM matrix, performance baseline, installer/deinstaller test suite, central restore center, full offline distribution, valid signing process or release candidate is available. No embedded AI runtime/model, model redistribution decision or model benchmarks have been delivered.

## Next work

Prioritize recovery and attribution tests, warning triage and measured compatibility before broadening functionality. Follow the [roadmap](DEVELOPMENT_ROADMAP.md). Publishing a production release requires separate validation and explicit approval.
