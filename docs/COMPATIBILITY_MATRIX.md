[English](COMPATIBILITY_MATRIX.md) | [Deutsch](COMPATIBILITY_MATRIX.de.md)

# Compatibility matrix

**Target** does not mean **validated**. This matrix separates requirements and recorded local checks from release-level certification.

| Component/scenario | Target or requirement | Verification status |
| --- | --- | --- |
| Windows | Windows 10 / 11 | Development-host checks only; clean VM matrix pending. |
| Architecture | Windows x64 distribution | No complete x64 packaging/install matrix; ARM64 and 32-bit not validated. |
| PowerShell | 7.5+ | Recorded local tests on 7.6.9; minimum-version enforcement exists. |
| Windows PowerShell 5.1 | Unsupported for running the app | A successful syntax parse does not make it supported. |
| Source launcher | Bundled compatible runtime, otherwise `PATH` | Runtime optional and absent from source repository. |
| Pester | CI/local Pester 5.7.1 | rc.8: 204 local tests passed; its GitHub quality run passed. Final release CI is checked before publication. |
| PSScriptAnalyzer | 1.24.0 | Error gate passed on 106 PowerShell files for rc.8; historical analyzer failures remain in their original report. |
| Desktop/MSI removal | Registered supported uninstallers | Mocked/targeted coverage; vendor-wide integration pending. |
| Store/Appx removal | Supported current-user packages | Provisioning scope differs; full multi-user matrix pending. |
| Permissions | Unelevated navigation, explicit elevation when needed | Actual elevated native-worker launch tested on Windows 11; complete account/UAC matrix pending. |
| ClamAV | Optional supported Windows engine and signatures | Setup/validation tests do not certify every upstream build. |
| Offline use | Local tools with required components already present | Setup/updates and some Windows repairs need network/media; complete offline package not tested. |
| Languages | de, en, es, fr, ru, tr | Six-language key/placeholder parity tested; complete linguistic/accessibility review pending. |
| Local AI | Planned embedded runtime/model | Not implemented; no CPU/RAM/model benchmark. |
| Installer/portable release | Planned verified packages | Verified source ZIP/checksum; no 2.2.0 installer, Complete AI package or digital signature. |

## Release validation still required

Exercise fresh supported Windows installations, standard/admin accounts, locked/shared resources, cancelled UAC, restarts, failed repairs, interrupted updates and rollback in disposable VMs. Record exact Windows builds, hardware and component versions.

Scan lifecycle, CLI/native benchmarks and resource-limit records exist; see the release notes and linked benchmark reports. They do not establish universal speedups, startup/idle-memory targets or AI performance.

See [verification report](VERSION_2.2.0.md) and [roadmap](DEVELOPMENT_ROADMAP.md).

Current release scope and evidence: [REMNEXA 2.2.0](RELEASE_2.2.0.md).
