[English](SECURITY.md) | [Deutsch](SECURITY.de.md)

# Security policy

REMNEXA can invoke uninstallers and modify files, Registry data and supported system settings. Treat it as a maintenance tool with sensitive operations, not as a security boundary or antivirus replacement.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting **if enabled** under the repository's Security tab. If it is unavailable, open a minimal issue requesting a private reporting channel; do not include exploit details, credentials, personal logs or private paths publicly. No private contact address or guaranteed response time is designated here.

Include the affected version/commit, sanitized reproduction steps, impact and a proposed mitigation if available. Use synthetic data. Do not test exploitation on systems without authorization.

## Support status

The current 2.2.0 branch is a development build. There is no formal long-term support or security response SLA. Report issues against current development and identify older affected releases where known. An existing release is not automatically a security-certified build.

## Boundaries and known limits

- Cleanup previews and confirmations reduce accidental changes but do not prove that every match belongs to an application.
- Reparse-point checks narrow, but do not eliminate, filesystem time-of-check/time-of-use races.
- Restore points and supported configuration backups do not guarantee complete recovery.
- ClamAV is optional on-demand scanning, not continuous protection.
- AI contracts exist; no inference runtime/model is shipped. Future model output must remain untrusted advice.
- Review any registered uninstaller command before trusting its origin.

See the [security model](docs/SECURITY_MODEL.md) and [development report](docs/VERSION_2.2.0.md) for implemented controls and open validation work.

## Sharing diagnostics

Redact user names, account identifiers, absolute personal paths, tokens, file content and sensitive program/command details. Do not upload malware or quarantine samples in public issues. Keep upstream third-party security updates separate from REMNEXA's application version.
