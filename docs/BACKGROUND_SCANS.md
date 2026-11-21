[English](BACKGROUND_SCANS.md) | [Deutsch](BACKGROUND_SCANS.de.md)

> Historical rc.7 report. The current [rc.8 scan](INDEPENDENT_SCANS.md) offers continue/cancel/back on exit and can run independently.

# Background antivirus scans — 2.2.0-rc.7

Development candidate on `feature/antivirus-background-scans`; no stable release is published by this change. Based on the [rc.6 worker fixes](RELEASE_2.2.0_RC6.md).

## Using the scan manager

Start a quick or custom scan from the existing Antivirus menu. The request returns to the menu while scanning continues in a separate PowerShell runspace. Return to the main menu and use other REMNEXA features.

- Enter `/scan` at a normal REMNEXA input prompt, or choose **B** in the Antivirus menu.
- The scan manager refreshes every two seconds in an interactive console. Other hosts provide a manual control prompt.
- **P** requests a pause, **R** resumes, **C** cancels, and **0** returns to the previous menu while the scan continues.
- **D** opens a static snapshot of findings/issues, so refresh does not interrupt reading. **0** returns to the live view.
- **X** exits REMNEXA. Exiting cancels and cleans up the owned scan; this is not a detached service that survives application exit.

The manager displays phase, performance mode, acknowledged files, findings, elapsed time and average files/active second. The average includes preparation/loading and excludes completed pause time; it is not an instantaneous scan rate. Percentages appear only after inventory has established a total. Acknowledging all inventoried files does not imply successful complete coverage: exclusions, inaccessible files and engine limits still apply.

The latest 20 finding/error lines appear in the live view. A snapshot retains up to 1,000 lines and reports any omitted lines. Existing final results and local scan logging remain separate. Treat scan output and filenames as untrusted; control characters are stripped from console display. Findings never trigger automatic quarantine in this workflow.

## Lifecycle and concurrency

The main menu and scan use separate session states and shared synchronized in-memory telemetry. The background scan never reads console keys or handles the main console's cancellation event. It uses the existing inventory, engine selection, signature policy, output parser, coverage checks, update exclusion and quarantine implementation.

Only one background scan is accepted at a time. The installation mutex also rejects competing scans and signature/engine writes while scanning or paused. Read-only tools remain available; filesystem changes made by other features may make an ongoing scan partial. An optional post-uninstall scan reports the busy installation instead of starting another engine.

Pausing is applied at a scan checkpoint, normally within a heartbeat, not an instantaneous UI action. Preparation/inventory pauses cooperatively. For `clamscan` and the private worker, documented Windows thread suspend/resume APIs stop only the scanner PID supplied by its launch/heartbeat path. Host suspension is refused. Successful suspends are balanced on resume/cancellation; failure rolls back and fails the scan rather than claiming a successful pause. The scanner keeps its RAM and may hold file handles while paused. REMNEXA's outer scan/startup deadlines exclude pause time; native per-file engine limits are unchanged and may still produce an incomplete result after a long pause.

Cancellation preserves previously observed findings and marks coverage incomplete. An outcome is exposed as finished only after pipeline results and worker cleanup have been collected. Shutdown requests cancellation and waits up to 15 seconds; an unconfirmed cleanup is reported. No Windows service, scheduled task, listener, security exclusion or automatic update is added.

## Module API

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Start-ClamAVBackgroundScan -ScanType Quick -Language en
Get-ClamAVBackgroundScan
Set-ClamAVBackgroundScan -Action Pause
Set-ClamAVBackgroundScan -Action Resume
Set-ClamAVBackgroundScan -Action Cancel
Stop-ClamAVBackgroundScan
Get-ClamAVBackgroundScan -IncludeResults
```

Synchronous `Invoke-ClamAVScan` and `Invoke-ClamAVTargetedScan` remain available for scripts and ordered removal workflows. Background requests do not automatically update components or quarantine findings. The scan runspace is retained between requests so the native engine can be reused without reloading all signatures. The owned engine exits after its existing configured idle timeout (60 seconds by default). Before foreground scans or updates, the idle background engine/runspace is released without discarding completed results. Exit/module removal also releases it. No service or independent persistent application is installed.

## Candidate package

From a clean checkout of the candidate branch, build and verify a source ZIP with PowerShell 7.5 or newer:

```powershell
$package = ./tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.7'
./tools/Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

The ZIP and SHA-256 sidecar are written under `dist/`. This is a source candidate, without bundled PowerShell, ClamAV binaries or signature databases, and not an installer or stable release. Existing runtime/setup requirements still apply.

## Verification

`tests/BackgroundScan.Tests.ps1` exercises a genuinely asynchronous runspace and harmless external scanner fixture: caller responsiveness, live findings, actual process pause/resume, cancellation while paused, evidence preservation, installation exclusion, failures, bounded preview and six-language messages. `tests/BackgroundScanUI.Tests.ps1` checks background launch, `/scan` return navigation and state-sensitive controls. Existing synchronous scan and update-prompt tests remain applicable.

Final local regression: **191 passed, 0 failed, 0 skipped** with Pester 5.7.1 and PowerShell 7.6.9. Static analysis found no errors in the changed PowerShell code. Remote CI for this candidate has not been confirmed because the public GitHub API status request was rate limited.

`tools/Test-ClamAVBackgroundScan.ps1` was also run with installed ClamAV 1.5.4: **2,501 harmless files and one custom hash-signature finding per backend**, using the real CLI and restricted private native worker. Both paused without acknowledging further files, resumed with complete fixture coverage, and cancelled a second scan from the paused state. No automatic quarantine occurred. Installed signature files and personal directories were not changed or scanned. The isolated test module changes only readiness reporting to accept its harmless HDB database; all scanner/process code is production code.

The native test also verifies reuse of the same engine PID for the next request and release of a completed scan's cached engine before foreground access. Background-start return times are recorded with unequal cold setup; these are responsiveness observations, not a comparative engine performance benchmark. See [sanitized results](benchmarks/rc7-background-scan.json).

Validation is on the available Windows 11 SSD host with 16 GB RAM. These checks do not establish Windows 10, HDD, actual 8 GB VM, malware-detection effectiveness or long-pause behavior for every file format. The [existing native engine and licensing boundaries](PRIVATE_SCAN_ENGINE.md) remain in force.
