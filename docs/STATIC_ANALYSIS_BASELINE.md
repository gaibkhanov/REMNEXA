[English](STATIC_ANALYSIS_BASELINE.md) | [Deutsch](STATIC_ANALYSIS_BASELINE.de.md)

# Static analysis baseline

**Tool:** PSScriptAnalyzer 1.24.0 on PowerShell 7.6.9. This is a recorded application-code baseline, not a new scan of the documentation revision.

## Scope and results

Scope is 64 first-party PowerShell source, module, manifest, test and developer-tool files. Historical backups, vendor runtime/ClamAV content and analyzer dependencies are excluded.

| Run | Errors | Warnings | Information | Interpretation |
| --- | --- | --- | --- | --- |
| Earlier sequential full analysis of the same application code | 0 | 322 | 49 | Recorded warning baseline, not warning-free certification. |
| Error-only gate in the Git checkout | 0 | Not requested | Not requested | Completed error gate across 64 files. |
| Full warning-level run in the Git checkout | Incomplete | Incomplete | Incomplete | Intermittent null-reference failure on `tests/Navigation.Tests.ps1`. |

Do not combine a successful error-only gate with an incomplete full run and describe it as a complete new analysis. Older smaller-scope counts are superseded by this scope and should not be compared as though the file set were identical.

## Triage priorities

- Review empty catch blocks and state-changing functions without consistent `ShouldProcess` semantics.
- Inspect automatic-variable assignments, unused parameters and global compatibility state before refactoring.
- Console `Write-Host` calls are often intentional UI output, but each warning still needs contextual review.
- Preserve callable interfaces when addressing plural nouns or legacy verbs.
- In-memory request/result constructors do not mutate the system merely because their names start with New; assess such findings individually.
- Evaluate encoding, comment-help and output-type findings against the declared PowerShell 7.5+ runtime.

Do not suppress categories wholesale or claim every warning harmless. Detailed per-rule counts from smaller historical runs are not a current full triage.

## Reproduce

Install PSScriptAnalyzer 1.24.0, then run from the project root:

```powershell
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
```

The runner prints findings and fails on analyzer errors. The complete run may reproduce the documented tool failure. Capture sanitized failure details and isolate a minimal reproduction; do not alter tests simply to conceal it.

The [CI workflow](../.github/workflows/quality.yml) uses an error-only gate. Its definition is not evidence of a passed remote run. See [workflow](DEVELOPMENT_WORKFLOW.md) and [verification report](VERSION_2.2.0.md).
