[English](BACKUP_AND_CHECKPOINTS.md) | [Deutsch](BACKUP_AND_CHECKPOINTS.de.md)

# Sicherungen und Zwischenstände

Git dokumentiert Quellcodeänderungen. Ein lokaler Quellcode-Zwischenstand bietet eine zusätzliche Kopie. Beides ersetzt weder persönliche Datensicherungen noch eine geprüfte Systemwiederherstellung.

## Zwischenstand erstellen

Schließe REMNEXA und ändere während des Kopierens keine Quelldateien. Im Projektordner:

```powershell
pwsh -NoProfile -File .\tools\New-RemnexaBackup.ps1 -Version 2.2.0-checkpoint
```

Wähle für jeden Zwischenstand einen eindeutigen Versionszusatz. Gib `-Version` ausdrücklich an, um den gewünschten Stand zu kennzeichnen; der aktuelle Standard lautet `2.2.0-rc.1`. `-SourcePath` erlaubt einen anderen Quellordner.

Das Werkzeug prüft freien Platz, erstellt eine Zwischenkopie, prüft kopierte Dateien per SHA-256 und kontrolliert das Manifest. Erst danach heißt das Verzeichnis `Backup-<Version>`. Vorhandene Ziele werden nie überschrieben. Ein fehlgeschlagener Zwischenstand bleibt zur Prüfung erhalten und gilt nicht als fertige Sicherung.

## Umfang und Ausschlüsse

Oberste `.git`-, `dist`-, `Backup-*`- und `.Backup-*.partial-*`-Ordner sowie Reparse Points werden übersprungen. Verknüpfte oder als Platzhalter vorhandene Inhalte können fehlen; prüfe das Manifest, statt eine vollständige Datenträgerkopie anzunehmen. Die Quelle ist nicht gesperrt; gleichzeitige Änderungen können den Stand inkonsistent machen.

Eine erfolgreiche Sicherung enthält:

- `BACKUP-MANIFEST.csv`: relativer Pfad, Größe und SHA-256 jeder kopierten Quelldatei.
- `BACKUP-INFO.txt`: Version, Zeitpunkt, Quellort und Summen.

**Diese Dateien privat halten:** Lokale Metadaten können persönliche absolute Pfade und sensible Dateinamen enthalten. Sicherungen sind von Git ausgeschlossen und gehören nicht in Release-Pakete.

## Prüfen und wiederherstellen

Prüfe vor Verwendung erwartete Dateien und Hashes anhand des Manifests und teste eine Kopie in einem isolierten Verzeichnis. Sichere vor Ersetzungen den aktuellen Arbeitsstand. Übernimm nur geprüfte Dateien; ältere Laufzeiten oder Drittkomponenten nicht blind über neuere Sicherheitsupdates kopieren.

Das Werkzeug erstellt Zwischenstände und ist keine allgemeine Wiederherstellungsverwaltung. Deinstallationen, echte Systemeinstellungen und persönliche Daten benötigen eigene Wiederherstellungspläne. Versprich kein vollständiges Rollback fremder Deinstallationen.

[Entwicklungsablauf](DEVELOPMENT_WORKFLOW.de.md) beschreibt Git-Zwischenstände; [Sicherheitsmodell](SECURITY_MODEL.de.md) erläutert Wiederherstellungsgrenzen einzelner Vorgänge.
