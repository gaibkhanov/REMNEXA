# REMNEXA 3.0 development roadmap

**Baseline:** REMNEXA 2.1.3, GitHub `main` as read-only compared during the audit.\
**Release state:** no 3.0 release or release candidate exists. Production publication remains gated on validation and Salim's explicit approval.

**Current development:** 2.2.0, imported from the verified OneDrive folder into `C:\Dev\REMNEXA` on `feature/2.2.0-development`. Git 2.56.0.windows.4 is available. The current delivery record is `VERSION_2.2.0.md`; the Git handover is recorded in `DEVELOPMENT_WORKFLOW.md`. Older phase checkpoints below remain historical evidence, not the latest test totals.

## Phase A — Audit

**Status: completed for the available source snapshot. Git versioning is now enabled at the maintainer's request.**

- Inventory active source, launchers, configuration, docs, historical backups, ignored runtime payloads, licenses and available test tools.
- Record confirmed risks separately from future architecture recommendations in `ARCHITECTURE_AUDIT.md` and `SECURITY_MODEL.md`.
- Establish compatibility limits in `COMPATIBILITY_MATRIX.md` and stage an ordered implementation plan here.
- Continue development from the imported 2.2.0 source in the Git checkout, using feature branches and reviewable commits. Preserve the OneDrive snapshot and its verified backups; do not merge or publish production releases without the required review and maintainer approval.

## Phase B — Stabilization (in progress; current source imported into Git)

1. **Fail closed on reparse paths.** An isolated snapshot validates each existing path component during discovery and immediately before deletion, and refuses linked or uninspectable paths. The junction regression test passed under Pester 3.4.0; review the remaining time-of-check/time-of-use window before declaring this complete.
2. **Make ClamAV installs and engine updates verifiable and recoverable.** The snapshot requires HTTPS and rejects missing, malformed or mismatched SHA-256 metadata before extraction. A direct ZIP URL can supply `-ExpectedSha256`. Initial installation now stages beside the target, retains existing signature files, restores the prior folder if configuration commit fails, and keeps a replaced folder as a recovery backup. Synthetic URL, digest, rollback and backup tests pass under Pester 3.4.0; vendor download and execution were not tested.
3. **Keep diagnostics aligned with supported packaging.** The snapshot corrects `-SelfTest` so a missing optional portable runtime or ClamAV engine is reported as optional. The isolated source-only package regression test passed under Pester 3.4.0.
4. **Check localization completeness.** `-SelfTest` now verifies every translation key has a non-empty value for all six supported languages; the source-package regression test asserts the diagnostic.
5. **Add test/static-analysis gates.** The snapshot has a Windows CI workflow pinned to Pester 5.7.1 and PSScriptAnalyzer 1.24.0. Local PSScriptAnalyzer 1.24.0 review on 50 files found zero errors, 228 warnings and 41 informational findings; warning categories and triage are recorded in `STATIC_ANALYSIS_BASELINE.md`. The 29-case local Pester 3 suite passes; Pester 5 and GitHub Actions have not run. First CI must avoid real system changes and upload no user logs.
6. **Review backups and rollback.** Verify integrity before mutation, preserve existing data on partial failure, write Antivirus configuration atomically, test restore in isolated user data/registry fixtures, and clearly label operations that cannot be rolled back.

**Phase B exit gate:** high-risk path tests pass; archive integrity fails closed; static analysis findings are reviewed; no live user/system state is changed by tests.

**Progress on 2026-11-16:** the snapshot corrects optional-component handling in `-SelfTest`, requires HTTPS and SHA-256 verification for ClamAV installation and engine updates, makes initial installation transactional, writes Antivirus configuration atomically, validates privacy restore backups against a fixed allowlist, and adds regression coverage. Phase C has extracted tested Core services for localization, app settings, logging, native processes, permissions, operation results and AI contracts. The read-only SystemSnapshot is now connected to home-menu option 9 and was exercised against live Windows CIM data. The Pester suite passes 34 tests; the local Pester runner fails closed on test errors. Windows PowerShell 5.1 parsed 58 active PowerShell files with zero syntax errors. PSScriptAnalyzer 1.24.0 reported zero errors, 230 warnings and 44 informational findings across 58 first-party files. The quarantine restore menu provides localized validation. Reparse-path protection retains a documented time-of-check/time-of-use limitation. The untouched OneDrive source and its verified `Backup-2.1.3` remain unchanged.

## Phase C — Modularization (in progress)

- The 230 existing UI text keys and five new operation-status labels now live in six keyed UTF-8 JSON locale files. `Core/Localization.psm1` loads them, validates resource types and falls back to German for missing or unsupported translations. The existing `T` interface remains as a compatibility wrapper.
- Language settings now use `Core/AppSettings.psm1`, which validates saved language codes and atomically replaces the settings file after read-back validation.
- Native process execution, current-token administrator checks and versioned operation results now have tested Core modules; settings, localization and logging have focused modules too. Continue with cross-module interfaces.
- Keep legacy command-line behavior stable while introducing module boundaries.
- Add runtime language-switch tests, translation-schema versioning, localization tooling and launcher compatibility tests.

## Phase D — Local AI feasibility and implementation

- The audit snapshot now has `Core/AiContracts.psm1`, which validates explicitly provided, bounded system facts and accepts only a strict advisory-response schema. Its four local tests pass; this is a data boundary, not an implemented AI feature.
- Model comparison, redistribution-license verification and benchmarks remain blocked: the research search service timed out. No model weights or inference runtime have been selected or installed.

- Compare at least three compact Qwen Instruct GGUF candidates and any credible alternative using the same German/English system-report prompts and CPU/RAM benchmarks.
- Verify redistribution and runtime licenses from primary sources before selecting or packaging any model.
- Prototype `llama.cpp` CPU inference behind a typed analysis-only interface. No generated command may be executable; recommendations remain separate from confirmed, rule-based actions.
- Do not add a model or runtime until cancellability, memory limits, process lifecycle, offline behavior and package integrity tests pass.
- Treat “Complete” and “Standard” packages as separate deliverables only after size and offline installation benchmarks exist.

## Phase E — System and security functions

- A read-only Core collector converts Windows CIM data into Windows, CPU, memory and fixed-drive metrics. It is reachable from the terminal home menu; synthetic tests and a live CIM query passed. Full interactive console rendering still needs a real-console check.
- Build on measured, supported Windows APIs for dashboard, storage analysis, Defender status and Windows repair guidance.
- Extend uninstall attribution using product IDs, publisher, install path and shared-component evidence. Unknown ownership must remain non-deletable by default.
- Add a central operation journal and recovery center only for resources that can be restored reliably. Do not promise rollback for external application uninstallers.

## Phase F — UI/UX evaluation

- Keep the terminal UI until a prototype demonstrates measurable gains in usability, accessibility, responsiveness and packaging.
- If justified, compare a Windows-native UI against the current console interface without removing the latter until feature parity and regression testing are demonstrated.

## Phase G — Quality and compatibility

- Run Pester, PSScriptAnalyzer, security tests, offline tests, cancellation tests, Windows 10/11 tests and performance benchmarks on isolated runners/VMs.
- Establish cold-start, program-list, trace-scan, idle-memory and AI latency baselines before setting numeric targets.
- Verify x64 packaging, install/uninstall behavior, hashes and third-party license notices.

## Phase H — Release candidate

- Produce a versioned, reproducible candidate with release notes, hashes, compatibility statement and known limitations.
- Keep signing status honest; sign only if a valid trusted signing setup is available.
- Do not publish a production release until tests pass and Salim explicitly approves.

## Current blockers and decisions

- **Version control:** the earlier blocker is resolved. The verified 2.2.0 snapshot is now in the existing Git checkout on a feature branch; `main` and prior history are preserved. GitHub Actions remain unverified until a remote workflow run is available. Local commits are not evidence of a GitHub publication.
- **Pester 5:** the local suite currently passes with Pester 3.4.0. `Save-Module` failed while bootstrapping NuGet through the installed PowerShellGet 1.0.0.1, so Pester 5.7.1 was not installed and the workflow remains unverified locally. The project tools folder contains no Pester 5.7.1 module.
- **Interactive menu verification:** the headless test host cannot set a console cursor position, so an end-to-end menu launch exited before the first prompt. The live collector and synthetic tests pass; verify option 9 in a normal Windows Terminal before calling the UI path release-ready.
- **Static-analysis warnings:** the current full scan has zero errors but 230 warnings and 44 informational findings. The warning set is documented; it is not a release-quality claim that every warning has been individually resolved.
- **AI model choice:** intentionally deferred; no reproducible benchmark or redistribution-license check has been performed.
- **Local runtime availability:** this computer has no detected `llama-cli`, `llama-server`, `ollama` command or GGUF model in the project. The license search backend timed out, so a model cannot yet be selected or redistributed responsibly.
- **UI migration:** deferred pending measurable evidence.
- **Release:** not authorized until a validated release candidate is presented and approved.
