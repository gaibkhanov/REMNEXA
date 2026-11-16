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
| Pester | Local runner 3.4.0+; CI pinned 5.7.1 | 79 tests recorded on 3.4.0; 5.7.1 CI run not verified here. |
| PSScriptAnalyzer | 1.24.0 | Error gate passed; warnings remain and a full-run crash is recorded. |
| Desktop/MSI removal | Registered supported uninstallers | Mocked/targeted coverage; vendor-wide integration pending. |
| Store/Appx removal | Supported current-user packages | Provisioning scope differs; full multi-user matrix pending. |
| Permissions | Unelevated navigation, explicit elevation when needed | Simulated elevation tests; complete account/UAC matrix pending. |
| ClamAV | Optional supported Windows engine and signatures | Setup/validation tests do not certify every upstream build. |
| Offline use | Local tools with required components already present | Setup/updates and some Windows repairs need network/media; complete offline package not tested. |
| Languages | de, en, es, fr, ru, tr | 282 keys checked per language; complete linguistic/accessibility review pending. |
| Local AI | Planned embedded runtime/model | Not implemented; no CPU/RAM/model benchmark. |
| Installer/portable release | Planned verified packages | No validated 2.2.0 installer, Complete AI package or signed release. |

## Release validation still required

Exercise fresh supported Windows installations, standard/admin accounts, locked/shared resources, cancelled UAC, restarts, failed repairs, interrupted updates and rollback in disposable VMs. Record exact Windows builds, hardware and component versions.

No measured startup, idle-memory, scan or AI performance targets have been established. Avoid fixed speedup or resource-use claims until reproducible benchmarks exist.

See [verification report](VERSION_2.2.0.md) and [roadmap](DEVELOPMENT_ROADMAP.md).
