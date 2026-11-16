[English](ARCHITECTURE_AUDIT.md) | [Deutsch](ARCHITECTURE_AUDIT.de.md)

# Architecture audit

**Scope:** first-party source for the 2.2.0 development build, derived from the 2.1.3 baseline. This is a source review with targeted tests, not a complete independent security audit.

## Current structure

| Area | Responsibility |
| --- | --- |
| `REMNEXA.cmd`, compatibility launchers | Select a suitable PowerShell runtime and launch the application. |
| `REMNEXA.ps1` | Console navigation, program inventory, uninstall/cleanup orchestration and Windows tools. |
| `Core/` | Localization, settings, logging, processes, permissions, results, system snapshots, path safety, menu and security assessment. |
| `locales/` | Six JSON language resources; 282 keys per language at the recorded baseline. |
| `Antivirus/` | Optional ClamAV setup, scanning, signatures and quarantine. |
| `config/`, `assets/`, `Examples/` | Default configuration, visual assets and usage examples. |
| `tests/`, `tools/`, `.github/workflows/` | Regression tests, local checks, backup tooling and CI configuration. |

The console dispatcher remains substantial. Compatibility wrappers preserve existing calls while selected responsibilities move into modules. There is no full graphical application or universal task scheduler.

## Operation boundaries

Application inventory includes registered desktop uninstallers and supported Appx packages. The pipeline previews candidates, obtains required approvals, attempts a verified restore point, invokes the registered uninstaller, rescans, offers separate leftover cleanup, verifies remaining traces and writes logs/history. Optional status assessment follows the completed removal.

Registry, filesystem, registered commands, services, scheduled tasks and vendor package tools are sensitive boundaries. Some matching is still name-based. No universal publisher/product/shared-dependency attribution has been validated.

## Confirmed defects addressed in 2.2.0

| Earlier defect | Current control |
| --- | --- |
| Optional source-package components failed self-test | Runtime and ClamAV engine absence is handled as optional. |
| Missing/malformed archive digest could allow installation | HTTPS plus matching SHA-256 required before extraction. |
| Replacement engine/configuration could leave partial setup | Staged installation, atomic config commit and rollback on commit failure. |
| Linked-path cleanup risk | Ancestor reparse-point checks at collection and before removal; uninspectable paths rejected. |
| Privacy restore trusted arbitrary input | Schema and fixed Registry allowlist validated before writes. |
| WindowsApps deletion produced avoidable access failures | Windows-managed package directories intentionally retained. |
| Registry exit code 1 counted as success | Failure accounting and successful-parent coverage separated. |
| Progress waited at 92% for optional status check | Save removal result and reach 100% before optional assessment. |
| Misleading service/duplicate Defender warnings | Contextual service and combined antivirus assessment. |
| Invalid paging and duplicate exit choices | Bounds checked; one advertised exit per prompt. |

These controls have targeted regression coverage; they do not prove every removal/recovery scenario.

## Remaining risks and improvement proposals

1. **High priority:** stronger ownership attribution and shared-resource handling before expanding cleanup.
2. **High priority:** comprehensive restore verification, non-success paths and isolated Windows integration coverage.
3. **High priority:** filesystem race remains between validation and use; path checks are not handle-based isolation.
4. **Medium priority:** large dispatcher, legacy wrappers and analyzer warning debt require gradual refactoring.
5. **Medium priority:** signature-update failure after engine installation is outside the installation transaction.
6. **Unimplemented:** full rollback center, GUI, packaged offline AI, complete installer and release validation.

## UI and dependency decision

Retain the PowerShell console during stabilization. Compare a Windows-native graphical option against startup time, memory, accessibility, packaging and migration effort before adopting it. No measured benefit currently justifies replacing the whole stack.

PowerShell and optional ClamAV remain separate dependencies. Development uses Pester and PSScriptAnalyzer. No AI runtime/model has been integrated or licensed for distribution. See [third-party notices](THIRD_PARTY_NOTICES.md).

See [roadmap](DEVELOPMENT_ROADMAP.md), [security model](SECURITY_MODEL.md), [compatibility](COMPATIBILITY_MATRIX.md) and [verification report](VERSION_2.2.0.md).
