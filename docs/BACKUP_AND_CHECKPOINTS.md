[English](BACKUP_AND_CHECKPOINTS.md) | [Deutsch](BACKUP_AND_CHECKPOINTS.de.md)

# Backups and checkpoints

Git records source changes. A local source checkpoint provides an additional copy; neither replaces backups of personal data or a tested system restore.

## Create a checkpoint

Close REMNEXA and stop editing the source during copying. From the project root:

```powershell
pwsh -NoProfile -File .\tools\New-RemnexaBackup.ps1 -Version 2.2.0-checkpoint
```

Choose a unique version suffix for each checkpoint. Specify `-Version` explicitly to identify the intended checkpoint; the current default is `2.2.0-rc.1`. `-SourcePath` can select a different source root.

The tool checks space, stages the copy, verifies copied files with SHA-256, checks its manifest and only then names the directory `Backup-<Version>`. An existing destination is never overwritten. Failed staging is retained for inspection rather than presented as a completed backup.

## Coverage and exclusions

Top-level `.git`, `dist`, `Backup-*` and `.Backup-*.partial-*` directories, and reparse points, are skipped. Linked or placeholder content may therefore be absent; inspect the manifest rather than assuming a full disk image. The source is not locked, so concurrent changes can make a snapshot inconsistent.

A successful checkpoint contains:

- `BACKUP-MANIFEST.csv`: relative path, size and SHA-256 for each copied source file.
- `BACKUP-INFO.txt`: version, timestamp, source location and totals.

**Keep these files private:** local metadata can contain absolute personal paths and sensitive filenames. Backups are excluded from version control and must not be included in release artifacts.

## Verify and recover

Before relying on a backup, verify expected files and hashes against the manifest and test a copy in an isolated directory. Preserve the current working tree before replacing anything. Restore only reviewed files; do not copy an old runtime or vendor component blindly over newer security updates.

The backup tool creates checkpoints; it is not a general restore manager. Application removal, live system settings and personal data require separate recovery plans. Do not claim complete rollback of a third-party uninstallation.

See [development workflow](DEVELOPMENT_WORKFLOW.md) for Git checkpoints and [security model](SECURITY_MODEL.md) for operation-level recovery limits.
