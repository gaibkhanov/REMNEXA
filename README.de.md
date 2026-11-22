[English](README.md) | [Deutsch](README.de.md)

# REMNEXA

**Mehr Kontrolle über deinen Windows-PC.**

Ein kostenloses Open-Source-Werkzeug für die Deinstallation von Anwendungen, Autostart-Verwaltung, Windows-Wartung und optionale lokale Malware-Scans. Prüfe die gefundenen Einträge und entscheide selbst über die unterstützten Änderungen.

**Windows 10 / 11 · PowerShell 7.5+ · Open Source · Sechs Oberflächensprachen**

> **Version 2.2.0**: [Download und Release Notes](https://github.com/gaibkhanov/REMNEXA/releases/tag/v2.2.0). Quellpaket mit SHA-256-Prüfsumme; PowerShell und optionale ClamAV-Komponenten werden separat benötigt. Siehe [Installation, Prüfstand und Grenzen](docs/RELEASE_2.2.0.de.md).

> **Launcher-Vorschau im Feature-Branch:** Nativer Windows-Start mit eigenem Icon und aufgeräumtem Benutzerpaket. Build und Grenzen: [Windows-Launcher](docs/WINDOWS_LAUNCHER.de.md). Das stabile Release oben bleibt unverändert.

Der Paketbau unterstützt geprüfte Authenticode-Signierung mit vertrauenswürdigem Signierzertifikat und Microsoft SignTool. Die aktuelle Vorschau ist **unsigniert**; siehe [Voraussetzungen](docs/WINDOWS_LAUNCHER.de.md#authenticode-signierung).

## Funktionen

### Anwendungen entfernen

- Unterstützte Desktop-, MSI- und Microsoft-Store-Anwendungen deinstallieren.
- Möglicherweise zugehörige Dateien, Ordner, Registry-Einträge, Dienste und geplante Aufgaben finden.
- Rückstände vorab ansehen und deren Bereinigung getrennt von der regulären Deinstallation bestätigen.
- Entfernte, fehlgeschlagene, bewusst behaltene und verbleibende Einträge nachvollziehen.
- Windows-verwaltete Paketdateien vor allgemeinem manuellem Löschen schützen.

Ein Treffer ist ein Bereinigungskandidat und kein Eigentumsnachweis. Prüfe jede vorgeschlagene Entfernung. Für Store-Pakete gelten Grenzen beim Benutzer- und Bereitstellungsumfang; siehe [Benutzerhandbuch](docs/USER_GUIDE.de.md).

### Autostart und Systemwartung

Unterstützte Autostart-Einträge prüfen und verwalten, einschließlich Sicherungen für unterstützte Änderungen. Windows-Version, CPU-Auslastung, Arbeitsspeicher, Platz auf festen Laufwerken und laufende Dienste anzeigen. Ausgewählte Windows-Reparatur-, Feature- und Datenschutzwerkzeuge aufrufen.

Die Systemübersicht liest ausschließlich Daten. Die aktuelle Oberfläche läuft im Terminal; ein grafisches Dashboard ist geplant.

### Optionale ClamAV-Prüfung

Scans laufen im eigenen Fenster. Nutze REMNEXA weiter oder beende es und lasse den Scan unabhängig fertiglaufen. Pause, Fortsetzung, Abbruch und Befunde sind im Scanmanager oder Scanfenster erreichbar. Siehe [Anleitung zum unabhängigen Scan](docs/INDEPENDENT_SCANS.de.md).

Lokale Prüfungen bei Bedarf ausführen, Signaturen aktualisieren und Funde ansehen. Unterstützte Quarantäne- und Wiederherstellungsvorgänge müssen bewusst ausgewählt werden. Ersteinrichtung und Signaturupdates benötigen Internet; mit installierter Engine und vorhandenen Signaturen sind Scans offline möglich.

REMNEXA ist kein Echtzeit-Antivirus und ersetzt weder Microsoft Defender noch vorhandene Sicherheitssoftware. Ein Fund kann ein Fehlalarm sein; ausbleibende Funde garantieren keine Sicherheit. Siehe [ClamAV-Anleitung](Antivirus/README.de.md).

### Sechs Oberflächensprachen

Deutsch, Englisch, Spanisch, Französisch, Russisch und Türkisch. Übersetzungen liegen getrennt von der Anwendungslogik; Deutsch dient als Rückfallsprache. Die Projektdokumentation ist auf Englisch und Deutsch verfügbar.

## Installation

Voraussetzungen: Windows 10 oder 11, PowerShell **ab Version 7.5** sowie Administratorfreigabe für Aktionen, die erhöhte Rechte benötigen. Windows PowerShell 5.1 kann die Anwendung nicht ausführen. Die [Kompatibilitätsmatrix](docs/COMPATIBILITY_MATRIX.de.md) beschreibt die Prüfgrenzen.

Lade das Release-Quellpaket herunter oder verwende den Release-Tag mit Git:

```powershell
git clone --branch v2.2.0 https://github.com/gaibkhanov/REMNEXA.git
Set-Location REMNEXA
.\REMNEXA.cmd
```

Alternativ:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1
```

Der Starter verwendet bevorzugt eine mitgelieferte `runtime\pwsh.exe`, sonst PowerShell aus `PATH`. **Das Quellrepository enthält weder die portable Laufzeit noch ClamAV-Binärdateien oder Signaturdatenbanken.** Installiere PowerShell bei Verwendung des Quellcodes separat. Halte die Quellordner zusammen. Ein neuer Windows-Installer ist nicht enthalten.

## Sicherheit und Kontrolle

- Bereinigungsvorschauen prüfen und destruktive interaktive Aktionen ausdrücklich bestätigen.
- Vor einer Windows-Administratorabfrage die Erklärung zur gewählten Aktion lesen.
- Geschützte Komponenten sind standardmäßig gesperrt; WindowsApps-Ordner werden nicht allgemein manuell gelöscht.
- Unterstützte Vorgänge versuchen einen neuen Wiederherstellungspunkt anzulegen und prüfen die tatsächliche Erstellung.
- Strukturierte Protokolle unterscheiden übersprungene Pfade, Fehler und verbleibende Treffer.
- Persönliche Ordner sind von der normalen Rückstandssuche ausgeschlossen; die erweiterte Suche verlangt besondere Sorgfalt.

Sicherungen und Wiederherstellungspunkte garantieren keine vollständige Wiederherstellung. Die Deinstallation fremder Anwendungen kann irreversibel sein. Sichere wichtige Daten unabhängig.

Dienste- und Antivirus-Prüfungen sind Momentaufnahmen. Ein gestoppter Dienst mit Start bei Bedarf ist nicht automatisch fehlerhaft. Ein anderer registrierter Antivirus kann einen ruhenden Defender erklären; die Registrierung allein belegt keinen aktiven Schutz.

## Neu in 2.2.0

Version 2.2.0 ergänzt unabhängige Scanfenster und Fortsetzen/Abbrechen/Zurück beim Beenden von REMNEXA. Der frühere Kandidat rc.6 korrigiert den nativen Worker-Start aus einer erhöhten Anwendung und erweitert Prüfungen realer Job-Grenzen, knappen Speichers, von Archiven und Signatur-Neuladen. Wiederverwendbare ClamAV-1.5.4-Engine, CLI-Fallback, Eco/Balanced/Fast und Scanabbruch bleiben verfügbar. Bestehende Update- und Quarantänekontrollen bleiben erhalten. Siehe [Prüfungen und verbleibende Grenzen](docs/INDEPENDENT_SCANS.de.md).

- HTTPS- und SHA-256-Prüfung unterstützter ClamAV-Downloads; gestufte Installation und Konfigurationswiederherstellung.
- Zusätzliche Prüfungen verknüpfter Pfade und unterstützter Datenschutzsicherungen.
- Klarere Bereinigungszahlen, Zugriffsfehler und bewusst erhaltene Windows-Paketdateien.
- Abschluss bei 100 % vor der optionalen Systemzustandsprüfung.
- Kontextbezogene Dienste-/Antivirus-Meldungen und aktionsbezogene Administratorhinweise.
- Seitenwechsel nur bei vorhandenen Seiten; genau eine sichtbare Beenden-Option je Eingabe.
- Modulare Kernbausteine, externe Übersetzungen und eine rein lesende Systemübersicht.

Aktuelles Verhalten und verbleibende Grenzen stehen im [Bericht zur privaten Engine](docs/INDEPENDENT_SCANS.de.md). Frühere Prüfergebnisse bleiben im historischen [Entwicklungsbericht](docs/VERSION_2.2.0.de.md) dokumentiert.

## Dokumentation

- [Dokumentationsübersicht](docs/README.de.md) · [Benutzerhandbuch](docs/USER_GUIDE.de.md)
- [ClamAV-Anleitung](Antivirus/README.de.md) · [Änderungsprotokoll](CHANGELOG.de.md)
- [Architekturprüfung](docs/ARCHITECTURE_AUDIT.de.md) · [Roadmap](docs/DEVELOPMENT_ROADMAP.de.md)
- [Sicherheitsmodell](docs/SECURITY_MODEL.de.md) · [Kompatibilität](docs/COMPATIBILITY_MATRIX.de.md)
- [Entwicklungsablauf](docs/DEVELOPMENT_WORKFLOW.de.md) · [Sicherungsanleitung](docs/BACKUP_AND_CHECKPOINTS.de.md)

## Roadmap

Ein grafisches Dashboard, umfassendere Speicheranalyse, bessere Zuordnung von Rückständen, eine zentrale Wiederherstellungsoberfläche, eine integrierte Offline-KI und verbessertes Packaging sind geplant. **KI-Modell und Inferenzlaufzeit sind nicht enthalten.** Die Roadmap nennt Umsetzungs- und Prüfstatus.

## Mitwirken und Sicherheit

Lies vor Änderungen [CONTRIBUTING.de.md](CONTRIBUTING.de.md). Melde Fehler über ein [Issue](https://github.com/gaibkhanov/REMNEXA/issues) mit Versionen, Reproduktionsschritten sowie erwartetem und tatsächlichem Verhalten. Entferne private Pfade, Zugangsdaten und sensible Protokollinhalte. Sicherheitslücken gemäß [SECURITY.de.md](SECURITY.de.md) melden.

## Projekt unterstützen

Spenden sind freiwillig. Über die [PayPal-Spendenseite](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr) kannst du die Entwicklung unterstützen.

[![Über PayPal spenden](https://img.shields.io/badge/Spenden-PayPal-0070BA?logo=paypal&logoColor=white)](https://www.paypal.com/pool/9uaOjAIYHS?sr=wccr)

Auch Fehlermeldungen, Übersetzungen und Codebeiträge helfen.

## Lizenz

REMNEXA-Oberfläche und IPC-Transport stehen unter der [MIT-Lizenz](LICENSE). Der optionale native Adapter in `Antivirus/Workers` steht unter **GPL-2.0-or-later** mit eigenen Lizenzhinweisen. Optionale Drittkomponenten behalten ihre Bedingungen; siehe [Drittanbieterhinweise](docs/THIRD_PARTY_NOTICES.de.md).
