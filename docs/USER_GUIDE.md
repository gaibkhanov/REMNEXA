[English](USER_GUIDE.md) | [Deutsch](USER_GUIDE.de.md)

# User guide

Applies to the **2.2.0 development build**. See the [project README](../README.md) for installation and the [compatibility matrix](COMPATIBILITY_MATRIX.md) for verification limits.

## Start and permissions

Launch `REMNEXA.cmd`, or run:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1
```

PowerShell 7.5+ is required. The home menu starts without an administrator request. Before requesting elevated access for an operation or the Antivirus workspace, REMNEXA explains why. Press Enter to open the Windows prompt; choose Yes to allow elevation or No to decline. In the explanation, 0 returns and X exits. An already elevated process does not request elevation again.

Administrator approval starts an elevated application process; it does not grant unlimited permission to change everything. Separate action confirmations still apply.

## Navigation and exit

Read the choices shown at the current prompt. A number from another screen does not select an action on this screen.

- Where **0 means Exit**, it is the only advertised exit choice.
- Where **0 means Back**, or the input accepts ordinary text, **X** offers direct exit.
- `x` and `exit` remain exit aliases. Session logging is attempted before closing.
- Return choices take you to the preceding function or program list when offered; returning to a program list retains its page and filter.
- Program and startup lists show next/previous pages only when they exist. Available page commands are shown; unavailable commands explain why they cannot be used.

The exit option applies while REMNEXA waits for input. It does not add a cancellation mechanism to a running external uninstaller, scan, repair command or Windows permission dialog. Wait for critical write operations to finish; forcing the window closed can interrupt them.

## Processing status

In candidate rc.2, known work shows processed/total items and their percentage. During Antivirus scanning, the counter uses ClamAV file replies after target inventory. Percentages do not estimate remaining time. Discovery, engine loading and Windows calls without a measurable total show the phase and an indeterminate bar. Native-process heartbeats update elapsed time even during silent work; a single synchronous Windows call may not refresh until it returns.

Cyan means processing; yellow means waiting for your input, a warning or cancellation; green means successful completion; red means failure. Read the accompanying status text as well as the color. A partial scan retains its actual file count and a warning. A completed file count may still be followed by evaluation or explicit quarantine work. See the [candidate notes](RELEASE_2.2.0_RC2.md) for coverage and host limits.

## Remove an application

1. Open the application-removal area, filter the list if needed and select the displayed application number.
2. Check the exact selected product and the preview. Matches may include files, Registry entries, services and tasks; they are not conclusive ownership evidence.
3. Read any protected-component or administrator warning. A supported write operation attempts a restore point; if no new point can be verified, the warning explains whether to stop or explicitly continue without it.
4. Confirm the official uninstaller and follow any vendor prompts.
5. Review the new leftover scan. Confirm cleanup separately, or keep the leftovers.
6. Read the final remaining items and results. The operation saves its result/history and reaches 100% before offering an optional system-status snapshot.
7. Open the log, return to the previous program list or exit using the displayed choice.

The default residual scan excludes personal folders. Extended scanning may include personal files: inspect those candidates particularly carefully.

### Store packages and retained items

Supported Appx removal is scoped to the selected current-user package. An optional provisioning operation changes availability for future user profiles; it is not a promise to remove the application from every existing profile.

WindowsApps directories are managed by Windows and are retained rather than manually deleted. They may relate to other profiles, staged packages or pending Windows cleanup; a directory name alone cannot establish which. REMNEXA does not take ownership or change ACLs to force deletion.

A skipped Windows-managed path is different from a failed deletion. For actual access failures, inspect the path and concrete error. Do not assume administrator mode makes every path safe or writable.

### Understand the counts

The before/after scans are separate snapshots. A successfully removed Registry parent can cover child entries; these are counted separately rather than as individual deletion calls. Skipped, failed and still-present items have different meanings and should not be added as though they were independent categories.

Free-space changes can be influenced by other applications and Windows activity. They do not measure exact bytes attributable to REMNEXA.

## Safe command-line previews

From the project root:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1 -Name 'Example application' -DryRun
pwsh -NoProfile -File .\REMNEXA.ps1 -Name 'Example application' -ResidualOnly -DryRun
```

Replace the example name with the intended product. Keep `-DryRun` for a read-only preview. `-ResidualOnly` by itself is not a guarantee of a read-only operation. Advanced bypass flags are not substitutes for reviewing changes or maintaining backups.

## Startup manager

Review entry location, command and scope before disabling a supported entry. Use the supported restore action to reactivate it. System-wide changes can need elevation. Backups cover supported entry types, not every possible startup mechanism or a complete Windows restore.

## System overview and Windows tools

The system overview reads Windows/CIM information on demand: Windows version/build, CPU load, memory and fixed drives. It does not automatically optimize Windows.

The services area shows status. The optional status check does not repair services. Stopped/manual services can be normal. Antivirus registration and Defender readings are contextual evidence, not a protection guarantee or proof that a removal damaged Windows.

Selected advanced tools expose Windows repair, optional features, Registry-candidate review and privacy settings. Review each confirmation and any restart requirement. A tool may need installation media or network access. Avoid broad policy or service changes without understanding their effect.

Supported privacy backups are checked against a fixed Registry allowlist before restore. This is a limited configuration restore, not full system rollback.

## Antivirus

The optional Antivirus area explains elevation and supports engine/signature setup, scans and quarantine operations. See the [ClamAV guide](../Antivirus/README.md) before using it. A scan is not real-time protection.

## Logs, history and recovery

Removal logs are stored under `%LOCALAPPDATA%\REMNEXA\Logs`; history uses `%LOCALAPPDATA%\REMNEXA\History.jsonl`. These are generic application locations. The log-opening action returns to the result screen after you close the viewer. Keep useful logs before clearing them.

Logs and configuration backups can contain private paths, commands or application names. Review and redact them before sharing. Do not publish quarantine files.

The [backup guide](BACKUP_AND_CHECKPOINTS.md) explains source checkpoints. Neither those checkpoints nor a restore point reinstalls every removed application or recovers all personal data.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Launcher cannot find PowerShell | Install PowerShell 7.5+ or use a distribution with a compatible bundled runtime. |
| Permission request declined | Return to the action and approve it only after reviewing the explanation. |
| WindowsApps items remain | This is intentional protection; use supported Windows package management. |
| No new restore point | Read the reported restriction; an existing point is not a newly created backup. |
| No antivirus engine/signatures | Complete optional setup; installation and signature updates need internet. |
| A menu command is unavailable | Use the current screen's choices; pagination exists only when another page exists. |

For reproducible bugs, follow the sanitized reporting guidance in [CONTRIBUTING.md](../CONTRIBUTING.md).
