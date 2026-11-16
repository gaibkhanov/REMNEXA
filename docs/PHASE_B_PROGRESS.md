# Phase B progress

**Date:** 2026-11-16\
**State:** in progress in an isolated source snapshot; Git versioning is intentionally not used, and nothing has been pushed or released.

## Latest checkpoint — 2026-11-16

**Implemented:** Added a localized, on-demand read-only system overview to home-menu option 9 (Windows version/build, CPU load, memory use and fixed-drive capacity). Added a local Pester runner that supports Pester 3/5 and fails closed on test failures, and strengthened the PSScriptAnalyzer runner so it includes first-party tools and exits unsuccessfully when analyzer errors exist. Updated the README, changelog, compatibility notes and contributor instructions.

**Verified:** 34 Pester 3.4.0 tests passed under PowerShell 7.6.9; the application self-test passed all 12 checks; all 249 localization keys were present in six languages; Windows PowerShell 5.1 parsed 58 first-party PowerShell files with zero syntax errors; PSScriptAnalyzer 1.24.0 found zero errors, 230 warnings and 44 informational findings across 58 files. The read-only CIM collector returned live Windows, CPU, memory and fixed-drive data.

**Showstoppers skipped and recorded:** No local AI runtime/model is available and the model redistribution license/benchmark decision is unverified; therefore no AI package or model was added. The reparse-path guard still has a time-of-check/time-of-use window, so destructive cleanup security is not declared complete. Pester 5.7.1 and GitHub Actions were not run. An unmocked headless menu launch cannot get past `Clear-Host` because there is no console cursor handle; an isolated mock-host integration run did reach option 9, return to the menu and exit cleanly. Visual rendering in a normal Windows Terminal remains unverified. The full GUI, installer, Windows 10/11 matrix, package/release validation and production release remain unfinished.

**Version/state:** The entry point still reports version 2.1.3. This is an optimized development snapshot, not a finished or published REMNEXA 3.0.0. The active OneDrive copy remains untouched. The pre-change development checkpoint was `Backup-3.0.0-dev.2-2026-11-16`; a post-change checkpoint is created only after this report and the final tests are complete.

## Implemented in this snapshot

- `-SelfTest` now treats `runtime\pwsh.exe` and the installed ClamAV engine as optional. Required source files and module loading remain checked.
- `-SelfTest` now verifies that every in-code translation key has a non-empty entry for each supported language; the source-package regression test asserts this check.
- ClamAV initial installation and engine updates accept only an absolute HTTPS URL and require a valid matching SHA-256 digest before extraction. A direct ZIP URL can provide `-ExpectedSha256`; invalid, missing or mismatched values abort.
- Initial ClamAV installation now stages files beside the target and switches the target only after package preparation. A failed configuration commit restores the previous target. Existing signature files are carried into the staged package, and a replaced target is retained as a recovery backup.
- Antivirus configuration updates now write UTF-8 to a same-directory temporary file and replace the prior JSON atomically.
- Privacy restore now validates every saved registry path/name against the fixed allowlist and checks the full snapshot before writing. Unsupported paths, incomplete data, invalid registry kinds and malformed values are rejected before any restore mutation.
- Nine core Pester regression cases cover source-only self-test behavior, translation completeness, digest validation, HTTPS URL validation, trusted install/update asset metadata, linked-path rejection, installation rollback, retained backups, atomic config updates and privacy-backup validation. Eleven added cases cover localization, app settings, logging, native-process behavior and administrator-token checks.
- `.github/workflows/quality.yml` runs Pester 5.7.1 and an error-level PSScriptAnalyzer gate on Windows.
- The README contains the PayPal donation link supplied by the maintainer and links the audit documentation.

## Verification

- The expanded regression suite passed under PowerShell 7.6.9 with the locally available Pester 3.4.0: **31 passed, 0 failed**. Fixtures use temporary folders; `LOCALAPPDATA` is redirected for the source-package and settings tests.
- A fresh Windows PowerShell 5.1 parser pass reported **0 syntax errors across 50 `.ps1`, `.psm1` and `.psd1` files**. The ClamAV, localization, app-settings, logging, permissions, native-process, operation-results, AI-contract, system-snapshot and backup-validation modules were exercised by passing Pester tests under PowerShell 7.6.9.
- PSScriptAnalyzer 1.24.0 analyzed 50 active files: **zero errors, 228 warnings and 41 informational findings**. The warning baseline and triage are in `STATIC_ANALYSIS_BASELINE.md`; Pester 5 and GitHub Actions have not run locally.
- The application's `-SelfTest` completed with **12 of 12 checks passed**, including the six-language resources, required Core manifests and optional-runtime behavior. Inventory checks read the local startup entries and Windows service list.
- The original OneDrive `REMNEXA.ps1` SHA-256 remains `25AF6F5F276AD2E9001B4FE059C39E31CF4F7CF5C0A44888B88AEBEE529F5146`, identical to the hash captured before audit changes. A separate `Backup-2.1.3` folder was added beside it; its 898 source files were SHA-256 verified.
- For review without Git, a file-hash comparison of active project files (excluding historical backups, runtime/vendor payloads and developer tools) found **45 added files, 8 modified files and no original active files missing**. Modified files are `Antivirus/Private/10-NativeProcess.ps1`, `Antivirus/Private/20-Installation.ps1`, `Antivirus/Public/Initialize-ClamAV.ps1`, `Antivirus/Public/Set-AVConfig.ps1`, `Antivirus/Public/Update-ClamAVEngine.ps1`, `Antivirus/README.md`, `README.md` and `REMNEXA.ps1`.

## Open blockers and risks

- Git branches and commits are intentionally omitted per the maintainer's instruction. `REMNEXA-3.0-audit` remains the isolated working copy; no development source files were copied into the active OneDrive project.
- The snapshot checks each existing path component and rejects linked or uninspectable paths during discovery and just before deletion. The junction regression passed; review the remaining time-of-check/time-of-use window before calling this complete.
- The ClamAV transaction tests use synthetic local package fixtures; they do not download or execute a vendor binary. A replaced target remains as a sibling backup and currently has no in-app cleanup/restore UI.
- The transaction covers package staging, target replacement and configuration commit. Signature database download/update failures after installation are not rolled back and require a retry.
- Privacy-backup validation is tested as a pure data check; it does not perform or validate a real elevated registry restore. The snapshot has no cryptographic signature for privacy backup contents.
- The analyzer reported no errors, but its warning set still needs item-by-item reduction. Windows 10/11 runtime coverage, installer tests, offline AI behavior, model licensing/benchmarks and release artifacts remain unverified or not implemented.
- No production release has been created or published.
- The pinned Pester 5.7.1 workflow was not run locally: installed PowerShellGet 1.0.0.1 failed while bootstrapping NuGet for `Save-Module`. The existing Pester 3.4.0 suite remains green, and no Pester 5.7.1 module is present in the project tools folder.

## Phase C progress

- Extracted 230 existing keys into six UTF-8 JSON resources and added localized operation-status and menu labels (236 keys total). `Core/Localization.psm1` validates resource data and provides German fallback; the user-facing `T` function retains its current call shape.

## No-Git checkpoint update — 2026-11-16

- Created `Backup-2.1.3` beside the original project. It contains 898 active source files (1,309,979,961 bytes); the copy operation compared SHA-256 for every file and wrote `BACKUP-MANIFEST.csv` plus `BACKUP-INFO.txt`. Historical `Backup-*` folders were excluded to avoid nesting old snapshots.
- Added `tools/New-RemnexaBackup.ps1` and `docs/BACKUP_AND_CHECKPOINTS.md` so later checkpoints use the same no-overwrite, staged-copy and per-file SHA-256 process.
- Added two backup-tool regression tests. Full Pester 3.4.0 suite: **31 passed, 0 failed**. Windows PowerShell 5.1 parser: **54 active PowerShell files, 0 syntax errors**.
- No local `llama-cli`, `llama-server` or `ollama` command and no GGUF model are available in the project. Official model/runtime license search timed out again, so no model or runtime has been bundled or selected.
- The quarantine restore prompt previously advertised `0` as return, but an invalid number silently fell through. It now accepts `0`, validates choices against the displayed entry count and explains the valid range in all six languages. This is covered by two menu-choice tests; localized resources now contain 236 keys.
- Moved language-setting reads and writes into `Core/AppSettings.psm1`; writes are schema-checked, read back and atomically replaced.
- Six tests cover locale completeness/fallback, app-settings replacement/validation and structured logging. Four test native process arguments, stdout/stderr capture, missing executables and the Antivirus adapter; one verifies the Windows administrator-token check; three cover the operation-result schema and validation. The full suite has 23 passing tests under PowerShell 7.6.9 with Pester 3.4.0.
- Structured logging is in `Core/Logging.psm1`; the existing global `Write-LogEntry` function remains as a compatibility wrapper. Antivirus retains `Invoke-AVNativeProcess` through an adapter to `Core/NativeProcess.psm1`.
- `Core/OperationResults.psm1` now validates a versioned result record for completed, partial, dry-run, cancelled and failed operations. The uninstall dispatcher still returns its legacy Boolean while the interactive summary exposes a localized result state.
- `Core/AiContracts.psm1` accepts only explicitly supplied, allowlisted facts with size/range limits and parses advisory responses against a strict schema that rejects command fields. Four Pester cases cover data bounds, unknown facts, malformed output and inert recommendations. No model or inference runtime is included.
- Phase E groundwork: `Core/SystemSnapshot.psm1` can read Windows/CIM health data on demand and computes CPU, memory and fixed-drive metrics. Two tests exercise only synthetic records; no UI page or automatic background scan uses this module yet.
- Remaining Phase C work includes additional cross-module contracts and checking the pinned Pester 5 workflow on a suitable Windows CI runner.
