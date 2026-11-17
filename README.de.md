[English](README.md) | [Deutsch](README.de.md)

# REMNEXA

**Mehr Kontrolle über deinen Windows-PC.**

Ein kostenloses Open-Source-Werkzeug für die Deinstallation von Anwendungen, Autostart-Verwaltung, Windows-Wartung und optionale lokale Malware-Scans. Prüfe die gefundenen Einträge und entscheide selbst über die unterstützten Änderungen.

**Windows 10 / 11 · PowerShell 7.5+ · MIT-Lizenz · Sechs Oberflächensprachen**

> **Aktueller Kandidat: 2.2.0-rc.2**, verfügbar im [Kandidatenbranch](https://github.com/gaibkhanov/REMNEXA/tree/feature/2.2.0-progress). Dies ist kein stabiles Release. Beachte [Kandidatenbericht und Paketanleitung](docs/RELEASE_2.2.0_RC2.de.md). Der Standardbranch kann eine ältere Version enthalten.

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

Lokale Prüfungen bei Bedarf ausführen, Signaturen aktualisieren und Funde ansehen. Unterstützte Quarantäne- und Wiederherstellungsvorgänge müssen bewusst ausgewählt werden. Ersteinrichtung und Signaturupdates benötigen Internet; mit installierter Engine und vorhandenen Signaturen sind Scans offline möglich.

REMNEXA ist kein Echtzeit-Antivirus und ersetzt weder Microsoft Defender noch vorhandene Sicherheitssoftware. Ein Fund kann ein Fehlalarm sein; ausbleibende Funde garantieren keine Sicherheit. Siehe [ClamAV-Anleitung](Antivirus/README.de.md).

### Sechs Oberflächensprachen

Deutsch, Englisch, Spanisch, Französisch, Russisch und Türkisch. Übersetzungen liegen getrennt von der Anwendungslogik; Deutsch dient als Rückfallsprache. Die Projektdokumentation ist auf Englisch und Deutsch verfügbar.

## Installation

Voraussetzungen: Windows 10 oder 11, PowerShell **ab Version 7.5** sowie Administratorfreigabe für Aktionen, die erhöhte Rechte benötigen. Windows PowerShell 5.1 kann die Anwendung nicht ausführen. Die [Kompatibilitätsmatrix](docs/COMPATIBILITY_MATRIX.de.md) beschreibt die Prüfgrenzen.

Lade das ZIP des Kandidatenbranches herunter oder verwende Git:

```powershell
git clone --branch feature/2.2.0-progress https://github.com/gaibkhanov/REMNEXA.git
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

Kandidat rc.2 ergänzt messbaren Antivirus-Dateifortschritt, sichtbares Laden und Auswerten, Laufzeit sowie klare Abschluss-, Hinweis- und Fehlerzustände für Wartungsvorgänge. Überlappende Scanwurzeln werden zusammengefasst; fehlende Rückmeldungen bleiben unvollständig. Prüfstand und Grenzen stehen im [Kandidatenbericht](docs/RELEASE_2.2.0_RC2.de.md).

- HTTPS- und SHA-256-Prüfung unterstützter ClamAV-Downloads; gestufte Installation und Konfigurationswiederherstellung.
- Zusätzliche Prüfungen verknüpfter Pfade und unterstützter Datenschutzsicherungen.
- Klarere Bereinigungszahlen, Zugriffsfehler und bewusst erhaltene Windows-Paketdateien.
- Abschluss bei 100 % vor der optionalen Systemzustandsprüfung.
- Kontextbezogene Dienste-/Antivirus-Meldungen und aktionsbezogene Administratorhinweise.
- Seitenwechsel nur bei vorhandenen Seiten; genau eine sichtbare Beenden-Option je Eingabe.
- Modulare Kernbausteine, externe Übersetzungen und eine rein lesende Systemübersicht.

Der dokumentierte Anwendungsstand bestand **79 lokale Pester-Tests und 12 Selbsttest-Prüfungen**. Das ist keine vollständige Kompatibilitäts-, Sicherheits- oder CI-Zertifizierung. Siehe [Entwicklungsbericht](docs/VERSION_2.2.0.de.md).

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

REMNEXA steht unter der [MIT-Lizenz](LICENSE). Optionale Drittkomponenten behalten ihre eigenen Bedingungen; siehe [Drittanbieterhinweise](docs/THIRD_PARTY_NOTICES.de.md). Die REMNEXA-Lizenz ersetzt diese Pflichten nicht.
