# Changelog

All notable changes to REMNEXA are documented here. This file follows the Keep a Changelog format; released versions remain unchanged.

## [2.2.0] - 2026-11-16 (local build; not published)

### Added

- Action-specific administrator explanations before every REMNEXA RunAs request, translated into all six languages. Users can read why the selected area needs access, then press Enter to open the Windows Yes/No prompt, choose 0 to return or X to close the application.
- A localized `[X]` exit option at application input prompts without an existing zero-to-exit choice, including submenus, searches, result screens and confirmations. `x` or `exit` closes directly and attempts to save the session details without returning through the home menu.
- Isolated child-process exit tests covering nested menus, cleanup, log preservation/failure, normal path input and explicit quarantine confirmation.
- Initial architecture audit, security model, compatibility matrix and REMNEXA 3.0 roadmap.
- Self-test validation that every translation key contains non-empty text for all six supported languages.
- Six keyed UTF-8 locale resources and a localization module with German fallback; legacy `T` calls remain compatible.
- Pester coverage for locale completeness, fallback behavior and malformed non-fallback resources.
- A core app-settings module for validated language loading and atomic settings replacement.
- A structured logging module behind the legacy `Write-LogEntry` compatibility wrapper.
- A shared native-process service with the existing Antivirus process API preserved through an adapter, plus an isolated administrator-token check.
- A versioned operation-result schema for completion, partial completion, dry runs, cancellation and failures; interactive summaries show localized outcome labels.
- A local-AI input/output contract that bounds explicit system facts and accepts only advisory fields; command fields and unrecognized properties are rejected.
- An on-demand, read-only SystemSnapshot module that converts Windows CIM records into CPU, memory and fixed-drive metrics; no background inventory was added.
- A localized main-menu system overview for Windows version/build, CPU load, memory and local fixed drives; data is collected only when selected.
- A local Pester runner that supports Pester 3 and 5 and returns a nonzero exit code for failed or invalid test results.
- A static-analysis runner that includes first-party tools, reports severity totals and fails when PSScriptAnalyzer finds errors.
- Isolated Pester regression tests for ClamAV URL and digest validation, transactional installation, atomic configuration writes, linked-path rejection and privacy-backup validation.
- Windows GitHub Actions workflow for Pester and an error-level PSScriptAnalyzer gate.
- Static-analysis baseline documenting the existing warning set and zero analyzer errors.
- PayPal donation page link in the README.

### Fixed

- Program, startup and service lists offer Next/Previous only when those pages exist, including after filtering and resuming a list. Out-of-range page commands show an explanation beside the available choices and do not move the selection.
- All eleven zero-to-exit prompts omit the redundant X label. X remains visible where zero means Back or is ordinary text input; x/exit remain compatible quiet aliases when zero already exits.
- Windows-managed WindowsApps package paths (including secondary-drive roots) remain visible as intentionally retained findings and are excluded from generic deletion. No ownership or ACL takeover is attempted; ordinary access failures retain their concrete error details.
- Removal reaches 100% and saves its result/history before offering the optional service/security snapshot. The optional snapshot has a separate log linked to the removal, and failures do not relabel a completed removal as failed.
- Demand-start stopped services are explained without false failures. Antivirus status considers SecurityCenter registration, reports Defender only once, and distinguishes registered third-party software from confirmed real-time protection.
- Restore-point creation is confirmed by a unique description returned by Windows; skipped frequency-limited creation no longer reports a new backup.
- Registry deletion exit code 1 no longer counts as success. Child entries are covered only by successfully removed parent keys, with separate coverage counts. Final remaining traces and intentionally skipped paths are recorded in the removal log.
- General administrator notices no longer incorrectly describe every operation as removal; cancellation and NoElevation messages cover the selected action.
- Quarantine restore now uses the application's explicit warning with the shared exit option; the module's interactive warning is bypassed only after the user explicitly approves the in-app warning. Hash validation and no-overwrite checks remain in the module.
- Opening the Antivirus workspace now requests Windows administrator approval through the existing RunAs flow. The elevated process opens Antivirus directly, cancellation returns safely, and an already elevated process is reused.
- File-trace collection and cleanup now reject reparse points or path components that cannot be inspected.
- The self-test no longer treats the optional portable PowerShell runtime or optional ClamAV engine as mandatory.
- ClamAV archive installation now requires HTTPS and fails closed when SHA-256 metadata is missing, malformed or mismatched. Direct ZIP installs can provide `-ExpectedSha256`.
- ClamAV installation preserves existing signatures and restores the previous engine if the configuration commit fails; antivirus configuration writes use an atomic replacement.
- Privacy restore data is checked against the fixed registry allowlist and schema before restore writes begin.
- The application language setting is validated and saved through a read-back-verified atomic replacement.

### Open

- Reparse-point validation narrows but does not eliminate the race between checking a path and later filesystem access.
- ClamAV signature-update failure after engine installation is not transactionally rolled back.
- No release candidate has been built or published.
