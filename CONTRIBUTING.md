[English](CONTRIBUTING.md) | [Deutsch](CONTRIBUTING.de.md)

# Contributing

REMNEXA welcomes fixes, translations, tests and documentation. Work from the current development branch; do not assume that `main` contains the newest development code.

## Before changing code

1. Read the [architecture audit](docs/ARCHITECTURE_AUDIT.md), [security model](docs/SECURITY_MODEL.md) and [workflow](docs/DEVELOPMENT_WORKFLOW.md).
2. Create a focused feature branch from the intended baseline.
3. Preserve existing features and language keys. Explain any necessary behavior change.
4. Add meaningful regression coverage for changed behavior, especially deletion, process execution, privilege handling and restore paths.
5. Keep destructive tests in isolated fixtures or disposable Windows VMs.

Never execute test uninstallations, broad deletion, live Registry restores or security-setting changes against a contributor's real environment.

## Checks

Use PowerShell 7.5+ from the repository root:

```powershell
pwsh -NoProfile -File .\tools\Invoke-RemnexaTests.ps1
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
```

Install compatible Pester and PSScriptAnalyzer modules in the development environment first. See the workflow for the CI pins and local verification limits. Report tool versions, test counts, failures and skipped cases. Do not present old baseline results as a new run.

For documentation-only changes, check relative links, language counterparts, examples, private information and release claims. Do not run destructive examples.

## Pull requests

Describe the problem, resulting behavior, tests and remaining limits. Keep unrelated changes separate. Do not include runtime binaries, signatures, model weights, backups, credentials, private logs or machine-specific paths. Review `git diff --cached` before pushing.

Use [SECURITY.md](SECURITY.md) for vulnerabilities. Public bug reports should include sanitized version/build information, reproduction steps and expected/actual behavior.

## Localization and licenses

Keep all six interface resources consistent. Maintain English and German documentation together, using reciprocal language links. Do not translate code identifiers or alter legal license text.

Check upstream licenses before adding dependencies or distributing binaries/models. The project's MIT license does not automatically apply to third-party components.

A development push is not release approval. Production publication requires successful validation and explicit maintainer approval.
