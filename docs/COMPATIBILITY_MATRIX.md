# REMNEXA compatibility matrix

Status means what the current source documents or enforces, not what has been tested across every machine.

| Dimension | Current baseline | Evidence | Validation status |
|---|---|---|---|
| Operating system | Windows 10 and Windows 11 | `README.md` | Declared; broad version/build matrix not run |
| PowerShell | PowerShell 7.5 or newer | `README.md`, `REMNEXA.ps1` and module `#requires` | Parser checks passed under Windows PowerShell 5.1, but runtime requires 7.5+ |
| Windows PowerShell 5.1 | Unsupported for app execution | `#requires -Version 7.5` | Parser-only check is not runtime support |
| Architecture | x64 not explicitly enforced by the launcher or source metadata | Launchers and inventory | Not verified; ClamAV package architecture should be detected before install |
| UI | Console/terminal interface | Main script uses `Write-Host`/`Read-Host`; no WPF/WinForms references found | No GUI accessibility/resizing matrix exists |
| System snapshot | On-demand Windows CIM queries for OS, CPU load, memory and fixed disks; visible in the Home menu as a read-only overview | `Core/SystemSnapshot.psm1`, `REMNEXA.ps1` | Synthetic tests and live Windows CIM query passed; interactive rendering inside a real console remains unverified |
| Portable runtime | Optional `runtime\pwsh.exe`; launcher prefers it when present | `REMNEXA.cmd`, README, `.gitignore` | Runtime version and package hashes not verified in a distributable build |
| ClamAV | Optional, on-demand integration; setup/signature update needs Internet | `Antivirus/README.md`, module source | Offline scan only possible after engine and signatures are already present; no complete offline package verified |
| Languages | German, English, Spanish, French, Russian, Turkish | Six keyed UTF-8 JSON resources in the audit snapshot; original source used arrays in `REMNEXA.ps1` | Resource completeness is covered by Pester and `-SelfTest`; console rendering across hosts is not verified |
| Local AI | None in baseline | Source inventory | Not implemented; no model/runtime dependencies or offline inference claim |
| Installer/update | No installer or release build workflow found | Source inventory | Not implemented/validated |
| Tests and static analysis | Audit snapshot includes a Windows quality workflow; locally 34 Pester 3.4.0 cases and PSScriptAnalyzer 1.24.0 are available | `tests/`, `tools/Invoke-RemnexaTests.ps1`, `.github/workflows/quality.yml`, `docs/STATIC_ANALYSIS_BASELINE.md` | Local suite passes under PowerShell 7.6.9; pinned Pester 5.7.1/GitHub Actions not run |
| Licensing | REMNEXA MIT; ClamAV and included upstream components have separate terms | `LICENSE`, `Antivirus/README.md`, ClamAV license files in ignored local payload | Redistribution review needed for any bundled binaries or model weights |

## Compatibility targets for 3.0

- Keep the current Windows 10/11 and PowerShell 7.5+ baseline until tests demonstrate a safe change.
- Detect 32/64-bit runtime and OS architecture before installing native dependencies.
- Run automated functional tests on supported Windows 10 and Windows 11 images with both non-elevated and elevated test accounts. Destructive checks must stay inside disposable test fixtures/VMs.
- Verify all six existing locales, including non-Latin text in Windows Terminal and standard console hosts.
- Measure performance on a CPU-only low-memory machine before making AI or hardware promises.
- Treat offline compatibility as feature-specific: core console tools, ClamAV engine/signature availability and future AI model availability are separate states.
