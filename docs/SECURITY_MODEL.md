# REMNEXA security model

**Scope:** current 2.1.3 implementation and target constraints for 3.0. This document describes observed controls and gaps; it is not a claim of certification or a complete penetration test.

## Security goals

1. Inspect only the resources needed for the selected operation.
2. Show the user what will change and require confirmation for risky operations.
3. Fail closed when target ownership, path identity, permissions, or integrity cannot be established.
4. Run with least privilege and request elevation only for concrete operations.
5. Treat downloaded binaries, local models, scan results and future AI output as untrusted input.
6. Keep logs local and avoid sending system inventory to a service.

## Trust boundaries and data

| Boundary | Data crossing it | Required treatment |
|---|---|---|
| User selection → operation engine | Program names, registry paths, app package IDs, file paths | Validate typed identifiers; show resolved target and scope before mutation. |
| File scanner → cleanup | Candidate paths, publisher/product evidence, shared-file relationships | Revalidate ownership, canonical path and every reparse-point ancestor immediately before deletion. Unknown ownership means no deletion. |
| Registry/service/task inventory → removal | Registry keys/values, services and scheduled task names | Protect Windows/security components; back up mutable state where possible; keep preview and explicit confirmation. |
| Remote release service → ClamAV installer | Release metadata and archive bytes | Require HTTPS plus a trusted, mandatory SHA-256 digest; stage, validate and roll back before replacing an existing engine. |
| System → local logs/history | Installed program names, paths, scan results, timestamps and operation outcomes | Keep local by default; document sensitive fields; restrict permissions; make cleanup explicit. |
| Future local AI → user advice | Explicitly supplied system reports and untrusted text | No direct filesystem/registry/process access; no executable command output; validate structured inputs/outputs; all mutations remain rule-based and user-confirmed. |

## Existing controls observed

- `#requires -Version 7.5`, `Set-StrictMode`, and stop-on-error behavior are set in the main script.
- Elevation uses `Start-Process -Verb RunAs` only when an operation needs it; interactive removal defers that prompt until after program selection.
- The app has protected component/service checks, removal previews, confirmations and a dry-run mode.
- `Add-FileTraceIfSafe` rejects a final path component marked as a reparse point. Registry traces also have protected-path checks.
- A system restore point is attempted before uninstall. If it fails, noninteractive removal stops and interactive removal asks the user whether to continue.
- Startup and privacy settings have application-managed backup/history paths. ClamAV quarantine records a SHA-256 hash and restore checks the hash and refuses to overwrite an existing target.
- ClamAV scans are on demand; findings are reported and are not automatically quarantined or deleted.

## Confirmed baseline gaps requiring Phase B work

The findings below describe the starting 2.1.3 source before the isolated Phase B changes. The current audit snapshot has partial mitigations described in the status section at the end of this document; those changes have not been copied to the OneDrive source or published.

### File path and reparse-point handling

The final candidate is checked for `ReparsePoint` when it is discovered, but ancestor components are not checked and the path is not revalidated for links immediately before recursive deletion. A junction/symlink in a parent could redirect a path outside the intended installation tree. Phase B must validate every component at discovery and mutation time, block if any component is linked or cannot be inspected, and test using temporary directories and junctions.

### Download integrity

The baseline ClamAV setup and engine update compute SHA-256 only when release metadata provides a digest in the expected format. Missing or malformed digest metadata does not abort those downloads, and the baseline engine-update path does not require HTTPS for a configured direct ZIP URL. The 3.0 policy is mandatory verification against a trusted digest or signature, followed by staging and rollback; no archive should be extracted before verification succeeds.

### Recovery boundaries

Restore points and app backups have different guarantees. An application uninstall may remove shared data or invoke vendor logic that cannot be reversed. The UI and docs must state this before confirmation. Tests must use isolated fixtures; do not simulate cleanup against real user files or the live registry.

## Required controls for the future AI module

- Run a pinned local inference process with an explicit memory cap, cancellation and bounded lifetime.
- Provide only an allowlisted, typed snapshot of system data to the model.
- Never expose a shell, arbitrary process runner, deletion API, registry writer or elevation path to model output.
- Parse model responses into a strict schema; render plain explanatory recommendations and flag uncertainty.
- Require the existing deterministic operation flow and a separate user confirmation for every system change.
- Test prompt injection in analyzed text, malformed output, timeouts, cancellation, offline mode and process cleanup.

## Logging and privacy

Current logs are local under `%LOCALAPPDATA%\REMNEXA` and can contain system-specific names and paths. No telemetry or cloud AI implementation was found in active source. Future diagnostics must redact secrets and avoid uploading logs by default. Log export, retention and deletion behavior should be documented before adding a report-sharing feature.

## Security release gate

Do not ship 3.0 until reparse-point, path traversal, permissions, partial failure, backup integrity, malicious download, offline AI and installer tests pass in isolated Windows environments. A source parse or self-test alone does not satisfy this gate.

The isolated snapshot now checks each existing path component for reparse points at trace discovery and again before deletion. It blocks linked and uninspectable paths. This narrows the gap but cannot eliminate a race between path inspection and a later filesystem operation; that residual risk must be reviewed before the control is called complete.

## Phase B status in the isolated snapshot

- ClamAV installation and engine-update archives require an absolute HTTPS URL and a valid matching SHA-256 digest. Direct ZIP URLs require `-ExpectedSha256` when release metadata does not supply a digest.
- Initial installation stages beside the target, preserves an existing signature database, and restores the prior target if the configuration commit fails. A successfully replaced target is kept as a sibling backup; no cleanup or restore UI exists yet.
- Antivirus configuration writes use a same-directory UTF-8 staging file and atomic replacement.
- Privacy restore validates the complete backup against the fixed registry path/name allowlist and supported value types before making changes. This blocks tampered JSON from redirecting elevated writes to unrelated registry locations.
- Thirty-four Pester 3.4.0 regression tests passed under PowerShell 7.6.9. Windows PowerShell 5.1 parsed 58 active `.ps1`, `.psm1` and `.psd1` files without syntax errors. Synthetic tests did not download or execute ClamAV or change the live registry. A read-only Windows CIM snapshot ran successfully. PSScriptAnalyzer 1.24.0 reported zero errors, 230 warnings and 44 informational findings; warnings remain tracked in `STATIC_ANALYSIS_BASELINE.md`.
- The isolated snapshot records uninstall outcomes in a versioned result schema with a generated operation ID, UTC timestamps, counts, log path and error text. Model-generated or external content remains outside this result contract and cannot trigger an action.
- The AI input/output contract limits facts to an explicit allowlist and rejects unknown fields such as generated commands. It is tested as a parser boundary only; no model output is currently wired into the application.
- The system-snapshot module makes read-only CIM queries only when called and is connected to home-menu option 9. Its calculations are covered with synthetic fixtures and a live CIM query; interactive rendering was not validated because the headless host lacks a console cursor handle.
