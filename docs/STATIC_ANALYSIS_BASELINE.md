# Static analysis baseline

**Date:** 2026-11-16\
**Analyzer:** PSScriptAnalyzer 1.24.0 on PowerShell 7.6.9\
**Scope:** 58 first-party PowerShell source, module, manifest, test and developer-tool files. Historical backups, runtime payloads, ClamAV vendor files and the bundled analyzer module were excluded.

## Result

- Errors: **0**
- Warnings: **230**
- Informational findings: **44**
- Total findings: **274**

The CI workflow and local runner gate on analyzer errors, so the local error gate passes. The warning set is a baseline, not a claim that every warning is harmless or resolved. The rule-by-rule notes below were written during the earlier 50-file scan; the expanded scope includes first-party tools and still needs a fresh rule-level review.

## Warning triage

- **157 `PSAvoidUsingWriteHost`:** REMNEXA is a console interface and deliberately uses colored host output for menus, progress and results. Replacing these calls wholesale would change the interface and output behavior; revisit them as part of the UI boundary work in Phase C/F.
- **13 `PSAvoidUsingEmptyCatchBlock`:** several catches are best-effort console, host-title or optional-system probes. Review each with its surrounding operation before changing error behavior; do not add noisy errors to expected fallback paths.
- **9 `PSUseShouldProcessForStateChangingFunctions`:** the flagged functions are `New-FreshClamConfiguration`, `Update-ClamAVSignature`, `New-RemnexaAiRequest`, `New-RemnexaOperationResult`, `Set-OperationProgress`, `New-RestorePointIfPossible`, `Remove-RegistryTrace`, `Remove-Traces` and `Set-PrivacyProfile`. The two request/result constructors only build in-memory data; these are false positives from the verb-based rule. Other functions still need a focused `-WhatIf`/`ShouldProcess` design review before the warning is suppressed or fixed.
- **19 `PSReviewUnusedParameter`:** includes the script's legacy command-line parameters, which are consumed by its dispatcher and compatibility paths. Preserve the public command-line interface while checking these during modularization.
- **22 `PSUseSingularNouns`:** existing function names are used by current modules and call sites. Renaming them needs compatibility wrappers and regression coverage.
- **4 `PSUseBOMForUnicodeEncodedFile`:** the files are UTF-8 without BOM and run on the declared PowerShell 7.5+ baseline. Do not rewrite encodings until the packaging/compatibility policy is set.
- **1 `PSAvoidAssignmentToAutomaticVariable`:** review the flagged assignment before changing it; preserve the legacy call surface.
- Remaining warnings concern global compatibility variables and a legacy helper verb; review those with the API and logging changes.
- The 41 informational findings are split between 16 `PSProvideCommentHelp` and 25 `PSUseOutputTypeCorrectly` findings.

## Verification limits

PSScriptAnalyzer was obtained from the PowerShell Gallery over HTTPS. Its SHA-512 package hash matched the Gallery's version metadata. The package was extracted only to the isolated workspace for analysis and is not an application dependency. GitHub Actions has not run because version control is intentionally not used in this workflow.
