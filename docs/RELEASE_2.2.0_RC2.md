[English](RELEASE_2.2.0_RC2.md) | [Deutsch](RELEASE_2.2.0_RC2.de.md)

# REMNEXA 2.2.0-rc.2: processing progress

**Status: development test candidate. Publication is postponed.** This extends [rc.1](RELEASE_2.2.0_RC1.md), preserving its fixes. It is not a stable release or REMNEXA 3.0.

## Implemented behavior

- A shared progress service shows the current operation, phase, elapsed time and current item. Known work uses processed/total counts; unknown work remains indeterminate rather than inventing a duration percentage.
- Cyan means running, yellow means waiting for input, a warning or cancellation, green means successful completion, and red means failure. Text labels also communicate the state. Incomplete measured work keeps its actual fraction when ending with a warning.
- Before console input, active work is labeled as waiting. Native-process observation refreshes elapsed time even while an engine or external command is silent. Interactive consoles redraw the native bar; hosts hiding native progress retain throttled colored status lines.
- Antivirus scans first inventory allowed targets. Directory roots that overlap are deduplicated, exclusions remain effective, links are skipped, and enumeration failures are counted. An explicit file list prevents ClamAV from recursively revisiting overlapping roots.
- During scanning, per-file ClamAV replies drive the count. Engine loading and result evaluation are separate phases. Missing replies, skipped paths and file errors do not produce an unqualified clean result. Unattributable detection exit codes fail safely. Findings remain visible and quarantine remains opt-in.
- Progress also covers application inventory, leftover search, Registry queries, removal, startup inventory/changes/restores, privacy changes/restores, restore-point requests, service/feature queries, log cleanup, source backups, the system overview, and Antivirus setup/update/status/quarantine operations.
- Existing fixed removal percentages now select phase text only. The overall removal stays indeterminate until completion; measurable child operations show their own counts. Result saving still finishes before the optional system assessment.
- All six interface languages contain the new progress resources. The application identifies itself as `2.2.0-rc.2`.

## What a scan percentage means

During the scan, the percentage is the proportion of inventoried files for which ClamAV reported a result. It is **not a remaining-time estimate**, byte count, or measurement of every object within an archive. One large file may take longer than many small files. A 100% file counter can still be followed by result evaluation or explicit quarantine work; the state stays running until the operation ends.

`FilesTotal`, `FilesReported`, `FilesUnconfirmed`, `InventorySkipped` and `CoverageComplete` record inventory/reply accounting. `CoverageComplete` does not override ClamAV's size, archive or format limits and does not guarantee full content inspection or absence of malware. Configured exclusions are intentional and are not counted as access failures. Enumeration skips are reported in aggregate; this change does not add a per-skipped-path audit manifest.

## Verification

Local validation used PowerShell 7.6.9 and the following checks:

| Check | Result |
| --- | --- |
| Pester 3.4.0 | 107 passed, 0 failed, 0 skipped. |
| Pester 5.7.1 | 107 passed, 0 failed, 0 skipped. |
| First-party PowerShell parsing | 73 files, 0 syntax errors. |
| PSScriptAnalyzer 1.24.0 error gate | 73 files, 0 errors; existing warning baseline is not claimed resolved. |
| Application self-test | 12 checks passed, version 2.2.0-rc.2. |
| Locale completeness | 318 nonempty keys in each of six languages. |
| Documentation | 39 files, 19 language pairs, 262 relative links and 30 PowerShell examples checked; no detected private-machine references. |

The real ClamAV 1.5.4 engine completed Quick scans against an isolated profile fixture: five harmless files inventoried, five replies, no inventory skips or unconfirmed files, no detections, approximately 16–25 seconds across two runs. A separate one-file custom scan also completed. Test-specific environment variables and configuration kept the scan in fixture directories. These are functional tests of the real engine and Quick workflow, **not a scan of a user's whole computer**. They did not update signatures, quarantine files or change installed security software.

Regression cases exercise partial replies, detection/error handling, excluded paths, linked directories, overlapping targets, progress invariants, input waiting, callback failure and native output limits. Existing navigation, permissions, backup and completion regressions remain part of the suite.

## Limits and deferred work

- Synchronous Windows/CIM calls, vendor installers and web downloads that expose no usable callbacks show a phase; they cannot provide a reliable percentage or continuous elapsed refresh during that single blocking call. A background-task UI is deferred.
- There is no universal new cancellation button or guaranteed control of detached/elevated third-party installers. Existing native timeouts remain enforced. Signature age, size/format limits and inaccessible content still affect scan usefulness.
- File inventory precedes the scan. Files can change afterward; this reduces duplication but does not eliminate filesystem races. Inventory and result accounting require disk/memory proportional to the selected workload.
- Source checkpoints preserve application code, not a locked full-machine image or vendor payloads. The prior source candidate is retained separately.
- No clean Windows VM matrix, live destructive uninstall/restore test, installer, embedded local AI, complete offline distribution or digital signature is delivered. Remote CI success is not implied by local results.

## Build and try

Use the `feature/2.2.0-progress` branch. From a clean committed checkout with Git and PowerShell 7.5+:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.2'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

The source archive excludes PowerShell, ClamAV binaries/signatures and AI models. Keep those supported optional components available separately. Launch `REMNEXA.cmd` from the updated application directory; restart an older running instance to load the changes. No existing release is replaced.
