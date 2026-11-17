[English](CHANGELOG.md) | [Deutsch](CHANGELOG.de.md)

# Changelog

Development changes are not published release claims. Existing release artifacts and tags are not modified by this document.

## 2.2.0 — development, not released

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
