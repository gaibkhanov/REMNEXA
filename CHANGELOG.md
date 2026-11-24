[English](CHANGELOG.md) | [Deutsch](CHANGELOG.de.md)

# Changelog

Development changes are not published release claims. Existing release artifacts and tags are not modified by this document.

## Unreleased — Windows launcher preview

- Add a common background update center for portable PowerShell, ClamAV, signatures and supported stable Complete app releases. Require confirmation and verified official assets; preserve active runtimes/scans and stage replacements with cancellation before activation.
- Show local component/database versions, prepared-runtime notices and recent saved activities on the start dashboard. Keep menus usable during updates; document restart, offline, scan-lock and app-package limits.

- Make Complete the default user package: bundle pinned PowerShell 7.7.0, portable ClamAV 1.5.5, verified FreshClam signature snapshots, runtime dependencies, license notices and matching ClamAV source. Fail incomplete or stale builds; retain an explicitly selected Standard developer profile.
- Verify upstream archive/runtime bytes and signature integrity, exclude local updater state and preserve database timestamps when archiving. Add isolated packaging security regressions and clearly identify Standard CI artifacts as developer builds.

- Separate saved Antivirus history from live status: dated home-screen summaries, H and /scans navigation, conditional paging and clear incomplete-scan messages. Preserve per-run records across scan-window reuse and read older snapshots without inventing timestamps.
- Clarify that the end-user folder contains one EXE, a short README, app/ and optional runtime/; source and compatibility launchers remain in the developer checkout.

- Fix repeated progress banners and overlapping download bars. Show actual download bytes, cancellable bounded HTTPS transfers and a clear update-before-scan message; cancellation does not launch the scan.
- Replace repeated scan-console clearing with one stable buffer update, disable window-local Quick Edit, retain direct P/R/C controls and add manual U refresh for the main application's snapshot. Add isolated console/mouse, download-failure and cancellation regressions.

- Require Windows 11 or newer (client build 22000+) in the native launcher and PowerShell entry; reject Windows 10/older/Server before application initialization, add six-language notices and platform-boundary regression tests. Existing release artifacts remain unchanged.
- Add opt-in SHA-256 Authenticode signing with HTTPS RFC 3161 timestamps, trusted-certificate/tool checks, verification before package hashing and isolated regression tests. The current artifact remains unsigned because signing credentials/tools are unavailable.
- Add native x64 Win32 launcher with official multi-size icon, validated PowerShell discovery and safe argument passing; no policy bypass or blanket elevation.
- Build an allowlisted user package with one EXE, app/ and optional licensed runtime; exclude developer files and backups.
- Preserve source compatibility entries, normalize examples and keep verified local backups outside the repository.
- [Build, layout and limits](docs/WINDOWS_LAUNCHER.md); existing stable release unchanged.

## 2.2.0 — 2026-11-21

### Stable source release

- Promote the verified rc.8 functional baseline to 2.2.0; earlier candidate reports remain historical validation records.
- Source ZIP, SHA-256 checksum and English/German release notes; no bundled runtime, ClamAV database, AI or installer.
- Confirm rc.8 GitHub CI success. Final release source is checked again before publication. See [validation and limits](docs/RELEASE_2.2.0.md).

### Candidate 2.2.0-rc.8

- Run interactive scans in an independent PowerShell window so the main application can exit while scanning continues.
- Offer continue/cancel/back when exiting with an active scan; resume paused scans before confirmed continuation and preserve cancellation evidence.
- Add same-user/elevation local pipe controls, atomic private status/results, re-opening the latest session and owned CLI process cleanup when the scan host exits.
- Retain native cache reuse while attached, release it after detached completion, and translate all new controls into six languages.
- Verify creator-process exit with both real CLI and private-worker backends on 2,501 harmless files each. See [usage and validation limits](docs/INDEPENDENT_SCANS.md). No stable release is published.

### Candidate 2.2.0-rc.7

- Run interactive Antivirus quick/custom scans in a background runspace while other REMNEXA tools remain usable.
- Add **B** and global **/scan** access to live status/findings, pause/resume, cancellation and a static evidence snapshot; translate controls into all six languages.
- Keep one active scan per installation, preserve detections on cancellation, and collect results/cleanup before publishing completion. Exiting REMNEXA cancels the scan.
- Test real CLI/private-worker pause/resume and paused cancellation with 2,501 harmless files per backend. See [behavior and validation limits](docs/BACKGROUND_SCANS.md).

### Candidate 2.2.0-rc.6

- Fix restricted worker startup from an elevated parent by explicitly preserving current-user/SYSTEM access to token defaults and process/thread objects.
- Verify actual Windows CPU/memory/process limits and full-signature scans under a 1.5 GiB process limit, with simulated low-memory admission boundaries.
- Compare eleven harmless native/CLI fixtures; check nested ZIP, GZip, TAR, size limits, sharing errors, reuse and signature-change reload without changing installed databases.
- Add CI host diagnostics, isolate test reports under `dist/`, and select one Git executable when several PATH entries match during source packaging.
- See [validation records and missing VM/HDD coverage](docs/RELEASE_2.2.0_RC6.md). No stable release is published.

### Candidate 2.2.0-rc.5

- Add a reusable ClamAV 1.5.4 native engine with inherited private pipes instead of an unauthenticated TCP daemon. Engine/signature updates invalidate and stop the owned cache.
- Bound native scan concurrency and reordering, restrict worker privileges, enforce job CPU/commit limits and kill owned workers on cancellation, idle timeout or owner exit.
- Keep CLI fallback for unsupported startup configurations, complete per-file accounting, explicit limit/error results and existing update/quarantine controls.
- Add six-language startup/reuse/fallback messages, lifecycle APIs, reproducible native tests and cold/warm benchmark tools. The optional linked adapter is GPL-2.0-or-later; frontend/transport remain MIT.
- See [implementation and validation boundaries](docs/PRIVATE_SCAN_ENGINE.md). No stable release is created.

### Candidate 2.2.0-rc.4

- Stream directory entries into a temporary file list using lazy .NET enumerators; avoid materializing every child and retaining acknowledged file paths.
- Wake native output readers on data instead of sleeping after each asynchronous read; omit verbose scanner lines and redundant version/signature-tool launches on the scan-only status path.
- Add Antivirus P settings (Eco/Balanced/Fast), measured resource adaptation, one scan process per configured installation and a 2 GiB available-memory preflight. These priorities are not thread-count or hard memory limits.
- Cancel discovery/scanning with X, Esc, Ctrl+C or a cancellation token; terminate owned native processes and retain prior detections as incomplete results.
- Report engine scan-size/recursion limits as non-malware, incomplete warnings; never quarantine limit warnings. Existing update and quarantine safeguards remain.
- Preserve update behavior and six-language UI resources. [Benchmarks, scope and validation](docs/CLAMAV_SCAN_PERFORMANCE.md).

### Candidate 2.2.0-rc.3

- Silent, asynchronous ClamAV engine/database metadata checks with configurable timeouts, a 24-hour default cache, bounded retries/backoff and owned-worker shutdown.
- Separate semantic engine comparison and official database TXT/header versions; unknown, offline and stale evidence is not presented as current.
- Antivirus U/I controls, component-specific confirmed updates and once-per-scan update decisions with explicit continuation after failures.
- Atomic update state and exclusive metadata/update leases; missing hashes, untrusted package sources and downgrades remain blocked.
- All six UI languages and paired English/German instructions. Existing Antivirus numbering/APIs and rc.2 progress improvements are retained. [Behavior and validation](docs/CLAMAV_SMART_UPDATES.md).

### Candidate 2.2.0-rc.2

- Shared measured/indeterminate progress, current phases/items, elapsed time, input-wait state and labeled colors across processing areas.
- Live native output/heartbeats with bounded result capture and owned-process cleanup on callback failures.
- Deduplicated Antivirus inventory, per-file reply counts and explicit partial/error outcomes instead of fixed scan-stage percentages.
- Six-language progress resources and additional regressions. See [behavior, validation and deferred work](docs/RELEASE_2.2.0_RC2.md). Publication remains postponed.

### Candidate 2.2.0-rc.1

- Native-process timeouts request owned-process-tree termination with a bounded cleanup wait. Redirected output draining shares the deadline; empty arguments are preserved.
- Source backups exclude top-level Git metadata, generated packages and abandoned staging directories; the default version is updated to this candidate.
- Clean-commit source packaging produces a ZIP, an internal per-file SHA-256 manifest and an archive checksum sidecar. Existing outputs are never overwritten.
- Verification rejects changed content, missing/unlisted files, unsafe paths, case-insensitive duplicates and incorrect expected archive hashes without extracting files.
- CI now builds, verifies and uploads the source candidate as a workflow artifact; it does not publish a GitHub release.
- Console clearing is cosmetic and no longer crashes application startup when cursor APIs are unavailable, including redirected output.
- Regression coverage increases to 89 tests, including real application home/exit startup. See [candidate verification and limitations](docs/RELEASE_2.2.0_RC1.md).

### Added

- Architecture audit, prioritized roadmap, security model and compatibility matrix.
- Six external locale resources with German fallback and completeness checks.
- Core modules for validated settings, logging, native processes, administrator checks, versioned outcomes and read-only system snapshots.
- A main-menu system overview for Windows, CPU, memory and fixed drives.
- Advisory-only AI input/output contracts; no inference runtime or model.
- Local Pester/analyzer runners, source-checkpoint tooling and Windows quality workflow.
- Regression tests for security, configuration, navigation, elevation and completion behavior.
- Paired English/German documentation, a documentation index and full user guides.
- Optional PayPal donation link and button.

### Fixed

- Optional runtime/ClamAV absence no longer fails the source-package self-test.
- ClamAV archive installation requires HTTPS and valid matching SHA-256 metadata.
- Engine replacement stages installation, preserves signatures and restores the prior engine on configuration-commit failure.
- Supported application/antivirus settings use validated atomic writes.
- Privacy restore validates a fixed Registry allowlist and schema before writes.
- File candidate collection/removal rejects reparse-point ancestors and uninspectable paths.
- WindowsApps directories remain visible as intentionally retained items instead of generic deletion targets; no ownership/ACL takeover.
- Registry exit code 1 is a failure; child coverage derives only from successfully removed parent keys.
- Removal result/history and 100% completion precede optional system assessment.
- Service and antivirus messages explain demand-start, third-party registration and uncertainty without duplicate Defender warnings.
- Restore-point success requires confirmation of a new uniquely described point.
- Every application elevation request has an action-specific explanation; Antivirus can resume directly after approval.
- Next/previous page choices appear only when valid; invalid commands explain available choices.
- Prompts show a single direct exit choice: 0 where it exits, X elsewhere.
- Quarantine restoration keeps explicit warning, integrity validation and no-overwrite protection.
- Documentation removes contributor-specific filesystem locations and separates implemented features from plans.

### Verification and known limits

The recorded application baseline has 79 passing local Pester tests and 12 self-test checks. Documentation changes do not imply a new application test run. Analyzer warnings/full-run failure, filesystem races, incomplete recovery, unverified Windows/CI matrix, missing AI/installer and lack of release candidate remain open. See the [development report](docs/VERSION_2.2.0.md).

## 2.1.3 — source baseline

The preceding source version supplies the application-removal and maintenance foundation. Earlier release details should be checked against their original tags and artifacts; this changelog does not reconstruct unverified historical release notes.
