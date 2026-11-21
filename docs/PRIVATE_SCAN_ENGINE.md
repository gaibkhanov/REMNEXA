[English](PRIVATE_SCAN_ENGINE.md) | [Deutsch](PRIVATE_SCAN_ENGINE.de.md)

# Private reusable scan engine — 2.2.0-rc.5

Historical rc.5 report. The [rc.6 follow-up](RELEASE_2.2.0_RC6.md) fixes elevated-parent launch and records expanded memory/archive validation and current CI status.

Development candidate on `feature/clamav-private-worker`; no stable release is published by this change. The [rc.4 scan report](CLAMAV_SCAN_PERFORMANCE.md) describes the earlier CLI backend and remains historical.

## What runs

REMNEXA can reuse **libclamav 1.5.4** in a separate Windows process. Signatures load once; subsequent scans reuse that compiled engine until idle shutdown, configuration/database changes, cancellation or an explicit stop. This is an alternative to `clamd`, not an authenticated configuration of stock `clamd`.

The shipped Windows daemon offers unauthenticated TCP. Placing a broker in front would leave that endpoint reachable. This implementation opens **no TCP listener and no public named pipe**. Three anonymous pipe handles (input, results, diagnostics) are explicitly inherited by the owned child. Scan requests contain a basename and file bytes; the worker does not receive original source paths or shell commands.

The frontend streams a disk-backed file inventory. A bounded window limits outstanding files and reordering; replies are returned to existing progress/result handling in inventory order. Duplicate, missing and malformed replies fail the scan. There is no clean-file cache: every selected file is submitted again on later scans. Size-limit and access warnings remain visible and do not become malware quarantine actions.

## Resource and lifecycle controls

| Mode | Maximum native threads | CPU hard cap | Process priority |
|---|---|---|---|
| Eco | 1 | 25% | Idle |
| Balanced | 2 | 50% | BelowNormal |
| Fast | 4 | 80% | Normal |

Threads are also capped by logical cores, available memory and measured load. Less than 4 GiB available or a resource-constrained profile selects one thread. Fast needs at least 6 GiB available for four threads. An existing engine's active scan window can be reduced when resources change. This does not resize native allocations already retained by the compiled engine.

The Windows Job Object enforces one child process, a 1.5–3 GiB process-commit limit and the CPU cap. These are ceilings, not reserved memory or performance promises. A cold start requires at least 2 GiB available; a warm engine can be used with at least 512 MiB available. One REMNEXA scan/update per configured installation remains enforced. Independent application instances can each retain their own engine between scans; low-memory preflight still applies.

The worker starts suspended, is assigned to its job, and is checked for elevation before running. A restricted, medium-integrity token is attempted. If restricted creation fails, a standard-user fallback is allowed only from a non-elevated parent; an elevated fallback is refused. The native worker independently refuses an administrator token. The restricted launch was exercised locally; the elevated-parent path still needs separate Windows validation.

The job is killed on owner exit, including an abrupt owner crash. X, Esc, Ctrl+C and cancellation tokens retain the existing incomplete-scan behavior. A 60-second default idle timeout releases the native engine. Updates stop only REMNEXA's own worker before changing engine/signature files. Foreign ClamAV processes, services and Windows security settings are left alone.

Native archive extraction uses a random directory restricted to the current account and SYSTEM. Normal shutdown removes that owned tree. If Windows refuses cleanup of an unexpected protected/reparse entry, it is retained; target permissions are not rewritten to force removal.

An abrupt owner crash can leave a private extraction directory behind. The job still terminates the worker; automatic orphan-directory purging is not implemented.

## Configuration and fallback

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Set-AVConfig -Values @{
    ScanBackend = 'Auto'
    ScanEngineIdleSeconds = 60
    ScanEngineStartupSeconds = 120
}
Get-ClamAVScanEngineState
Stop-ClamAVScanEngine
```

`Auto` tries the private worker when a sibling `libclamav.dll` exists. Unsupported ABI/version, startup/memory failures or unsupported limits fall back to the existing `clamscan` path **before any file is scanned**, with a visible explanation. After a scan has started, a worker failure produces an incomplete/error result instead of silently restarting. A failed startup is cooled down for five minutes for that configuration/database fingerprint.

`ClamScan` explicitly selects the previous backend. `PrivateWorker` requires the new backend and reports startup failures. Idle timeout accepts 15–600 seconds; startup timeout 15–300 seconds. The native adapter currently supports configured per-file limits from 1 byte through 128 MiB, a 400 MiB expanded scan limit and a 120-second native per-file time limit. Exceeding a limit is an incomplete-coverage warning, not a clean result. Use `ClamScan` for unsupported per-file limits. No file type or age is silently excluded by the parallel implementation.

SHA-256 fingerprints cover the configured engine DLL and every file in the flat database directory, not just modification dates. A change stops reuse and reloads signatures. Existing HTTPS, hash, staging, rollback and explicit update confirmations remain in place. The application does not update or download components just to start a scan.

## Security boundaries and licenses

Private handles, restricted privileges, bounded messages and job limits reduce exposure. This is **not an AppContainer or a complete sandbox against a native-engine exploit**. A standard-account process may still access resources allowed to that account. Filesystem path checks reduce link attacks but do not establish race-free traversal. Keep the engine and signatures trusted and updated.

The PowerShell frontend and IPC transport remain MIT licensed. The optional adapter in `Antivirus/Workers/NativeEngine.cs` and `NativeScan.ps1` is **GPL-2.0-or-later**, with its [license text](../Antivirus/Workers/COPYING.txt). ClamAV and its dependencies retain their own licenses. The source ZIP contains adapter source, not ClamAV binaries, databases or PowerShell. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Reproducible checks

Local verification: **177/177 tests passed with Pester 5.7.1**, including all existing scan/update/quarantine tests and 17 new private-engine regressions. Ninety PowerShell files parsed without errors. PSScriptAnalyzer 1.24.0 reported **0 errors**, 484 warnings and 66 informational findings; the warning baseline remains open. The [native test record](benchmarks/private-engine-native-rc5.json) confirms custom-signature/archive detection, reuse, idle exit, public startup cancellation and private temporary ACLs. No EICAR or real malware was placed on the host.

The 17 new regressions also passed with Pester 3.4.0; the complete suite was run with 5.7.1. All 12 application self-test checks passed for rc.5.

Two alternating runs scanned the same 1,000 harmless seeded files (4,608,000 bytes) with installed signatures on an 8-logical-core Windows/SSD machine. No tests or other REMNEXA scans ran during the timed comparison; ordinary system activity remains a source of variability.

| Mean measurement | CLI | Private, cold | Private, warm |
|---|---|---|---|
| Total scan time | 88.82 s | 75.65 s | 10.07 s |
| Time to first file result | 39.02 s | 45.92 s | 2.78 s |
| Sampled scanner CPU seconds | 84.02 s | 94.43 s | 5.43 s |
| Sampled CPU, share of entire machine | 11.83% | 15.61% | 6.77% |
| Maximum sampled scanner working set | 971.88 MiB | 1,132.70 MiB | 1,132.70 MiB |

Total time decreased **14.83% cold** and **88.67% warm** in this dataset. Cold startup/first reply was slower and cold CPU work increased. The native process used approximately **160.82 MiB more peak RAM**, excluding the frontend. Its warm high-water mark includes initialization. Signatures stay in RAM between scans until idle shutdown; this is a performance/memory tradeoff. Two repetitions do not establish a general speedup.

Run the Pester suite for protocol, bounded queues, resource policy, duplicate replies, access/limit warnings and owned-process cleanup. `tools/Test-ClamAVPrivateEngine.ps1` additionally requires a local ClamAV 1.5.4 installation and tests a harmless isolated custom signature, a ZIP, Unicode/empty files, reuse and native idle shutdown. It never changes the installed databases.

`tools/Measure-ClamAVPrivateEngine.ps1` compares the CLI with cold and warm private scans of identical seeded harmless data. It performs no downloads or quarantine. CPU/RAM samples cover the scanner process, not the frontend. See the [measurement data](benchmarks/private-engine-rc5.json). SSD/HDD comparisons, low-memory VMs, elevated-parent launch and a broad real-world malware corpus are separate validation work; local results are not universal speed or protection guarantees.

```powershell
./tools/Test-ClamAVPrivateEngine.ps1 -TestStartupCancellation
./tools/Measure-ClamAVPrivateEngine.ps1 -FileCount 1000 -Repetitions 2
```

The optional cancellation check loads the installed database only until the real worker starts, cancels through the public scan API, and checks process/temp cleanup and the private directory ACL. Engine/version compatibility and installed databases are prerequisites; no update is requested.

Source packages are built from a clean commit with `tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.5'`. They include a per-file manifest and an archive SHA-256 sidecar. `tools/Test-RemnexaPackage.ps1` verifies them. These source artifacts do not include a runtime or scanner and are not an installer or stable release.
