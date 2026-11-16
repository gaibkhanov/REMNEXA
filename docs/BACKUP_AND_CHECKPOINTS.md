# Backups ohne Git

Der Maintainer entwickelt REMNEXA ohne Git-Versionierung. Vor größeren Änderungen wird deshalb ein unveränderlicher Ordner `Backup-<Version>` erstellt. Das Werkzeug überschreibt vorhandene Backups nie, überspringt vorhandene Backup-Ordner und Reparse Points und erstellt ein SHA-256-Manifest.

## Ein Backup erstellen

Aus dem Projektordner:

```powershell
pwsh -NoProfile -File .\tools\New-RemnexaBackup.ps1 -Version 2.1.3
```

Der Standard-Quellordner ist der Projektordner, in dem das Werkzeug liegt. Für einen anderen Quellordner kann `-SourcePath` angegeben werden. Bei einem Fehler bleibt der Zwischenstand zur Prüfung erhalten; ein vorhandener Backup-Ordner wird nicht verändert.

Die Quelle wird während des Kopierens nicht gesperrt. Vor einer Sicherung sollte REMNEXA daher geschlossen sein und es sollten keine Dateien im Quellordner geändert werden.

Jeder erfolgreiche Sicherungsordner enthält:

- `BACKUP-INFO.txt` mit Versionsnummer, Zeitpunkt und Umfang.
- `BACKUP-MANIFEST.csv` mit relativem Pfad, Dateigröße und SHA-256 für jede gesicherte Quelldatei.

## Checkpoints

Nach jeder abgeschlossenen Entwicklungsstufe wird der Arbeitsstand mit einer neuen Versions- oder Entwicklungsnummer gesichert. Änderungen werden über `BACKUP-MANIFEST.csv` mit der letzten Sicherung verglichen. Release-Dateien werden weiterhin separat getestet; ein Backup ersetzt keine Regressionstests oder einen Wiederherstellungstest.

Die erste Sicherung des unveränderten REMNEXA-2.1.3-Stands wurde mit denselben Regeln erstellt. Sie enthält 898 Dateien und 1,309,979,961 Nutzdatenbytes; alle 898 Dateien wurden beim Kopieren per SHA-256 verifiziert.
