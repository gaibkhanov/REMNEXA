# REMNEXA

REMNEXA is a Windows utility for removing applications, reviewing leftover traces, managing startup entries, checking selected Windows settings, and optionally running local ClamAV scans.

**Current version:** 2.1.3  
**Platform:** Windows 10/11  
**PowerShell:** 7.5 or newer  
**License:** MIT; third-party components retain their own licenses.

## Start

1. Install PowerShell 7.5 or newer, or use the optional portable PowerShell runtime in a packaged distribution.
2. Run `REMNEXA.cmd`. The launcher prefers `runtime\pwsh.exe` when present and otherwise uses `pwsh.exe` from `PATH`.
3. For a direct source run, use `pwsh -NoProfile -File .\REMNEXA.ps1`.

The source repository excludes the portable runtime and ClamAV engine/signature files. The optional ClamAV integration can fetch the official Windows engine and signatures when the user selects its setup/update actions. Those third-party files are not redistributed in this repository.

## Main features

- Uninstalls selected Windows applications and scans for related files, folders, registry entries, services, and scheduled tasks.
- Shows the scan results before cleanup, asks before deleting traces, then reports removed, failed, and remaining items.
- Offers optional system-integrity checks and keeps a JSON log for each run.
- Manages startup entries with a backup and restore path.
- Lists running Windows services and provides selected Windows maintenance tools.
- Provides optional on-demand ClamAV scans and quarantine workflows; it is not a real-time antivirus or a replacement for Microsoft Defender.
- Supports German, English, Spanish, French, Russian, and Turkish interface text.

## Safety and scope

REMNEXA requests elevation only for actions that need it. It previews selected changes and asks for confirmation before removal or system changes. Protected Windows components are blocked by default. Restore-point creation is attempted before write operations; if it cannot be created, the user must explicitly choose whether to continue without one.

Personal folders are not searched by default. Enabling the optional personal-file scan can permanently delete matching files after confirmation. Review each preview and keep backups of important data.

Integrity-check warnings are informational. A stopped or manually started Windows service is not automatically evidence of a fault. Antivirus detections can also be false positives; review findings before taking action.

## Documentation

- [Detailed German guide](README-Programm-Entferner.txt)
- [ClamAV integration guide](Antivirus/README.md)
- [Interactive ClamAV workflow example](Examples/Invoke-AntivirusWorkflow.ps1)
- [Official PowerShell documentation](https://learn.microsoft.com/powershell/)
- [Official ClamAV documentation](https://docs.clamav.net/)

## Donations

PayPal donation link: https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr

## Third-party components

The optional ClamAV integration downloads ClamAV from the official Cisco Talos release channel. ClamAV is a separate project with its own license and terms. PowerShell is also distributed under its own license. This repository contains REMNEXA source and does not include those third-party binaries or signature databases.

## License

REMNEXA is released under the MIT License. See [LICENSE](LICENSE). Third-party components remain subject to their respective licenses.

