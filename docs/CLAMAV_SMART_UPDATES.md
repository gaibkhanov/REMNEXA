[English](CLAMAV_SMART_UPDATES.md) | [Deutsch](CLAMAV_SMART_UPDATES.de.md)

# ClamAV smart updates — 2.2.0-rc.3

**Implemented development feature, not a stable release.** This extends [rc.2](RELEASE_2.2.0_RC2.md). Existing scan, setup, status, quarantine and restore APIs remain available.

## What happens

At application startup, REMNEXA checks its configuration, local installation and cached metadata. When due, it dispatches one hidden, owned PowerShell worker and immediately continues to the home menu. Missing ClamAV skips online checks. No update notices are printed on the home screen. Normal application exit, direct exit and module removal stop the owned worker; network operations and retries also have bounded deadlines. No service, scheduled task or autostart entry is added.

The worker reads the installed engine version and small local database headers. It fetches the latest stable Windows release metadata from the official Cisco-Talos GitHub repository and queries ClamAV's official `current.cvd.clamav.net` TXT record through Windows DNS. It never invokes installation, FreshClam or a scan. It never downloads engine archives or database updates.

Engine versions use semantic ordering, including prereleases. A newer stable version is offered only for a supported Windows asset with an official HTTPS source and valid SHA-256 metadata. A missing hash disables the engine update action. Actual installation fetches and validates the asset again; cache data is not installation authority. Engine updates reject downgrades and unknown package versions, retain staging/rollback and preserve the existing database.

Database versions use readable `main`, `daily` and `bytecode` CVD/CLD headers and the official TXT field mapping. Missing, conflicting or unreliable local headers remain unknown. Malformed or older-than-three-hour DNS records are rejected. DNS is advisory availability information, not a signed download or proof of protection. FreshClam remains responsible for confirmed database updates and its own integrity checks. Unknown versions produce an update recommendation, not an invented available update.

## Antivirus controls

- Existing numbered actions **1–7** remain in place.
- **U** runs an immediate metadata check, bypassing the interval, then offers supported database-only, engine-only or combined updates. Offline checks return to the menu without forcing an update.
- **I** shows component status, local/available database versions and the last successful metadata check.
- Before a console scan, confirmed pending updates offer **J** to update then scan, **N** to scan without updating, **I** for information and **0** to return. `Y` is also accepted as a quiet confirmation alias; the displayed keys are consistent across languages.
- After a failed update, scanning continues only after a separate explicit confirmation. The update is not retried repeatedly within that scan. The scan rechecks the local engine/database readiness.
- Direct module scans remain noninteractive and do not fetch updates. Noninteractive removal scans also avoid updates. The legacy `AutoUpdateSignatures` setting no longer authorizes a silent update from the console removal workflow; explicit update APIs and example workflows remain separate.

Signature and engine evidence expires independently. A working signature endpoint is still useful if the release endpoint fails. Offline, stale and failed checks never become an unqualified current status. Metadata failures do not delete or disable an installed scanner.

## Settings and storage

Settings are in `config/antivirus.json`; older configuration files receive compatible defaults in memory. `Set-AVConfig` validates the settings before saving.

| Setting | Default | Allowed |
| --- | --- | --- |
| `AutoCheckUpdates` | `true` | Boolean; U can still explicitly check when automatic checks are disabled. |
| `UpdateCheckIntervalHours` | `24` | 1–168 hours. |
| `UpdateNetworkTimeoutSeconds` | `3` | 1–10 seconds per HTTP/DNS/native version operation. |
| `UpdateRetryCount` | `1` | 0–2 retries after the first attempt. |
| `UpdateRetryBackoffSeconds` | `1` | 1–30 seconds, doubled between retries. |

Successful checks are reused within the interval. Failed attempts also persist a cooldown, starting at one minute and increasing to at most one hour between subsequent application-triggered attempts. Already successful component endpoints are not redundantly retried within one attempt sequence. There is no permanent background polling loop.

State is stored under `%LOCALAPPDATA%\REMNEXA\AntivirusUpdates.json`. It includes component versions/status/timestamps, retry timing and a local configuration fingerprint. Writes use a validated same-directory temporary file and atomic replacement. A file lease prevents concurrent metadata/managed-update transactions from overwriting one another. Corrupt, oversized, unsafe or mismatched state is treated as unknown. The adjacent lock file may remain empty after exit; it is not a running process.

The check sends no personal files, filenames, reports, logs or installation paths. Requests necessarily expose ordinary network metadata, such as the source IP address, to the contacted server or DNS resolver. No telemetry or API key is used.

## Verification and limits

Tests use mocks and isolated directories. They cover missing installation, offline/current/new versions, both components, bounded retries, corrupt information, hashes/sources, semantic ordering, no downgrade, atomic replacement failures, cache age/cooldown, failed workers, concurrent leases, confirmation/decline/failure continuation and six-language completeness. Real home-menu tests use an isolated deliberately slow worker and verify input remains usable and the worker stops at exit.

Read-only live metadata validation also identified a newer daily database without updating anything. A later live run exercised partial success when the release endpoint failed but official database metadata remained available. Dispatch was approximately 0.18–0.45 seconds in these local observations; this is not a universal startup benchmark. Real downloads, privileged engine replacement, live signature installation and a clean Windows VM matrix were not performed for this feature.

Local validation on PowerShell 7.6.9: Pester 3.4.0 and 5.7.1 each passed all **144 tests**, with zero failures/skips. Parsing and the PSScriptAnalyzer 1.24.0 error gate found zero errors in **78 first-party PowerShell files**. The application self-test passed **12 checks**. All six locales contain **346 nonempty keys**. The English/German documentation and relative links were checked; the license text is unchanged. These are local results, not a remote-CI or full compatibility certification.

No stable release is created by this change. From the development checkout, build a source test package with:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.3'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Source packages exclude optional PowerShell/ClamAV payloads and signatures. Restart an older running application to load the changes. For general operation, see the [Antivirus guide](../Antivirus/README.md).

Implementation references: [official release metadata](https://api.github.com/repos/Cisco-Talos/clamav/releases/latest), [FreshClam's database field mapping](https://github.com/Cisco-Talos/clamav/blob/main/libfreshclam/libfreshclam_internal.c) and [DNS timestamp validation](https://github.com/Cisco-Talos/clamav/blob/main/libfreshclam/libfreshclam.c). The CVD/CLD header format is described in [ClamAV database documentation](https://docs.clamav.net/manual/Signatures/Introduction.html).
