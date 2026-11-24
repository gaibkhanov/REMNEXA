[English](UPDATES.md) | [Deutsch](UPDATES.de.md)

# Updates and the start dashboard

Open **[U] Updates and versions** on the home screen or enter **/updates** at a prompt. This development feature does not publish a new stable release.

- Startup checks run separately and fetch metadata only. Successful checks are reused for 24 hours; unsuccessful attempts back off for five minutes. **[U]** inside the update center forces a new check. Offline status never means current protection.
- The dashboard reads local versions without launching a scanner or waiting for the network: running REMNEXA/PowerShell versions, ClamAV file version, main/daily/bytecode database versions and four recent saved activities.
- Installation requires confirmation. Return to the menus to keep working during downloads and verification. Enter refreshes the update-center snapshot. Percentages require an actual known download size. Completion notices appear at the next application prompt.
- **PowerShell:** verified official stable x64 ZIPs install beside the running runtime. Existing files remain unchanged. The launcher selects the prepared version on the next launch; the dashboard distinguishes active and prepared versions. Invalid, missing or non-newer selections fall back to the original runtime.
- **ClamAV/signatures:** prepare a separate copy using the existing HTTPS/hash/FreshClam routines. Active scans keep their files. Activation waits for the installation's scan lock, checks that the original databases did not change, and verifies the replacement. Failure restores the previous directory. A ten-minute activation wait expires without interrupting a scan. External/shared installations are not replaced by this bundle updater.
- **Update then scan:** the Antivirus menu can queue the requested interactive scan after a successful background update. Failure never starts that queued scan. Existing synchronous module APIs and targeted checks within a removal operation retain their contracts.
- **REMNEXA:** only a newer stable official release with a matching Complete x64 ZIP and official SHA-256 digest is installable. A source-only release is not an app update. All downloaded app files must pass their manifest checks. The complete new application is prepared separately; launch its displayed `REMNEXA.exe` to switch. Existing application files and independent scans remain in place. Missing compatible release assets are explained in the app.

Confirmed installations can finish after the main application exits; the exit message explains this. Owned startup metadata checks are stopped on exit. No Windows service, scheduled task, global installation, security exclusion or execution-policy override is created.

Progress/cache and limited update history remain local, scoped to the application directory. Failed operations have a `failure-<operation>.txt` diagnostic in the local update-cache directory. Personal scan paths are not transmitted to update endpoints. Online requests necessarily disclose connection metadata to official endpoints.

Validation uses isolated transport/metadata tests, directory rollback and database-change tests, real side-by-side PowerShell/launcher checks and existing Antivirus/navigation regressions. Harmless fixtures do not establish malware-detection quality or every Windows/hardware configuration. The package remains unsigned unless the separately documented trusted signing workflow succeeds.
