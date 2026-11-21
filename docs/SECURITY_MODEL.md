[English](SECURITY_MODEL.md) | [Deutsch](SECURITY_MODEL.de.md)

# Security model

Applies to the implemented 2.2.0 development source. Planned safeguards are not presented as completed controls. Vulnerability reporting: [SECURITY.md](../SECURITY.md).

## Assets and trust boundaries

Protect user files, shared program resources, Registry state, service/task configuration, quarantine integrity and diagnostic confidentiality.

Treat application names, registered uninstall commands, filesystem metadata, downloaded archives, restore records, logs and future AI output as untrusted input. A name match does not establish ownership. Elevation makes mistakes more damaging and is not a substitute for validation.

## Implemented controls

| Boundary | Current protection | Limit |
| --- | --- | --- |
| Privileges | Unelevated home menu; action-specific explanation before RunAs; cancellation paths | Elevation starts an elevated application process, not a separate privileged broker. |
| Cleanup | Preview/confirmation, protected-component defaults, WindowsApps exclusion, ancestor checks | Attribution remains partly heuristic; filesystem races remain. |
| Downloads | HTTPS and matching SHA-256 before ClamAV extraction | Trusted metadata/source is still necessary; not a universal signed-update framework. |
| Configuration | Schema checks, atomic replacement and read-back for supported settings | Not a backup of all Windows state. |
| Privacy restore | Validate supported Registry path/name/type allowlist before writes | No universal cryptographic authentication or transactional system restore. |
| Processes | Shared native-process adapter avoids shell invocation for its calls | Registered vendor uninstallers remain a trust boundary. |
| Native scanner | Private inherited pipes, non-elevated worker, restricted-token attempt, job limits and kill-on-close; no daemon TCP endpoint | Not a complete native-exploit sandbox. Ordinary/elevated parent tests passed; VM/HDD and broader Windows configurations remain open. See [worker validation](RELEASE_2.2.0_RC6.md). |
| Quarantine | Deliberate action, manifest/hash and no-overwrite checks on restore | Restoration can reintroduce malicious content. |
| Logging | Structured events and explicit outcome categories | Logs can expose sensitive paths or commands. |

A new restore point must be confirmed by Windows using a unique description. Failure or frequency throttling is not reported as success. Supported interactive flows can explicitly proceed without a new point; noninteractive operation must satisfy its safeguards or stop.

## AI boundary

`Core/AiContracts.psm1` bounds explicitly supplied facts and validates advisory outputs, rejecting command fields. **There is no model or inference runtime.** These contracts are groundwork, not demonstrated process isolation.

Future AI must have no shell, deletion, Registry mutation, service control or elevation authority. Recommendations must remain inert. Only reviewed rule-based functions may perform confirmed changes. System reports and model text must be handled as untrusted data; do not pass generated commands to a shell.

## Recovery and safe failure

Do not force protected paths writable or change ownership to clear residuals. Distinguish intentional skips, failures and remaining evidence. A failed Registry parent deletion must not silently suppress children as if it succeeded.

Staged ClamAV installation restores the previous engine on configuration-commit failure. Signature-update rollback, complete service/task/file recovery and a central restore center remain incomplete. Never promise full recovery from third-party uninstallations.

## Verification priorities

Targeted mock/fixture tests cover selected controls. Remaining work includes adversarial path races, shared resources, permission failures under real Windows accounts, interrupted operations, installer/uninstaller VMs and complete restore exercises.

No destructive test should run against live user data without explicit authorization. Read [compatibility limits](COMPATIBILITY_MATRIX.md) and [analysis baseline](STATIC_ANALYSIS_BASELINE.md) before interpreting test success as broad assurance.
