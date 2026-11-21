[English](README.md) | [Deutsch](README.de.md)

# Optional ClamAV integration

REMNEXA integrates ClamAV for local, on-demand scanning. It is not a resident protection service or a replacement for Microsoft Defender or another antivirus. Review the [user guide](../docs/USER_GUIDE.md) and [security model](../docs/SECURITY_MODEL.md).

## Independent scans and application exit

Version 2.2.0 starts interactive scans in their own window. REMNEXA remains usable and offers **continue scanning**, **cancel scan**, or **return to application** on exit. The scan window supports pause/resume/cancel; results are saved locally. See [usage and verified limits](../docs/INDEPENDENT_SCANS.md).

## Components and requirements

The source contains the PowerShell integration, not ClamAV executables or signature databases. Setup needs a supported Windows ClamAV package, internet access and suitable permissions. The application explains elevation before opening its Antivirus workspace. API users must provide elevation where required for system scan targets or installation paths.

Load the module from the repository root:

```powershell
Import-Module .\Antivirus\Antivirus.psd1
Get-ClamAVStatus
Get-AVConfig
```

## Smart update checks

Candidate rc.3 checks official engine/database metadata in a silent background worker at startup, normally once per day. No packages are installed by that check. Open Antivirus for the cached status, use **U** for an immediate check and supported update choices, or **I** for details. Console scans offer confirmed pending updates and ask separately before continuing after a failed update. Offline scans remain available with an existing working database. Six-language messages, settings, cache/retry handling and verification limits are documented in the [smart-update guide](../docs/CLAMAV_SMART_UPDATES.md).

## Installation and updates

Use the setup action in the application, or explicitly request installation:

```powershell
Initialize-ClamAV -Install
Update-ClamAVSignature
```

Downloads require HTTPS and a valid, matching SHA-256 digest. Automatic setup depends on usable upstream release metadata; missing or malformed digests abort installation. Direct archive installation requires `-DownloadUri` and `-ExpectedSha256` from a trusted source. Never invent a digest or bypass verification to make installation succeed.

Installation stages the engine beside its target, preserves existing signatures and retains the replaced engine. Configuration-commit failures trigger rollback to the prior engine. A subsequent signature-update failure is outside that transaction; it does not automatically restore every earlier state. Retained engine backups have no in-application restore interface.

`Update-ClamAVEngine` handles engine updates; `Update-ClamAVSignature` invokes freshclam for signature updates. They are separate operations. Signature age warnings default to seven days; consult the actual configuration.

## Scans

Examples after engine/signature setup:

```powershell
Invoke-ClamAVScan -ScanType Quick
Invoke-ClamAVScan -ScanType Full
Invoke-ClamAVScan -ScanType Custom -Path '.\scan-fixture' -Timeout 1800
```

The custom example requires an existing directory. Choose targets deliberately.

| Type | Scope |
| --- | --- |
| Quick | Configured common infection locations, including temporary and startup locations. |
| Full | Defined Windows, program and user roots; not a guarantee of every mounted disk/file. |
| Custom | Explicit existing targets; at least one is required. |

`-IncludePUA` enables potentially unwanted application detection, which can raise false positives. `-MaxFileSize` and configured exclusions/limits affect coverage. Locked files, permissions, archive limits and timeouts can prevent complete inspection.

ClamAV exit code 0 means no detections, 1 means detections and 2 means a scan error. A detection is not automatically a confirmed infection; no detections are not proof of safety.

Candidate rc.2 inventories files before invoking ClamAV, deduplicates overlapping roots and skips linked paths. During scanning, the percentage uses reported file results versus the inventory, alongside the current phase, item and elapsed time. Engine loading and inventory have no invented time percentage. Missing replies or enumeration skips produce a warning and incomplete coverage; errors are red and successful completion is green. Counts describe file replies, not deep inspection of all archive members or a remaining-time estimate. Configured exclusions and ClamAV limits still apply. Read the [progress and verification details](../docs/RELEASE_2.2.0_RC2.md).

Scanning uses local engine/signatures and can run offline. The scan function itself does not fetch fresh signatures. Setup, explicit updates and other configured workflow update actions can require network access; prepare and verify the offline configuration beforehand. Old signatures reduce usefulness.

## Quarantine and restore

Ordinary scans report findings. `-Quarantine` explicitly opts into moving detected files into managed quarantine with a SHA-256-backed JSON manifest. The generic default location is `%ProgramData%\REMNEXA\Quarantine`; configuration can change it.

`Get-ClamAVQuarantine` lists entries. Select and review the detection, original path and intended restore target before using the application's restore action or `Restore-ClamAVQuarantine -Identifier`. Restoring can reintroduce a threat. The module verifies the stored hash and refuses an existing destination.

Do not use `-Force` as a workaround: it skips the module's confirmation, not its integrity/no-overwrite checks. The UI supplies its own explicit warning before invoking restore. Never publish quarantined files or private manifests.

## Configuration

Candidate rc.6 fixes restricted launch from an elevated application and adds constrained-memory/archive checks. See [current worker validation](../docs/RELEASE_2.2.0_RC6.md) for results and remaining VM/HDD limits.

Candidate rc.5 can keep a native ClamAV 1.5.4 engine loaded between scans, using private inherited pipes and bounded native threads. `ScanBackend` accepts `Auto` (default), `ClamScan` or `PrivateWorker`; `ScanEngineIdleSeconds` defaults to 60. No daemon port or service is opened. See [private engine, fallback and license details](../docs/PRIVATE_SCAN_ENGINE.md).

Choose **P** in the Antivirus menu for Eco/Balanced/Fast settings. Cancel an independent scan through **C** in its window or scan manager; synchronous console scans retain their X/Esc/Ctrl+C cancellation controls. Cancellation reports incomplete coverage. One REMNEXA scan/update at a time is allowed per configured installation. Engine limit warnings are visible and never quarantined as malware. See [performance behavior and benchmark limits](../docs/CLAMAV_SCAN_PERFORMANCE.md).

Use `config/antivirus.json`, `Get-AVConfig` and `Set-AVConfig`; prefer supported validated writes:

```powershell
Set-AVConfig -Values @{
    ScanBeforeRemoval = $false
    ScanAfterRemoval = $true
    IncludePUA = $false
    MaxFileSize = '100M'
}
```

These settings change future behavior; they do not run a scan immediately. Check configured paths, exclusions, signature policy and timeout before broad scans. Logs and quarantine are excluded from scanning as configured. See [the workflow example](../Examples/Invoke-AntivirusWorkflow.ps1) for the module API.

## Background scans

Quick/custom scans started from the Antivirus menu continue in the background. Choose **B** or enter **/scan** at another REMNEXA input prompt to view status and live findings, pause/resume or cancel. **D** opens a static findings snapshot; **0** returns while scanning continues. Exiting REMNEXA offers continue/cancel/back; choosing continue leaves the independent scan window running. The scanner retains its RAM while paused, and updates/competing scans stay excluded. Synchronous module commands retain their existing behavior. See [usage and verification](../docs/INDEPENDENT_SCANS.md).

## Troubleshooting and licensing

Check engine/signature readiness, exact errors, permissions and configured paths before retrying. An expired signature warning is different from an engine startup failure. Do not disable installed security software to force REMNEXA to run.

The optional REMNEXA native adapter in `Workers` is GPL-2.0-or-later; the frontend/transport remain MIT. ClamAV has its own license and third-party notices. Preserve upstream notices when distributing it. See [third-party notices](../docs/THIRD_PARTY_NOTICES.md) and [official ClamAV documentation](https://docs.clamav.net/).
