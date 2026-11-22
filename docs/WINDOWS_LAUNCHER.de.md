[English](WINDOWS_LAUNCHER.md) | [Deutsch](WINDOWS_LAUNCHER.de.md)

# Windows-Launcher und Paketvorschau

Dieser Feature-Branch ergänzt einen nativen x64-Win32-Launcher und ein getrenntes Benutzerpaket für die bestehende Anwendung 2.2.0. Das stabile Quellrelease v2.2.0 wird dadurch weder neu veröffentlicht noch ersetzt. Launcher und Paket sind unsignierte Vorschauen.

## Quellcode und Benutzerpaket

Bisher standen sechs CMD-Einstiege, der kompatible PowerShell-Starter, Entwicklerwerkzeuge/-tests und lokale Sicherungen nebeneinander. Im Quellcode bleiben kompatible Namen erhalten; im Benutzerpaket gibt es einen Einstieg:

```text
Quellcode                       Benutzerpaket
REMNEXA.ps1                     REMNEXA-2.2.0/
REMNEXA.cmd + Weiterleitungen      REMNEXA.exe
Core/ Antivirus/ config/          app/
src/Launcher/                      REMNEXA.ps1
assets/icons/                      Core/ Antivirus/ config/
locales/                           assets/ locales/ LICENSE
scripts/ tests/ tools/             runtime/ (optional)
docs/ examples/                   README.txt
```

Core, Antivirus und config behalten ihre Quellpfade: Module und Testkopien besitzen funktionierende relative Importe. Ein rein optisches Verschieben nach src würde zusätzlichen Migrationsaufwand erzeugen. Im Benutzerpaket liegen dieselben Abhängigkeiten unter app, ohne ihre Beziehungen zu verändern. src enthält den neuen Launcher, scripts die Icon-/Launcher-/Paket-Builds. Examples wird mit aktualisierten Verweisen zu examples. Sicherungen werden vollständig in einen benachbarten Backup-Bereich verschoben und vorher/nachher per SHA-256 protokolliert; sie werden weder gelöscht noch versioniert.

REMNEXA-Antivirus.cmd, REMNEXA-Autostart.cmd, REMNEXA-Deinstallation.cmd und REMNEXA-Dienste.cmd leiten zum zentralen Quellcode-Einstieg weiter. Programm-Entferner.cmd/.ps1 bleiben kompatible Einstiege. Diese Starter fehlen im Benutzerpaket ebenso wie Tests, tools, scripts, Git-Metadaten, Backups und Logs. Alle Arbeitsbereiche bleiben im Hauptmenü erreichbar.

## Nativer Launcher

Der MIT-lizenzierte C-Quellcode nutzt Win32 direkt. Er benötigt weder .NET noch C-Laufzeit, Python oder Node. Das Manifest verlangt asInvoker. PowerShell wird direkt mit sicherer Windows-Argumentübergabe gestartet; Rückgabecodes bleiben erhalten. Arbeitsverzeichnis ist der EXE-Ordner. Der Launcher setzt keine ExecutionPolicy und fordert keine erhöhten Rechte an. Vorhandene aktionsbezogene Freigaben der Anwendung bleiben bestehen.

Zuerst wird eine stabile PowerShell ab 7.5 unter runtime/pwsh.exe geprüft, danach an üblichen Program-Files-Pfaden und in allen absoluten PATH-Verzeichnissen. Leere/relative PATH-Einträge werden ignoriert, ungültige oder ungeeignete Kandidaten übersprungen. Verdeckte Prüfprozesse haben für den Kaltstart der Laufzeit 15 Sekunden Zeitlimit und erzeugen kein zusätzliches sichtbares Konsolenfenster. Der normale Start nutzt eine gemeinsame Konsole. --diagnose liefert die Laufzeitauswahl maschinenlesbar, ohne Anwendung oder Einstellungsänderungen auszuführen.

Das Icon übernimmt das vorhandene offizielle PNG, entfernt für Lesbarkeit nur transparenten Rand und enthält PNG-Stufen mit 16/24/32/48/64/128/256 Pixeln. Explorer verwendet das eingebettete Icon; klassische Konsolen bekommen das kleine/große Icon. Windows Terminal verwaltet seine Taskleistenidentität selbst; dort ist ein eigenes Taskleistenicon nicht garantiert. Spätere Verknüpfungen/Installer können assets/icons/remnexa.ico oder die EXE-Ressource nutzen. Ein Signierzertifikat steht nicht bereit.

## Build reproduzieren

Windows 11 x64 (Client-Build ab 22000), PowerShell ab 7.5, Git und festgelegtes Zig 0.15.2 verwenden:

```powershell
./scripts/Install-LauncherToolchain.ps1
./scripts/Build-Launcher.ps1
./scripts/Build-Release.ps1
# Optional vertrauenswürdige PowerShell-Dateien samt Lizenzhinweisen:
./scripts/Build-Release.ps1 -OutputDirectory ./dist/with-runtime -RuntimePath ./runtime
```

Die ausdrückliche Toolchain-Einrichtung lädt nur das offizielle Zig-Archiv und prüft dessen fest hinterlegten SHA-256-Wert. Keine globale Installation oder PATH-Änderung. Die Toolchain ist ausschließlich für Entwickler und nicht im Benutzerpaket. Zig steht unter MIT; siehe [Build-Lizenzhinweise](../src/Launcher/THIRD_PARTY_NOTICES.txt). Die bisherigen PowerShell-/ClamAV-Lizenzgrenzen gelten laut [Drittanbieterhinweisen](THIRD_PARTY_NOTICES.de.md). Nur vorhandener Anwendungscode und eine ausdrücklich angegebene Laufzeit werden verpackt; keine ClamAV-Programme oder Signaturen werden kopiert.

Aus einem sauberen, committeten Checkout bauen. Standardausgabe: dist/windows-x64/REMNEXA-2.2.0 sowie windows-x64-preview-ZIP mit SHA-256-Datei. Vorhandene Ausgaben werden nicht überschrieben. Das Manifest nennt Quellcommit und Hash jeder kopierten Datei; ZIP- und unsignierte PE-Zeitstempel sind normalisiert. Reproduzierbarkeit setzt identische Quellen, Compiler und gegebenenfalls Laufzeitdateien voraus. scripts/New-ApplicationIcon.ps1 regeneriert das Icon mit Windows System.Drawing als Formatumwandlung des vorhandenen Logos.

## Authenticode-Signierung

`Build-Release.ps1` kann den vorbereiteten Launcher und alle PowerShell-Skripte, Module und Modulmanifeste der Anwendung signieren, bevor Dateihashes und ZIP entstehen. Laufzeitdateien von Drittanbietern behalten ihre ursprünglichen Signaturen. Erforderlich sind ein bereits installiertes, gültiges Code-Signing-Zertifikat mit privatem Schlüssel, eine vertrauenswürdige und auf Widerruf prüfbare Zertifikatskette sowie Microsoft SignTool aus dem Windows SDK auf dem Signierrechner. Benutzer benötigen diese Entwicklerwerkzeuge nicht.

```powershell
./scripts/Build-Release.ps1 -OutputDirectory ./dist/signed-preview -RuntimePath ./runtime `
    -SigningCertificateThumbprint '<40-stelliger Zertifikat-Fingerabdruck>' `
    -SignToolPath '<Windows SDK x64 signtool.exe>'
```

Der RFC-3161-Zeitstempeldienst ist standardmäßig `https://timestamp.digicert.com`; über `-TimestampServer` lässt sich ein anderer HTTPS-Endpunkt angeben. Signatur und Zeitstempel verwenden SHA-256. Jede signierte Datei muss die SignTool-Prüfung und die Windows-Authenticode-Prüfung mit dem ausgewählten Herausgeber und einem Zeitstempel bestehen. Fehlende, abgelaufene oder nicht vertrauenswürdige Zertifikate, ein nicht vertrauenswürdiges Signierwerkzeug, fehlende Zeitstempel oder Signierfehler brechen den Build ab; teilweise signierte Zwischenstände werden verworfen. Private Schlüssel werden nicht exportiert, selbstsignierte Zertifikate weder erzeugt noch installiert und Vertrauens- oder Richtlinieneinstellungen nicht verändert. Ein Zertifikat-Fingerabdruck bezeichnet das öffentliche Zertifikat und ist kein Passwort.

Das Manifest setzt `Signed` erst nach erfolgreicher Prüfung und protokolliert den öffentlichen Fingerabdruck, Algorithmus, Zeitstempeldienst und die Anzahl geprüfter Dateien. Signieren und Zeitstempeln verändern Dateien; Paketprüfsummen entstehen deshalb anschließend. Signierte Pakete sind nicht bytegleich reproduzierbar. Signaturen belegen Herausgeber und Dateiintegrität, garantieren aber weder SmartScreen-Reputation noch die Qualität der Malware-Erkennung.

**Das aktuelle Paket bleibt unsigniert:** Auf dem Prüfrechner waren weder ein Code-Signing-Zertifikat mit privatem Schlüssel noch Windows SDK SignTool verfügbar. Die Schutzregeln des Signierablaufs sind durch isolierte Regressionstests mit Mocks abgedeckt; eine echte CA-Signatur mit Zeitstempel wurde noch nicht getestet. Die vorhandene unsignierte Vorschau bleibt nutzbar. Dieser Build erstellt oder ersetzt kein stabiles Release.

## Prüfung und Grenzen

Launcher-Regressionen prüfen PE-/CLR-Metadaten, Icon-Größen, Quell-/Paketlayout, Unicode/Leerzeichen, Argumentsonderzeichen, fehlende/defekte Laufzeit, Rechte-/Policy-Erhalt, Rückgabecodes und Weiterleitungen. Pakettests prüfen erlaubte Inhalte, Dateihashes, sechs Sprachen, Modul-/Lizenzabhängigkeiten und echte Anwendungsselbsttests über die EXE. Bestehende Antivirus-/Navigationstests bleiben relevant.

Nativer Launcher und direkter PowerShell-Einstieg benötigen Windows 11 oder neuer (Client-Build ab 22000). Windows 10, ältere Windows-Versionen und Windows Server werden vor Laufzeitsuche bzw. Anwendungsinitialisierung abgewiesen. Der Launcher nutzt RtlGetVersion; das Skript prüft Betriebssystemversion und Client-Produkttyp. Die Kompatibilitäts-GUID im Manifest wird mit Windows 10 geteilt und ersetzt diese Buildprüfung nicht. Lässt sich kein unterstützter Client feststellen, wird der Start abgewiesen. Die Mindestanforderung gilt für aktuelle Entwicklungsstände; vorhandene veröffentlichte Artefakte bleiben unverändert.

Die Vorschau zertifiziert weder SmartScreen-Reputation noch jede unterstützte Windows-11-/Terminal-Variante oder Offline-Ersteinrichtung optionaler Komponenten. Eine Benutzer-ExecutionPolicy kann heruntergeladene Skripte sperren; der Launcher meldet den Fehler und umgeht die Richtlinie nicht. Paketinhalt und unabhängige Sicherungen vor Systemänderungen prüfen. Die Build-Skripte verändern keine stabilen Releases.

Dokumentierte lokale Prüfung: **216 Tests bestanden, 0 fehlgeschlagen, 0 übersprungen** (Pester 5.7.1, PowerShell 7.6.9); die vier Pakettests wurden nach den Paketkorrekturen erfolgreich wiederholt. Syntax- und PSScriptAnalyzer-Fehlerprüfungen bestehen für **112 PowerShell-Dateien**. Zwei saubere Builds ohne optionale Laufzeit ergaben bytegleiche ZIPs. Das Paket mit PowerShell 7.6.9 enthält **738 Dateien** mit geprüften Hashes und vollständigen Laufzeit-Lizenzhinweisen. **12 Anwendungsselbsttests bestehen bei abgeschalteter Suche nach installierten Laufzeiten**, ohne erhöhte Rechte. Der zusätzliche Upstream-Preview-CMD-Starter ist ausgeschlossen. Ein echter Start über die Windows-Shell nutzte eine gemeinsame Konsole für Launcher und PowerShell und endete über das Hauptmenü; auch die Icon-Extraktion durch die Windows-Shell besteht. Dies dokumentiert den verfügbaren Windows-11-Rechner, keine vollständige Windows-Kompatibilitätsmatrix.
