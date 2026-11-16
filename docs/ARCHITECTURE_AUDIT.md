# REMNEXA architecture audit

**Audit date:** 2026-11-16\
**Baseline:** REMNEXA 2.1.3\
**Scope:** the active application source, PowerShell module, launchers, configuration, documentation and local test/build metadata. Historical `Backup-*` trees and ignored runtime payloads are recorded separately from the active source.

## Baseline and evidence

The local project at `C:\Users\gaibk\OneDrive\Software\REMNEXA` has no `.git` directory. A read-only comparison recorded earlier in this session found the main script byte-identical to GitHub `main` at commit `652360ebd8751be5f66b579e9e7d18854d8bb4de`; the public version was 2.1.3. The local folder therefore does not provide a verifiable local branch name, commit, or dirty-state report. Development remains in a separate source snapshot. The active OneDrive application files remain unchanged; an explicitly requested `Backup-2.1.3` directory was added beside them.

The active source contains a 3,615-line `REMNEXA.ps1`, a separate `Antivirus` PowerShell module, JSON configuration, five REMNEXA `.cmd` launchers, compatibility launchers, German user documentation, and a root README/license. The tree also contains versioned historical backups. The `.gitignore` excludes `runtime/`, `ClamAV/`, `Backup-*/`, logs, and JSONL files. The source inventory has no `tests/`, `.github/workflows/`, or existing `docs/` directory.

## Existing structure and behavior

| Area | Current implementation | Evidence |
|---|---|---|
| Entry point and UI | Interactive terminal UI in one large script; roughly 240 `Write-Host` calls. No WPF, WinForms, or other GUI framework references were found. | `REMNEXA.ps1`, function inventory and static search |
| Program removal | Registry uninstall entries and Appx packages are listed; user selection, protected-component checks, dry-run support, restore-point attempt, confirmation, uninstall invocation, residual search and run logs are handled in the main script. | `Get-InstalledPrograms`, `Find-AllTraces`, `Invoke-RemovalOperation`, `Remove-Traces` |
| Other system functions | Startup management with JSON backups/history, selected privacy registry changes with a backup, service listing, Windows maintenance tools, integrity checks and log cleanup. | `REMNEXA.ps1` functions around lines 1802–3020 |
| Antivirus | Optional ClamAV PowerShell module with setup, updates, scans, results, quarantine and restore. It is an on-demand second opinion, not real-time protection. | `Antivirus/Antivirus.psd1`, module files and `Antivirus/README.md` |
| Localization | Six languages are stored as translation arrays inside the main script: German, English, Spanish, French, Russian and Turkish. | `$script:LanguageCodes`, `$script:Texts` |
| Logging | JSON run/tool logs and JSONL history are stored under `%LOCALAPPDATA%\REMNEXA`. | `Save-RunLog`, `Save-ToolLog`, history functions |
| Startup and packaging | `.cmd` launchers select a portable `runtime\pwsh.exe` when present, else `pwsh.exe` on `PATH`. No installer or build pipeline is present in the source inventory. | `REMNEXA.cmd`, `.gitignore`, inventory |
| Tests and CI | No test suite, workflow, benchmark, or analyzer configuration exists. The machine has Pester 3.4.0; PSScriptAnalyzer was not found. | Local tool discovery and file inventory |

## Confirmed defects and risks

These are code-level findings. They have not been represented as a successful exploit or as a complete security review.

| Priority | Finding | Evidence and impact |
|---|---|---|
| High | Recursive cleanup does not validate every ancestor for a junction/symlink immediately before deletion. | `Add-FileTraceIfSafe` rejects a reparse point on the selected leaf (around line 1260), but `Remove-Traces` recursively removes a directory (around line 1709) after only `Test-ProtectedFilePath`; ancestor components are not rechecked. A linked parent could redirect a candidate outside its expected tree. This conflicts with the requested junction-attack protection and needs an isolated regression test before release. |
| High | Baseline ClamAV installation and engine-update paths could proceed without a valid digest; engine updates also accepted configured non-HTTPS ZIP URLs. | `Initialize-ClamAV` and `Update-ClamAVEngine` only checked a digest when metadata happened to match `sha256:<64 hex>`, and the update path did not enforce HTTPS. The isolated snapshot now requires HTTPS and a matching SHA-256 for both paths, accepts `-ExpectedSha256` for direct ZIP URLs, and stages initial installation with rollback. Synthetic regression tests pass; no vendor package was downloaded or executed. |
| High | Privacy restore trusted registry paths, names, types and values loaded from a mutable JSON backup. | `Restore-PrivacyProfile` previously applied each JSON snapshot directly. The privacy tool can request elevation, so a tampered backup could redirect writes outside the intended privacy settings. The isolated snapshot now validates the complete backup against the fixed path/name allowlist and accepted value types before performing any write. Tests cover a valid fixture and path, completeness and type tampering; no live registry was changed. |
| Medium | The self-test treats optional distribution components as mandatory. | `Invoke-RemnexaSelfTest` requires `runtime\pwsh.exe` and marks ClamAV failed whenever its engine is not installed (around lines 3297–3340), although `README.md` says the source distribution excludes the portable runtime and ClamAV engine. The first Phase B fix in this audit snapshot corrects this and adds a regression test. |
| Medium | A restore point is not a rollback for every operation. | Startup and privacy changes have app-managed restore data, while app uninstall and residual deletion cannot be reliably reversed. The UI must continue to describe these as distinct recovery levels. |
| Medium | The local source checkout cannot establish Git provenance. | There is no `.git` directory and Git was not found in standard install locations. `workspace_git` could not identify this folder as a workspace. No local branch or commit can be safely created or claimed from this machine state. |

## Confirmed safeguards

- PowerShell 7.5 or newer is required by the script and module manifests.
- Administrator elevation is deferred until an operation requires it; the removal path can use the current session without elevation where supported.
- Protected services/components and risky trace classes have explicit checks; removal previews and confirmations exist, and a dry-run option is exposed.
- Restore-point failure blocks a noninteractive uninstall and requires an explicit choice in interactive mode.
- ClamAV detections are not automatically deleted. Quarantine and restore are separate actions.
- The README states that REMNEXA is not a replacement for Microsoft Defender and documents the risk of optional personal-file cleanup.

## Dependency and license inventory

- Application runtime: PowerShell 7.5+ on Windows 10/11, as stated in the README and `#requires` directives.
- Optional scanner: official ClamAV Windows release fetched from Cisco Talos/GitHub when requested. The active source has a module; the Git-ignored local folder also contains scanner binaries and upstream license files, which are not part of the source snapshot.
- Application license: MIT. The ClamAV project and bundled third-party libraries retain separate license terms. A release that redistributes binaries or model weights needs a fresh component-by-component license review.
- No Python, Node.js, Docker, Ollama, cloud API or model dependency exists in the active source. No local AI runtime or model is implemented.

## Architecture decision

Keep PowerShell as the implementation baseline for Phase B. The existing console workflows and Windows integrations do not yet provide evidence that a full UI technology replacement would improve this application. First add safety tests and explicit module boundaries around the current code; evaluate a GUI migration only after startup, responsiveness, packaging, accessibility and maintenance costs can be measured against the console baseline.

## Implementation progress in the isolated snapshot

The working snapshot corrects the optional-component self-test, requires an absolute HTTPS URL and SHA-256 match for ClamAV installation and engine-update archives, stages initial installation with rollback, writes Antivirus configuration atomically, validates privacy restore backups against a fixed allowlist, and rejects linked or uninspectable path components. Phase C has extracted localization, settings, logging, native process execution, administrator checks and versioned operation results into focused Core modules while retaining compatibility wrappers. A bounded, advisory-only AI data contract remains disconnected from any model. The read-only system snapshot is now shown from home-menu option 9; synthetic tests and a live Windows CIM query passed, and an isolated mock-host run navigated through the menu entry and back. The quarantine restore prompt handles return and invalid entries in all supported languages. The local Pester suite passes **34 tests** under PowerShell 7.6.9; Windows PowerShell 5.1 parsed **58 active PowerShell files** without syntax errors; PSScriptAnalyzer 1.24.0 reported **0 errors, 230 warnings and 44 informational findings**. The test runner now returns a nonzero exit status for failed tests. The untouched OneDrive source and verified `Backup-2.1.3` remain unchanged. Visual behavior in a normal interactive Windows Terminal remains unverified. GitHub Actions has not run and nothing has been published.

## Audit limits

This was a static source review plus parser checks under Windows PowerShell 5.1 and targeted runtime tests under PowerShell 7.6.9. Static parsing succeeded for every active `.ps1`, `.psm1` and `.psd1` file, but that is not full application validation: the application requires PowerShell 7.5+. Live vendor-download verification, elevated privacy-restore integration tests, destructive-operation tests, installer tests, Windows-version matrix tests and a complete third-party license audit remain outstanding. Pester 5.7.1 and GitHub Actions have not run locally or remotely.
