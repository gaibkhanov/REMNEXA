[English](README.md) | [Deutsch](README.de.md)

# REMNEXA

**More control over your Windows PC.**

A free, open-source Windows utility for application removal, startup management, system maintenance and optional local malware scanning. Review detected items and choose which supported changes to make.

**Windows 11 or newer · PowerShell 7.5+ · Open Source · Six interface languages**

> **Version 2.2.0**: [Download and release notes](https://github.com/gaibkhanov/REMNEXA/releases/tag/v2.2.0). Source package with SHA-256 checksum; PowerShell and optional ClamAV components are required separately. See [installation, validation and limits](docs/RELEASE_2.2.0.md).

> **Feature-branch launcher preview:** Native Windows entry with the REMNEXA icon and a clean end-user package. See [build and limits](docs/WINDOWS_LAUNCHER.md). The stable release above remains unchanged.

For everyday use, open the extracted **Complete user package**, whose top level contains only `REMNEXA.exe`, `README.txt`, `app/` and `runtime/`. Keep these together. The repository root is the developer checkout, including source files, compatibility launchers, tests and build tools.

The package builder supports verified Authenticode signing when a trusted signing certificate and Microsoft SignTool are available. The current preview is **unsigned**; see [signing requirements](docs/WINDOWS_LAUNCHER.md#authenticode-signing).

## Features

The launcher preview also fixes overlapping Antivirus progress output and scan-window flicker. Scan controls use **P/R/C** directly without Enter; the main scan manager uses **U** and Enter for a snapshot refresh. Engine downloads show received bytes and support **C** to cancel before the file scan starts. See [scan controls](docs/INDEPENDENT_SCANS.md).

### Application removal

- Uninstall supported desktop, MSI and Microsoft Store applications.
- Find potentially related files, directories, Registry entries, services and scheduled tasks.
- Preview leftovers and confirm cleanup separately from the official uninstaller.
- Review removed, failed, intentionally retained and remaining items.
- Keep Windows-managed package files protected from generic manual deletion.

A match is a cleanup candidate, not proof of ownership. Review every proposed removal. Store package removal has user and provisioning scope limits; see the [user guide](docs/USER_GUIDE.md).

### Startup and system maintenance

Inspect and manage supported startup entries, with backups for supported changes. View Windows version, CPU load, memory, fixed-drive space and running services. Access selected Windows repair, optional-feature and privacy tools.

The system overview is read-only. The current interface is a terminal application; a graphical dashboard is planned.

### Optional ClamAV scanning

Scans run in their own window. Keep using REMNEXA, or exit it and choose to let the scan finish independently. Pause, resume, cancel and inspect findings through the scan manager or scan window. See the [independent scan guide](docs/INDEPENDENT_SCANS.md).

Run local on-demand scans, update signatures and review detections. Supported quarantine and restore operations require deliberate selection. Complete includes the engine and signatures for immediate offline scans. Initial component setup for source/Standard distributions and future updates need internet access.

REMNEXA is not a real-time antivirus and does not replace Microsoft Defender or your installed security software. A detection can be a false positive; no detections do not guarantee safety. See the [ClamAV guide](Antivirus/README.md).

### Six interface languages

German, English, Spanish, French, Russian and Turkish. Translation resources are separate from application logic, with German fallback. Project documentation is available in English and German.

## Installation

### Updates inside REMNEXA

The Complete development build adds **[U] Updates and versions** and **/updates**. Confirm PowerShell, ClamAV or signature updates and keep using the app while they run in the background. PowerShell activates on the next launch; Antivirus activation waits for active scans. The dashboard shows local versions and recent saved activities. A newer REMNEXA app can be prepared when its official stable Complete package and checksum are available. See [behavior and limits](docs/UPDATES.md).

### Complete user package

The Complete build in this development branch bundles **PowerShell 7.7.0, ClamAV 1.5.5 and a verified virus-signature snapshot**. No separate PowerShell, .NET, ClamAV or command-line installation is required. Download the **Complete ZIP** when published, extract the entire folder to a writable location, and double-click **REMNEXA.exe**. Keep `app/` and `runtime/` beside it. Scanning works offline immediately; internet is only needed for later updates. Windows may still request administrator consent for protected operations.

Complete packages use the filename `REMNEXA-2.2.0-complete-windows-x64-preview.zip`. This branch prepares a candidate, not a new stable release. Standard CI artifacts and source ZIPs are developer distributions and do not provide this bundled experience. See [packaging and verification](docs/WINDOWS_LAUNCHER.md).

### Running the source or Standard developer package

Requirements: Windows 11 or newer (Windows client build **22000+**), PowerShell **7.5 or newer**, and administrator approval for operations requiring elevated access. Current development builds reject Windows 10, older Windows versions and Windows Server before application initialization. Windows PowerShell 5.1 cannot run the application. Existing published release files remain unchanged. Consult the [compatibility matrix](docs/COMPATIBILITY_MATRIX.md) for tested limits.

Download the release source ZIP, or check out the release tag with Git:

```powershell
git clone --branch v2.2.0 https://github.com/gaibkhanov/REMNEXA.git
Set-Location REMNEXA
.\REMNEXA.cmd
```

Alternatively:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1
```

The launcher prefers a bundled `runtime\pwsh.exe`, otherwise PowerShell on `PATH`. **The source repository excludes the portable runtime, ClamAV binaries and signature databases.** Install PowerShell separately for a source checkout. Keep the source directories together. A new Windows installer is not included.

## Safety and control

- Review cleanup previews and explicitly confirm interactive destructive actions.
- Read the action-specific explanation before allowing a Windows administrator prompt.
- Protected components are blocked by default; WindowsApps folders are excluded from generic deletion.
- Supported operations attempt to create a new restore point and verify Windows actually created it.
- Structured logs distinguish skipped paths, failures and final remaining traces.
- Personal folders are excluded from the default leftover scan; an extended scan requires extra care.

Backups and restore points do not guarantee full recovery. Uninstalling another vendor's application can be irreversible. Keep independent backups of important data.

Service and antivirus checks are snapshots. A stopped demand-start service is not automatically faulty. Another registered antivirus can explain Defender standing down, but registration alone does not prove active protection.

## What's new in 2.2.0

Version 2.2.0 adds independent scan windows and continue/cancel/back choices when exiting REMNEXA. Earlier rc.6 fixes native worker launch from an elevated application and extends real job-limit, constrained-memory, archive and signature-reload checks. The reusable ClamAV 1.5.4 engine, CLI fallback, Eco/Balanced/Fast controls and cancellation remain available. Existing update and quarantine safeguards are preserved. See [verification and remaining limits](docs/INDEPENDENT_SCANS.md).

- HTTPS and SHA-256 checks for supported ClamAV downloads; staged installation and configuration recovery.
- Additional linked-path checks and validation of supported privacy backups.
- Clearer cleanup accounting, access errors and Windows-managed retained items.
- Completion at 100% before the optional system-status check.
- Contextual service/antivirus messages and action-specific administrator explanations.
- Page navigation only when another page exists; one visible exit option per prompt.
- Modular core components, external translations and a read-only system overview.

Current behavior and remaining limits are recorded in the [private-engine report](docs/INDEPENDENT_SCANS.md). Earlier results remain in the historical [development report](docs/VERSION_2.2.0.md).

## Documentation

- [Documentation index](docs/README.md) · [User guide](docs/USER_GUIDE.md)
- [ClamAV guide](Antivirus/README.md) · [Changelog](CHANGELOG.md)
- [Architecture audit](docs/ARCHITECTURE_AUDIT.md) · [Roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Security model](docs/SECURITY_MODEL.md) · [Compatibility](docs/COMPATIBILITY_MATRIX.md)
- [Development workflow](docs/DEVELOPMENT_WORKFLOW.md) · [Backup guide](docs/BACKUP_AND_CHECKPOINTS.md)

## Roadmap

A graphical dashboard, broader storage analysis, stronger removal attribution, a central restore interface, an embedded offline AI assistant and improved packaging remain planned. **No AI model or inference runtime is included.** See the roadmap for implementation and verification status.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. For bugs, [open an issue](https://github.com/gaibkhanov/REMNEXA/issues) with versions, reproduction steps and expected/actual results. Remove private paths, credentials and sensitive log content before posting. Report vulnerabilities through [SECURITY.md](SECURITY.md).

## Support the project

Donations are optional. You can support development through the [PayPal donation page](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr).

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-0070BA?logo=paypal&logoColor=white)](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr)

Bug reports, translations and code contributions also help.

## License

The REMNEXA frontend and IPC transport use the [MIT License](LICENSE). The optional native adapter in `Antivirus/Workers` is **GPL-2.0-or-later** with its own license notices. Optional third-party components retain their own terms; see [third-party notices](docs/THIRD_PARTY_NOTICES.md).
