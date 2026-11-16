# Security policy

REMNEXA is a Windows maintenance utility that can remove applications, files, registry entries, services or scheduled tasks after user selection. Review every preview and keep backups of important data. A restore point cannot reverse every external uninstaller or residual cleanup operation.

## Reporting a vulnerability

Please do not publish sensitive exploit details in a public issue. If GitHub private vulnerability reporting is enabled, use the repository's **Security → Report a vulnerability** form. Otherwise, contact the repository maintainer through a private GitHub channel and share only the minimum details needed to reproduce the issue.

Include the affected REMNEXA version, Windows version, PowerShell version, impact and safe reproduction steps. Do not attach personal logs or secrets.

## Supported versions

The current documented baseline is REMNEXA 2.1.3 on Windows 10/11 with PowerShell 7.5 or newer. The 3.0 roadmap is in progress and has no released version yet.

For current controls and known audit gaps, see [the security model](docs/SECURITY_MODEL.md). ClamAV is an optional on-demand scanner and is not a replacement for Microsoft Defender or real-time endpoint protection.
