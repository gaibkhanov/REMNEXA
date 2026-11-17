[English](RELEASE_2.2.0_RC1.md) | [Deutsch](RELEASE_2.2.0_RC1.de.md)

# REMNEXA 2.2.0-rc.1

**Status: source release candidate, not a stable release.** Publication requires maintainer approval. No existing release is replaced. This candidate extends the [2.2.0 baseline](VERSION_2.2.0.md).

## Improvements

- Console clearing safely degrades when output is redirected or cursor APIs are unavailable. An extracted-package smoke test exposed this startup crash; a real home-menu/exit regression now covers it.

- A timed-out native process requests termination of its owned process tree. Cleanup waits at most five additional seconds; failure is reported instead of claiming success. Output draining also respects the timeout. This does not add a universal UI cancel button or guarantee control of detached/elevated processes.
- The Windows argument encoder preserves empty arguments.
- Source checkpoints exclude top-level Git metadata, generated packages and abandoned staging directories. The existing backup no-overwrite and SHA-256 checks remain.
- A clean-commit package builder includes tracked source only, checks paths, refuses existing outputs and verifies the resulting archive.
- The package contains a per-file manifest; a separate SHA-256 sidecar covers the ZIP. Verification reads the archive without extracting files and rejects changed/missing/unlisted content, invalid paths, duplicate names and incorrect expected hashes.
- The quality workflow builds and uploads the verified source archive as an artifact. It does not publish a GitHub release.

The interface displays `2.2.0-rc.1`. Existing uninstall, startup, Antivirus, navigation and language behavior is retained.

## Local verification

| Check | Result |
| --- | --- |
| Initial unchanged baseline, Pester 3.4.0 | 79 passed, 0 failed. |
| Candidate suite, Pester 3.4.0 / PowerShell 7.6.9 | 89 passed, 0 failed, 0 skipped. |
| Candidate suite, Pester 5.7.1 / PowerShell 7.6.9 | 89 passed, 0 failed, 0 skipped. |
| First-party syntax and analyzer error gate | 68 PowerShell files, 0 syntax errors, 0 analyzer errors. |

These are local results. Remote CI and a clean Windows 10/11 installation matrix are not implied. The remaining warning baseline is documented [separately](STATIC_ANALYSIS_BASELINE.md). Each generated artifact must pass package verification and an extracted application self-test before publication.

## Build and verify

For maintainers, from a clean committed checkout with Git and PowerShell 7.5+:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.1'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Output: `dist/REMNEXA-2.2.0-rc.1-source.zip` and its `.sha256` sidecar. The manifest records the source commit, version, file sizes and hashes; it contains no developer-machine path. Output files are never overwritten. Use another output directory for a second build. A builder requires Git; end users do not need Git to run an extracted package.

Obtain the expected archive hash from the trusted release channel. A checksum supplied alongside an untrusted package is not proof of authenticity. There is no digital signature.

## Run the candidate

Verify the archive, extract it into a new directory and launch `REMNEXA.cmd` inside its versioned folder. PowerShell 7.5+ must already be installed and available on `PATH`; the source package does not include the optional runtime, ClamAV engine/signatures or an AI model. Keep the previous version and independent backups. Restart running REMNEXA instances to load the new code.

For a diagnostic check from the extracted application directory:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
```

This checks selected capabilities, not complete recovery or security. Follow the [user guide](USER_GUIDE.md) for removal previews and confirmations.

## Deferred work and publication gate

No new installer, bundled-runtime distribution, model/runtime integration or digital signing is delivered. Windows VM coverage, live rollback, multi-user removal and complete offline distribution tests remain pending. Path races and heuristic leftover attribution remain known limits.

The source candidate can be considered for an explicitly labeled prerelease after artifact checks and approval. These checks do not qualify it as a stable release or as REMNEXA 3.0. See the [roadmap](DEVELOPMENT_ROADMAP.md).
