[English](WINDOWS_LAUNCHER.md) | [Deutsch](WINDOWS_LAUNCHER.de.md)

# Windows launcher and distribution preview

This feature branch adds a native x64 Win32 launcher and a separate end-user package for the existing 2.2.0 application. It does not publish or replace the stable v2.2.0 source release. The launcher and package are unsigned previews.

## Source and user layouts

Previously, the source checkout and end-user copy exposed six CMD entry points, the compatibility PowerShell wrapper, developer tools/tests and local backup folders together. The source retains compatible names; the user package has one entry point:

```text
Source checkout                 End-user package
REMNEXA.ps1                     REMNEXA-2.2.0/
REMNEXA.cmd + compatibility       REMNEXA.exe
Core/ Antivirus/ config/          app/
src/Launcher/                      REMNEXA.ps1
assets/icons/                      Core/ Antivirus/ config/
locales/                           assets/ locales/ LICENSE
scripts/ tests/ tools/             runtime/ (included in Complete)
docs/ examples/                   README.txt
```

Core, Antivirus and config stay at their existing source locations: they and the test fixtures rely on working relative imports, and moving them under src solely for appearance would add migration risk. The runtime package isolates those same dependencies under app without changing their relationships. src contains the new launcher; scripts contains launcher/icon/distribution builds. Examples is renamed to examples with references updated. Backups are moved intact to a sibling backup area, with local before/after SHA-256 manifests; they are not deleted or tracked.

REMNEXA-Antivirus.cmd, REMNEXA-Autostart.cmd, REMNEXA-Deinstallation.cmd and REMNEXA-Dienste.cmd forward to the central source entry. Programm-Entferner.cmd/.ps1 remain compatibility routes. These wrappers are excluded from the end-user package, as are tests, tools, scripts, Git metadata, backups and logs. All workspaces remain in the main menu.

## Native launcher

The MIT-licensed C source uses Win32 APIs directly. It has no .NET, C runtime, Python or Node dependency. Its manifest requests asInvoker. It launches PowerShell directly, preserves Windows argument quoting and child exit codes, uses the executable directory as working directory, and never sets ExecutionPolicy or requests elevation. Existing operation-specific application confirmations remain.

Runtime selection probes a stable PowerShell 7.5+ in runtime/pwsh.exe first, standard Program Files locations next, then all absolute PATH directories. It ignores empty/relative PATH entries. Invalid or incompatible candidates are skipped. Hidden probes have a fifteen-second deadline to allow cold runtime initialization; no additional interactive console is created. Normal execution uses one inherited console. --diagnose returns machine-readable selection information without running the app or changing settings.

The icon preserves the existing official PNG artwork, trims only transparent margin for readability and supplies 16/24/32/48/64/128/256-pixel PNG frames in an ICO resource. Explorer uses the embedded icon; classic console windows receive the small/large icon. Windows Terminal controls its own taskbar identity, so a custom taskbar icon is not guaranteed there. Future shortcuts/installers can use assets/icons/remnexa.ico or the EXE resource. No signing certificate is available.

## Reproduce the build

The default distribution is now **Complete**, with the pinned PowerShell and ClamAV versions in `config/bundle-components.json`. Maintainers run `scripts/Prepare-CompleteBundle.ps1` first: it downloads official HTTPS archives, verifies pinned SHA-256 values and extracted runtime bytes, uses FreshClam in an isolated cache, and checks all three signature databases. An optional `-SignatureSeedPath` can seed that cache with existing official database files; it never edits the installed engine or its database. Network attempts have fixed timeouts and bounded retries.

`scripts/Build-Release.ps1` then includes PowerShell, portable ClamAV and its required DLLs, verified signatures, upstream notices and the matching ClamAV source archive under `app/licenses/clamav/`. A missing component, changed hash or signature preparation older than 24 hours fails the Complete build. Runtime bytes are checked again after copying. Local FreshClam state/logs, developer paths, debug symbols, linker libraries and headers are excluded. The generated FreshClam configuration is relative, so moving the extracted folder does not bind it to the build machine. Signature timestamps are preserved in the ZIP; other timestamps remain normalized.

```powershell
./scripts/Prepare-CompleteBundle.ps1
./scripts/Build-Release.ps1 -OutputDirectory ./dist/complete
# Explicit developer-only build without bundled antivirus:
./scripts/Build-Release.ps1 -Distribution Standard -OutputDirectory ./dist/standard
```

CI uses an explicitly named **Standard developer preview** to test packaging without fetching production signature databases on shared runners. It is not the Complete user download. Complete candidates need local verification from the extracted ZIP with an empty PATH, the bundled runtime and databases, and actual harmless scans before publication. PowerShell and ClamAV are pinned to the latest stable versions verified when these pins were updated; future upstream releases require a pin refresh and retesting.

Use Windows 11 x64 (client build 22000+), PowerShell 7.5+, Git and the pinned Zig 0.15.2 toolchain:

```powershell
./scripts/Install-LauncherToolchain.ps1
./scripts/Build-Launcher.ps1
./scripts/Build-Release.ps1 -Distribution Standard
# Optional trusted PowerShell payload, including its license/notices:
./scripts/Build-Release.ps1 -Distribution Standard -OutputDirectory ./dist/with-runtime -RuntimePath ./runtime
```

The explicit toolchain installation downloads only the official Zig archive and verifies its pinned SHA-256. It does not install globally or alter PATH. The toolchain is developer-only and excluded from distributions. Zig is MIT; see [launcher build notices](../src/Launcher/THIRD_PARTY_NOTICES.txt). The PowerShell/ClamAV license boundaries remain in [third-party notices](THIRD_PARTY_NOTICES.md). The Standard commands above omit ClamAV; the default Complete build includes its verified runtime and databases.

Build from a clean committed checkout. Complete output defaults to `dist/windows-x64/REMNEXA-2.2.0` and `REMNEXA-2.2.0-complete-windows-x64-preview.zip` plus a SHA-256 sidecar. Existing outputs are not overwritten. The manifest records the source commit and every copied file hash. ZIP timestamps are normalized except signature database dates, which preserve their real age; unsigned PE timestamps are normalized. Reproducibility requires identical source, compiler, component archives and database snapshot, including database dates. The icon can be regenerated with scripts/New-ApplicationIcon.ps1 using Windows System.Drawing; it is format conversion of existing artwork, not new branding.

## Authenticode signing

`Build-Release.ps1` can sign the staged launcher and all application PowerShell scripts/modules/manifests before generating file hashes and the ZIP. Third-party runtime files retain their upstream signatures. Signing requires an already installed, currently valid code-signing certificate with its private key, a trusted and revocation-verifiable certificate chain, and Microsoft SignTool from the Windows SDK on the signing machine. These are developer requirements, not end-user dependencies.

```powershell
./scripts/Build-Release.ps1 -OutputDirectory ./dist/signed-preview `
    -SigningCertificateThumbprint '<40-character certificate-store thumbprint>' `
    -SignToolPath '<Windows SDK x64 signtool.exe>'
```

The default RFC 3161 timestamp endpoint is `https://timestamp.digicert.com`; another HTTPS endpoint can be specified with `-TimestampServer`. SHA-256 signatures and timestamps are required. Every signed file must pass SignTool verification and Windows Authenticode validation with the selected signer and a timestamp. Missing/expired/untrusted certificates, an untrusted signing tool, missing timestamps or signing failures stop the build; a partly signed staging directory is discarded. No private key is exported, no self-signed certificate is generated or installed, and trust/policy settings remain unchanged. Certificate thumbprints identify a public certificate and are not passwords.

The manifest sets `Signed` only after successful verification and records the public signer thumbprint, algorithm, timestamp endpoint and verified file count. Signing and timestamping change bytes, so package hashes are computed afterwards; signed packages are not byte-reproducible. Signatures establish publisher identity and integrity, but do not guarantee SmartScreen reputation or certify malware detection quality.

**Current delivery remains unsigned:** no code-signing certificate with private key or Windows SDK SignTool was available on the validation machine. Signing safeguards are covered by isolated regression tests using mocks; a real CA-backed signature/timestamp has not been tested. The existing unsigned preview remains usable. No stable release is created or replaced by this build.

## Verification and limits

Launcher regression checks cover PE/CLR metadata, icon resolutions, source/package layouts, Unicode and spaces, argument metacharacters, runtime absence/corruption, no elevation/policy override, exit codes and compatibility routes. User-package tests check allowlisted contents, per-file hashes, six languages, module/license dependencies and real application self-tests through the EXE. Existing Antivirus/navigation tests remain applicable.

The native launcher and direct PowerShell entry require Windows 11 or newer (client build 22000+). Windows 10, older Windows versions and Windows Server are rejected before runtime discovery or application initialization. The launcher queries RtlGetVersion; the script checks the OS version and client product type. The compatibility manifest GUID is shared with Windows 10 and does not replace this build check. Failure to determine a supported client is rejected. This minimum applies to current development builds; existing published artifacts remain unchanged.

The preview does not certify SmartScreen reputation or every supported Windows 11/Terminal variant. Complete includes the components needed for offline scans; future updates require internet. Downloaded scripts may be blocked by a user's execution policy; the launcher reports failure instead of bypassing that policy. Review package contents and independent backups before system changes. Stable releases are not modified by these build scripts.

### Complete validation — 24 November 2026

The extracted Complete ZIP from source commit `9fe63cb` passed the per-file manifest checks and has only `REMNEXA.exe`, `README.txt`, `app/` and `runtime/` at the top level. Its size is 337,427,216 bytes. PowerShell **7.7.0**, ClamAV **1.5.5** and **3,642,950 signatures** are included; the FreshClam snapshot was verified on the same day. Original licenses, component notices and matching ClamAV source accompany the bundle.

`tools/Test-CompletePackage.ps1` ran from a space-containing extraction path, without elevation, with empty PATH, installed-runtime discovery redirected to an absent directory, and an unavailable HTTP proxy. All **12 application self-tests** passed. The real application API scanned **8 harmless files**, confirming complete coverage; a separate harmless custom hash signature produced the expected finding and ClamAV exit code 1. The test used only the packaged runtime/engine/databases, requested no updates and performed no automatic quarantine. The network adapter was not disabled; this verifies local scan operation rather than a physically disconnected machine.

The default Auto backend safely falls back to `clamscan` for bundled ClamAV 1.5.5. The reusable native adapter is currently validated only for 1.5.4; this Complete package does not claim native-worker acceleration for 1.5.5 or downgrade the engine.

The full local suite passed **272 tests** on PowerShell 7.7.0, and the subsequently added module-import regression passed separately. GitHub Actions for `9fe63cb` passed **260 tests** with **13 Windows 11 client tests excluded** on the Server runner; source packaging, Standard packaging and static analysis also passed. Local parser/PSScriptAnalyzer error checks covered **128 PowerShell files**. These results do not establish every hardware/Windows variant, real-malware detection quality or SmartScreen reputation. The package remains **unsigned** and is not a new stable publication.

### Historical launcher-only validation (before Complete)

Recorded local validation: **216 tests passed, 0 failed, 0 skipped** (Pester 5.7.1, PowerShell 7.6.9); the four package tests were repeated successfully after packaging fixes. Syntax and PSScriptAnalyzer error gates passed on **112 PowerShell files**. Two clean builds without an optional runtime produced byte-identical ZIPs. The bundle with PowerShell 7.6.9 has **738 files**, verified hashes, complete runtime licenses/notices and **12 passing application self-tests with installed-runtime discovery disabled**, without elevation. The redundant upstream preview CMD alias is excluded. A real Windows-shell launch shared one console between launcher and PowerShell and exited through the main menu; Windows shell icon extraction also succeeded. This records the available Windows 11 host, not a full Windows compatibility matrix.
