[English](INDEPENDENT_SCANS.md) | [Deutsch](INDEPENDENT_SCANS.de.md)

# Independent antivirus scans — 2.2.0-rc.8

Development candidate on `feature/independent-antivirus-session`; no stable release is published. This replaces the cancel-on-exit behavior of the [rc.7 background scan](BACKGROUND_SCANS.md).

## Using REMNEXA while scanning

Interactive Antivirus scans now start a separate PowerShell window. Continue using the main application, or open **B** in Antivirus or enter **/scan** at an application prompt to inspect status and findings. The scan window also accepts **P** (pause), **R** (resume) and **C** (cancel). Existing engine selection, resource limits, offline scanning, update exclusion and deliberate quarantine decisions remain in effect.

Exiting REMNEXA through its menus or **X** while a scan is active presents:

- **1 — Continue scanning and exit only REMNEXA.** A paused scan resumes before detaching. Keep the separate Antivirus window open.
- **2 — Cancel the scan and exit REMNEXA.** Wait for cancellation cleanup; existing findings remain available with incomplete coverage.
- **0 — Return to the application.** Leave the scan state unchanged.

Closing or forcibly terminating the main application outside these prompts cannot display a confirmation; the independent scan continues. Closing the separate **scan window** stops its owned scanner. Windows sign-out, shutdown and termination of the scan process are not covered by the continue option. No service or scheduled task is installed.

The scan window reports actual processed counts and available findings. Percentages require an inventoried total and do not guarantee complete coverage. Main-application and scan-window evidence displays sanitize control characters. Pausing retains scanner memory and may retain file handles. If the main process disappears while paused without choosing option 1, use **R** in the scan window to resume.

## Ownership, results and cleanup

The scan host owns the existing runspace and its scanner processes. The native worker retains its existing restricted token and Windows job limits; an owned CLI scanner also belongs to a kill-on-close job. Continuing a scan does not change Windows security settings or start an installed background service.

Control uses bounded, typed messages over a local current-user-only named pipe, restricted to the same elevation level. The client verifies the server PID. Requests cannot contain arbitrary shell commands. Session data is stored under the configured ClamAV log directory in `ScanSessions/scan-<random-id>/`, with access restricted to the current user and SYSTEM. This is not a security boundary against other programs already running as the same user.

Status is written atomically; readers allow atomic replacement. Cross-process previews retain at most 100 evidence lines, each at most 2,048 characters, and report omitted evidence. Full final results use a separate `results-<request-id>.json` file for each scan. Results may contain private file paths; do not upload them publicly without reviewing them. The latest session can be inspected from the scan manager after restarting REMNEXA with the same configuration. Automatic report deletion and a report browser are not implemented.

While attached, the host retains the existing native-engine cache between scans and releases completed sessions after 60 seconds of inactivity. After detaching, completion releases the scanner/cache and displays the report path for approximately 15 seconds before closing the window. Persisted reports remain. Updates and foreground scans release an idle host; an active scan still excludes conflicting writes.

## Module API

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Start-ClamAVBackgroundScan -ScanType Quick -Language en
Get-ClamAVBackgroundScan
Set-ClamAVBackgroundScan -Action Pause
Set-ClamAVBackgroundScan -Action Resume
Disconnect-ClamAVBackgroundScan -Resume # keep scanning after caller exit
# Explicit cancellation is separate:
Stop-ClamAVBackgroundScan
Get-ClamAVBackgroundScan -IncludeResults
```

Module removal detaches scans started by that module instead of cancelling them. Synchronous scan APIs remain synchronous. The independent host needs the existing PowerShell 7.5+ runtime and console-capable Windows session; it does not bundle ClamAV or signatures.

## Verification

`tests/IndependentScan.Tests.ps1` tests actual creator-process exit, pause/resume before detachment, implicit parent disappearance, explicit cancellation, retained evidence/reports, live remote controls, invalid commands/server PID and forced scan-host death with CLI child cleanup. `tests/ScanExitChoice.Tests.ps1` checks continue/cancel/back, failed cleanup, return to the original prompt and all six language resources. Existing runspace, native worker, update, quarantine and navigation tests remain.

Final local regression on PowerShell 7.6.9 and Pester 5.7.1: **204 passed, 0 failed, 0 skipped**. All 106 PowerShell files parse successfully and pass the PSScriptAnalyzer 1.24.0 error gate. Changed documentation links and private-path checks passed. No test scan hosts remain after the run.

`tools/Test-ClamAVIndependentScan.ps1` ran installed ClamAV 1.5.4 through both CLI and native private-worker backends against **2,501 harmless files and one custom hash-signature match per backend**. Each creator exited while the scan was still active, a paused scan resumed before detachment, and the scan completed with full fixture coverage and a saved report. No automatic quarantine, personal-directory scan or installed database modification occurred. See [sanitized results](benchmarks/rc8-independent-scan.json). This custom HDB fixture verifies lifecycle behavior, not malware-detection effectiveness or full-database performance.

Tests use the available Windows 11 SSD host with 16 GB RAM. Windows 10, a real 8 GB VM, HDD and malware-laboratory coverage remain unverified. Remote CI is a separate check; local test success does not establish a successful GitHub run. Existing [native-engine licensing boundaries](PRIVATE_SCAN_ENGINE.md) still apply.

From a clean candidate checkout, build and verify the source distribution:

```powershell
$package = ./tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.8'
./tools/Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

The source ZIP has no bundled runtime, ClamAV, signatures, installer or digital signature.
