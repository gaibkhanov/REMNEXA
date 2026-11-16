# REMNEXA

**More control over your Windows PC.**

REMNEXA is an open-source Windows maintenance utility with a multilingual terminal interface. Uninstall supported applications, review leftover traces, manage startup entries, inspect your system and optionally run local ClamAV scans.

Review what REMNEXA finds and choose which supported changes to make. Cleanup previews, confirmations and structured logs help you understand each operation.

**Windows 10 / 11 · PowerShell 7.5+ · MIT License · Six languages**

> **Development build: 2.2.0.** Available on [`feature/2.2.0-development`](https://github.com/gaibkhanov/REMNEXA/tree/feature/2.2.0-development). This is not a published stable release. The default `main` branch may contain an earlier version.

---

## ✨ Features

### 🗑️ Application Uninstaller

Remove supported desktop and Microsoft Store applications, then review the traces they may leave behind.

- Scan for potentially related files, folders and Registry entries.
- Identify potentially related services and scheduled tasks.
- Preview detected leftovers before choosing cleanup.
- Review removed items, failures, intentionally retained items and remaining traces.
- Keep Windows-managed package files protected from generic manual deletion.

Detected traces are cleanup candidates, not proof that every item is safe to delete. Review the preview before continuing.

### 🚀 Startup Manager

Review supported entries configured to launch with Windows.

- Inspect entry names, commands, locations and scope.
- Disable and restore supported startup entries.
- Preserve backups and history for supported startup changes.

### 🖥️ System Overview & Maintenance

Inspect useful Windows information and access selected maintenance tools.

- Windows version, build and architecture.
- CPU load and memory usage.
- Fixed-drive storage information.
- Running Windows services and startup entries.
- Optional service and antivirus-status checks.
- Selected Windows repair and maintenance tools.

The system overview is **read-only**. Opening it does not automatically optimize or change Windows settings. The current interface is terminal-based; a graphical dashboard is planned.

### 🛡️ Optional Antivirus Scanning

Integrate ClamAV for local, on-demand malware scanning.

- Set up supported ClamAV components using validated downloads.
- Update signature databases when an internet connection is available.
- Run manual scans and review detection results.
- Use supported quarantine and restore operations with explicit warnings.

Local scanning does not require a cloud API key. Initial setup and signature updates require internet access; scans can run offline once the engine and signatures are available.

**REMNEXA is not a real-time antivirus and does not replace Microsoft Defender or your installed security software.** Detections can be false positives; review findings before taking action.

### 🌍 Multilingual Interface

Six interface languages are available:

🇩🇪 German · 🇬🇧 English · 🇪🇸 Spanish · 🇫🇷 French · 🇷🇺 Russian · 🇹🇷 Turkish

Language resources are stored separately from application logic, with a German fallback.

---

## 📥 Installation

### Requirements

- Windows 10 or Windows 11; see the [compatibility matrix](docs/COMPATIBILITY_MATRIX.md) for verification limits.
- PowerShell **7.5 or newer**, or a compatible portable runtime supplied with a distribution. Windows PowerShell 5.1 cannot run REMNEXA.
- Administrator approval for operations requiring elevated access. REMNEXA explains the reason before opening the Windows permission prompt.

### Run the 2.2.0 development version from source

Download the ZIP from the [2.2.0 development branch](https://github.com/gaibkhanov/REMNEXA/tree/feature/2.2.0-development), or clone that branch:

```powershell
git clone --branch feature/2.2.0-development https://github.com/gaibkhanov/REMNEXA.git
Set-Location REMNEXA
.\REMNEXA.cmd
```

Alternatively, start the application directly with PowerShell 7.5+:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1
```

The launcher uses `runtime\pwsh.exe` when it is bundled; otherwise it looks for `pwsh.exe` in your system's `PATH`.

**The source repository does not include the portable PowerShell runtime, ClamAV binaries or signature databases.** Install PowerShell separately for a source checkout. ClamAV is optional and has its own setup requirements; see the [ClamAV guide](Antivirus/README.md). A new Windows installer is not available in this development build.

---

## 🔒 Safety First

REMNEXA makes sensitive operations visible and asks before supported interactive changes.

- Preview cleanup candidates before removal.
- Confirm destructive actions explicitly in the interactive workflow.
- Block protected Windows components by default.
- Request elevated access when required, with an explanation beforehand.
- Attempt to create restore points for supported write operations and verify that Windows created a new point.
- Keep structured logs for troubleshooting and review.
- Explain skipped Windows-managed files and access failures without taking ownership or overriding their access permissions.

**Some changes cannot be fully reversed.** Restore points and supported configuration backups do not guarantee complete recovery, especially after uninstalling third-party software. Review every deletion and keep independent backups of important files. If a new restore point cannot be confirmed, review the warning before choosing whether to continue without it.

Personal folders are excluded from the default leftover scan. The optional extended scan can include personal files and requires particular care.

Service and antivirus checks are snapshots. A stopped demand-start service is not automatically broken. Defender can stand down when another antivirus is registered, but registration alone does not confirm active real-time protection. Status messages do not prove that an uninstall caused a Windows problem.

---

## 🆕 What's New in 2.2.0?

Version 2.2.0 builds on the 2.1.3 baseline with maintenance, safety and usability improvements:

- HTTPS and SHA-256 validation for supported ClamAV downloads.
- Staged ClamAV installation and configuration-recovery handling.
- Additional cleanup-path validation, including linked-path checks and protection for Windows-managed package files.
- Clearer results for skipped, failed and remaining traces, including Registry deletion failures.
- Completion at 100% before the optional system-status check.
- Context-aware service and antivirus messages, without duplicate Defender warnings.
- Action-specific administrator explanations.
- Next/previous page options shown only when those pages exist.
- One visible exit choice per prompt: 0 where it already exits, otherwise X for direct exit.
- Modular core components, six external language resources and a read-only system overview.
- Expanded automated regression coverage.

**Verification:** the application baseline passed **79 local Pester tests** and **12 self-test checks**. These are local results, not a claim of a complete Windows compatibility matrix or a verified GitHub Actions run. Known limitations, analyzer warnings and untested scenarios are recorded in the [2.2.0 development report](docs/VERSION_2.2.0.md) and [development workflow](docs/DEVELOPMENT_WORKFLOW.md).

**Release status:** development build, not a published stable release.

---

## 🗺️ Roadmap

REMNEXA is being developed incrementally toward a broader Windows maintenance platform.

Planned work includes:

- A graphical system dashboard.
- More advanced disk and storage analysis.
- Enhanced application-removal workflows.
- Improved backup and recovery tools.
- A locally integrated, offline AI assistant.
- A simplified Windows installer.

These are future capabilities, not completed features of this development build. No local AI model or inference runtime is included.

---

## 📖 Documentation

- [Detailed German user guide](README-Programm-Entferner.txt)
- [ClamAV integration](Antivirus/README.md)
- [2.2.0 development report](docs/VERSION_2.2.0.md)
- [Changelog](CHANGELOG.md)
- [Development roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Compatibility information](docs/COMPATIBILITY_MATRIX.md)
- [Architecture audit](docs/ARCHITECTURE_AUDIT.md)
- [Development workflow](docs/DEVELOPMENT_WORKFLOW.md)

Official references: [Microsoft PowerShell](https://learn.microsoft.com/powershell/) and [ClamAV](https://docs.clamav.net/).

---

## 🤝 Contributing

Contributions, bug reports and suggestions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change.

For a bug report, [open a GitHub issue](https://github.com/gaibkhanov/REMNEXA/issues) with the REMNEXA version, Windows and PowerShell versions, steps to reproduce, and expected versus actual behavior.

Remove private system information, personal file paths, credentials and sensitive log data before posting a public report. For security vulnerabilities, follow [SECURITY.md](SECURITY.md).

---

## ❤️ Support the Project

REMNEXA is an open-source project developed to help Windows users maintain and manage their computers.

If you find it useful, you can support continued development through the [PayPal donation page](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr).

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-0070BA?logo=paypal&logoColor=white)](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr)

Donations are optional. Reporting bugs, improving translations and contributing code also help.

---

## 📜 License

REMNEXA is licensed under the [MIT License](LICENSE).

Optional third-party components, including ClamAV and PowerShell, retain their own licenses and redistribution requirements. Their licensing terms are independent of REMNEXA's MIT License.

---

**REMNEXA — More control over your Windows PC.**
