[English](CLAMAV_SCAN_PERFORMANCE.md) | [Deutsch](CLAMAV_SCAN_PERFORMANCE.de.md)

# ClamAV scan performance — 2.2.0-rc.4

This is a development candidate on `feature/clamav-scan-performance`, not a stable release. Restart the application after updating source files.

## Scan backend and scope

Both the baseline (`c95b462`) and this candidate use **one `clamscan.exe` process per scan**, with all deduplicated paths passed in one UTF-8 file list. Signatures are loaded once per process. A later scan loads its database again; there is no incremental clean-file cache to invalidate after signature updates.

The installed Windows ClamAV 1.5.4 package includes `clamd`, `clamdscan`, `MaxThreads` and `MaxQueue`. Its Windows configuration offers TCP; the bundled official protocol documentation says TCP is unauthenticated. An elevated local TCP scanner would expand access to files and daemon commands. A secure, per-user authenticated endpoint was not established in this task, so the existing process backend is retained. No daemon, service, port, firewall rule or external installation is created, contacted or reconfigured. Cross-scan database reuse and engine multithreading are **not implemented**. This limitation is explicit rather than launching multiple signature-heavy processes.

Quick/Full/Custom retain their existing target scopes. Quick is not a whole-disk scan; its existing ProgramData search targets executable content. Custom passes all selected files regardless of extension, age or size. Full keeps its existing documented Windows/profile roots rather than silently turning into an incremental scan.

## Changes and controls

- Lazy depth-first directory enumeration writes to a buffered temporary list. Memory scales with directory depth (bounded at 1,024 open levels), explicit roots and at most 20 inventory issue examples rather than every child in a large directory. Exclusions and reparse-point checks remain; all skipped counts are visible. Race-free handle-based traversal is not claimed.
- Scanner acknowledgements follow the ordered file list on disk instead of retaining a hash set of every reported path. Missing/unexpected replies produce incomplete coverage; duplicate replies do not inflate completion.
- Event-driven stream waits replace fixed sleeps. `--verbose` is omitted; clean-file acknowledgements remain. A scan-only status check avoids launching version/sigtool processes; the normal detailed status command retains those fields.
- Antivirus **P** selects **Eco**, **Balanced** (default) or **Fast**. The settings persist through the existing atomic configuration writer.

| Mode | Engine process priority | Parallel scanner processes |
|---|---|---|
| Eco | Idle | 1 |
| Balanced | BelowNormal | 1 |
| Fast | Normal | 1 |

Available physical memory and total CPU load are sampled through documented Windows APIs. Below 3 GiB available RAM or at least 80% measured CPU load, priority is reduced to Idle. Below 2 GiB available RAM a new scan is refused with an explanation. Measurements unavailable on an unsupported host remain unknown. Logical cores are reported; they do not enable unsupported clamscan threading. Disk type is not guessed or used to change coverage. Priority is a scheduler hint, **not a hard CPU, I/O or RAM cap**; memory pressure can change after preflight.

An installation-specific Windows mutex rejects concurrent REMNEXA scan/update processes, so two jobs do not load the same database simultaneously. It is scoped to normalized configured engine/database paths; aliases or independent third-party ClamAV processes are not managed. Existing external services are left alone.

During discovery/scan, **X**, **Esc** or **Ctrl+C** cancels the operation. During ordinary menus, X retains its existing application-exit behavior. Scripts can pass a `CancellationToken`. Only the owned native process tree is terminated. Cancellation returns `Status=Cancelled`, `CoverageComplete=false` and any detections already received; it never means a clean scan. Explicitly requested quarantine remains the existing separate path; scan-limit warnings are never quarantined.

Live progress shows mode, acknowledged files, detections, elapsed time and measured reply rate. The first reply includes initialization/first-file work; file-rate measurement begins at that reply. Percentages require the completed inventory, otherwise progress stays indeterminate. Inventory, status, scanner, first-reply and result-phase timings are returned with successful scan results. The configured engine file-size/scan-size/recursion limits are retained with `--alert-exceeds-max=yes`; `Heuristics.Limits.Exceeded*` is a visible **LimitExceeded** warning with incomplete coverage, not a malware diagnosis.

## Reproduce measurements

Recorded on Windows build 26300, PowerShell 7.6.9, ClamAV 1.5.4, 8 logical cores, approximately 15.85 GiB installed RAM and a SATA SSD. Each version scanned the same 4,000 deterministic benign files (18,432,000 bytes) twice, in alternating order. Every run acknowledged all 4,000 files with complete coverage. Database SHA-256 values were unchanged between measurement rounds. [Raw, path-free results](benchmarks/clamav-scan-rc4.json).

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Mean complete scan | 76.84 s | 73.48 s |
| Individual runs | 76.05 / 77.63 s | 73.13 / 73.84 s |
| Mean inventory | 3.016 s | 0.380 s |
| Mean scanner process | 70.62 s | 72.05 s |
| Mean time to first file reply inside scanner call | 12.54 s | 13.59 s |
| Mean files/s, including preparation | 52.06 | 54.43 |
| Sampled CPU seconds, application + children | 85.05 s | 80.54 s |
| Sampled mean CPU, share of entire 8-core machine | 13.53% | 13.41% |
| Maximum sampled concurrent working set | 1,119.34 MiB | 1,159.83 MiB |

Total elapsed time decreased **4.37%** and inventory time decreased **87.41%** in this small comparison. The scanner/first-reply phase itself was slower; reduced orchestration work produced the net gain. Peak sampled RAM increased approximately **40.50 MiB**, partly including the in-process C# helper/compiler load; this benchmark does **not** demonstrate a lower total RAM peak. There is no new engine-thread speedup. An earlier trial run alongside tests was slower and was excluded from this controlled comparison: scheduler priorities make results under competing load particularly variable. Two repeats are observations, not a universal performance guarantee.

Use a baseline checkout/source directory and a candidate checkout with a locally configured ClamAV installation. The benchmark downloads nothing, updates no databases and generates only deterministic benign `.dat` files in an isolated temporary directory. It runs Custom scans without quarantine and alternates baseline/candidate order.

```powershell
./tools/Measure-ClamAVScan.ps1 -BaselineRoot ../REMNEXA-baseline -FileCount 4000 -Repetitions 2
```

The tool requires the candidate's `runtime/pwsh.exe`; source packages do not bundle it. Reports in ignored `dist/` contain counts, timings and database hashes, not scanned file paths. Temporary worker/config/data files stay under the generated benchmark directory for diagnosis; review before sharing or removing it.

CPU and concurrent process working sets are sampled every 100 ms, with child discovery every 500 ms. Short-lived process CPU may be missed: these are sampled observations, not exact profiler totals or private committed memory. Disk-I/O attribution and HDD measurements were not collected. Run without simultaneous tests, builds or scans; antivirus activity, caches and other processes can still affect results.

## Verification limits

Regression coverage includes overlapping roots, duplicate/missing acknowledgements, explicit limit warnings, offline mock scans, missing components, return codes, constrained resource policies, persistent modes, cancellation before/during work, live owned-process cleanup, cross-process exclusion, UI navigation and six-language placeholder parity. Existing update/quarantine regression tests remain part of the suite. Detection/cancellation fixtures simulate findings with harmless content; no EICAR file is placed on the host.

A separate live smoke check cancelled the real installed clamscan during database loading, returned incomplete status and left zero new clamscan processes. A subsequent offline API scan of one benign Unicode-named file completed with one acknowledged file and complete coverage. No database update or quarantine was requested.

Interactive pseudo-console checks also exercised **X**, **Esc** and **Ctrl+C** against the real engine. All returned cancelled/incomplete results and left no scanner process. The Ctrl+C test interrupted the surrounding test shell with its normal nonzero exit status; the application still produced its cancellation result and cleaned up the scanner.

Final automated checks: **160 passed, 0 failed, 0 skipped** with each of Pester 3.4.0 and 5.7.1; 82 PowerShell files parsed without errors; the application's 12 self-test checks passed. PSScriptAnalyzer 1.24.0 reported **0 errors**, 430 warnings and 66 informational findings. The warning baseline is not presented as resolved.

Only this development machine's Windows/SSD environment was measured. An 8 GiB VM, HDD, production-scale directory tree, other terminal hosts and real malware detection are not certified by these checks. No blanket speedup or antivirus replacement claim is made. Stable release validation and approval remain separate.
