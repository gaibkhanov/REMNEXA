[English](RELEASE_2.2.0.md) | [Deutsch](RELEASE_2.2.0.de.md)

# REMNEXA 2.2.0

This source release promotes the tested rc.8 application to version 2.2.0. It combines the application-removal and maintenance foundation with the incremental improvements recorded in the [changelog](../CHANGELOG.md).

## Download and start

Download `REMNEXA-2.2.0-source.zip` and its `.sha256` file from the [v2.2.0 release](https://github.com/gaibkhanov/REMNEXA/releases/tag/v2.2.0). Extract the archive to a writable local folder. Use Windows x64 and PowerShell 7.5 or newer, then start `REMNEXA.cmd`. The launcher prefers a compatible runtime in `runtime/`, otherwise `pwsh.exe` on PATH. Source distributions do not include PowerShell, ClamAV executables or signature databases. Antivirus setup/updates require internet; installed signatures support offline scanning. Elevation is requested for operations that need it.

Verify the downloaded ZIP before extracting:

```powershell
$archive = './REMNEXA-2.2.0-source.zip'
$expected = ((Get-Content ($archive + '.sha256') -Raw).Trim() -split '\s+')[0]
if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or
    (Get-FileHash $archive -Algorithm SHA256).Hash -ine $expected) {
    throw 'Download checksum does not match.'
}
```

The release also supplies English/German notes. No installer, bundled runtime/engine, model weights, Windows service or digital signature is supplied. The source manifest records the exact Git commit and per-file SHA-256 values. Checksums detect corruption; obtain them from the trusted release page.

## Main changes

- Independent Antivirus scan window: keep using REMNEXA or choose to continue scanning after exiting the main application. Pause, resume, cancel and inspect findings; final results are stored locally.
- Explicit continue/cancel/back choices when exiting with an active scan. A paused scan resumes before confirmed continuation. Closing the scan window stops its scanner.
- Reusable restricted native ClamAV worker, CLI fallback, Eco/Balanced/Fast modes, bounded resources and incomplete-coverage reporting.
- Silent cached update checks, manual update choices and confirmed updates using existing safe download/staging/rollback controls.
- Clearer progress, conditional pagination, consistent exit controls and explanations before elevation in six interface languages.
- Cleanup path checks, protection of Windows-managed package files, more precise cleanup/service messages and tested source-package integrity checks.

Read [independent-scan behavior](INDEPENDENT_SCANS.md), [ClamAV guidance](../Antivirus/README.md), [security model](SECURITY_MODEL.md) and [third-party notices](THIRD_PARTY_NOTICES.md) before using advanced operations. Findings do not trigger automatic quarantine in background scans; REMNEXA does not replace real-time antivirus protection.

## Validation and scope

The unchanged functional rc.8 baseline passed **204 Pester tests**, **12 extracted-source self-tests** and the PowerShell syntax/PSScriptAnalyzer error gates. Its [GitHub quality run](https://github.com/gaibkhanov/REMNEXA/actions/runs/44929088151) also passed tests, static analysis, source build/verification and artifact upload. Final versioned source is checked again before publication; release notes identify the exact release CI run and package checksum.

Real ClamAV 1.5.4 CLI and private-worker scans each processed 2,501 harmless files with one custom hash-signature match, survived creator-process exit and saved complete results. Earlier records cover elevated launch, native job limits, constrained-memory admission, cache reuse, signature changes, cancellation and harmless archives. These checks do not prove malware-detection effectiveness or universal application-removal compatibility.

Recorded runtime tests use Windows 11 x64, SSD and 16 GB RAM with PowerShell 7.6.9. Windows 10, an actual 8 GB VM, HDD, the full account/UAC matrix and a malware lab remain unverified. Local AI, graphical dashboard, installer and Complete offline distribution remain planned. Existing filesystem check/access races and operation-specific rollback limits remain; back up important data independently. See the [compatibility matrix](COMPATIBILITY_MATRIX.md).

This stable source release is not completion of the REMNEXA 3.0 roadmap. Existing releases and tags remain unchanged.
