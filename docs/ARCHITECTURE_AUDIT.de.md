[English](ARCHITECTURE_AUDIT.md) | [Deutsch](ARCHITECTURE_AUDIT.de.md)

# Architekturprüfung

**Umfang:** eigener Quellcode der Entwicklungsversion 2.2.0 auf Basis von 2.1.3. Dies ist eine Quellcodeprüfung mit gezielten Tests und kein vollständiges unabhängiges Sicherheitsaudit.

## Aktuelle Struktur

| Bereich | Aufgabe |
| --- | --- |
| `REMNEXA.cmd`, Kompatibilitätsstarter | Geeignete PowerShell auswählen und Anwendung starten. |
| `REMNEXA.ps1` | Konsolennavigation, Programminventar, Deinstallation/Bereinigung und Windows-Werkzeuge. |
| `Core/` | Sprachen, Einstellungen, Logging, Prozesse, Rechte, Ergebnisse, Systemdaten, Pfadschutz, Menüs und Sicherheitsbewertung. |
| `locales/` | Sechs JSON-Sprachressourcen; je 282 Schlüssel im dokumentierten Stand. |
| `Antivirus/` | Optionale ClamAV-Einrichtung, Scans, Signaturen und Quarantäne. |
| `config/`, `assets/`, `examples/` | Standardkonfiguration, Grafiken und Aufrufbeispiele. |
| `tests/`, `tools/`, `.github/workflows/` | Regressionstests, lokale Prüfungen, Sicherungswerkzeug und CI-Konfiguration. |

Der Konsolendispatcher bleibt umfangreich. Kompatibilitätswrapper erhalten bisherige Aufrufe, während einzelne Aufgaben in Module wandern. Eine vollständige grafische Anwendung oder allgemeine Aufgabenverwaltung fehlt.

## Vorgangsgrenzen

Das Inventar umfasst registrierte Desktop-Deinstallationsprogramme und unterstützte Appx-Pakete. Der Ablauf zeigt Kandidaten, holt erforderliche Freigaben ein, versucht einen bestätigten Wiederherstellungspunkt, startet die registrierte Deinstallation, sucht erneut, bietet getrennte Restbereinigung, prüft verbleibende Einträge und schreibt Logs/Historie. Optionale Zustandsprüfung folgt nach abgeschlossenem Entfernen.

Registry, Dateisystem, registrierte Befehle, Dienste, Aufgaben und Paketwerkzeuge sind sensible Grenzen. Ein Teil der Zuordnung bleibt namensbasiert. Allgemeine Zuordnung über Hersteller, Produkt und gemeinsame Abhängigkeiten ist nicht validiert.

## Bestätigte, in 2.2.0 bearbeitete Fehler

| Früherer Fehler | Aktuelle Maßnahme |
| --- | --- |
| Optionale Quellpaket-Komponenten ließen Selbsttest scheitern | Fehlende Laufzeit/ClamAV-Engine werden als optional behandelt. |
| Fehlende/fehlerhafte Prüfsumme konnte Installation erlauben | HTTPS und passender SHA-256 vor Entpacken erforderlich. |
| Engine-/Konfigurationswechsel konnte Teilzustand hinterlassen | Gestufte Installation, atomare Konfiguration und Rückkehr bei Übernahmefehler. |
| Risiko verknüpfter Bereinigungspfade | Elternpfadprüfung bei Erfassung und vor Löschung; unprüfbare Pfade abgewiesen. |
| Datenschutz-Restore vertraute beliebigen Eingaben | Schema und feste Registry-Liste vor Schreibvorgängen geprüft. |
| WindowsApps-Löschung verursachte vermeidbare Zugriffsfehler | Windows-Paketordner bewusst erhalten. |
| Registry-Exitcode 1 galt als Erfolg | Fehlerzählung und Abdeckung erfolgreicher Elternschlüssel getrennt. |
| Fortschritt wartete bei 92 % auf optionale Zustandsprüfung | Ergebnis speichern und 100 % vor Zusatzprüfung erreichen. |
| Irreführende Dienste-/doppelte Defender-Warnungen | Kontextbezogene Dienste- und gemeinsame Antivirus-Bewertung. |
| Ungültige Seitenwechsel und doppelte Beenden-Optionen | Grenzen prüfen; eine sichtbare Beenden-Auswahl je Eingabe. |

Gezielte Regressionstests decken diese Maßnahmen ab, nicht sämtliche Deinstallations- und Wiederherstellungsfälle.

## Verbleibende Risiken und Vorschläge

1. **Hohe Priorität:** bessere Eigentumszuordnung und gemeinsame Ressourcen vor Ausweitung der Bereinigung.
2. **Hohe Priorität:** umfassende Restore-Prüfung, Fehlerpfade und isolierte Windows-Integrationstests.
3. **Hohe Priorität:** Zeitfenster zwischen Pfadprüfung und Zugriff bleibt; keine handlebasierte Isolation.
4. **Mittlere Priorität:** großer Dispatcher, Alt-Wrapper und Analyzer-Warnungen schrittweise bearbeiten.
5. **Mittlere Priorität:** Signaturupdate-Fehler nach Engine-Installation liegen außerhalb der Installationstransaktion.
6. **Nicht implementiert:** vollständiges Restore-Center, GUI, paketierte Offline-KI, vollständiger Installer und Release-Prüfung.

## Oberfläche und Abhängigkeiten

PowerShell-Konsole während der Stabilisierung erhalten. Eine Windows-native Grafikoberfläche vor Einführung anhand Startzeit, Speicher, Barrierearmut, Packaging und Migration vergleichen. Ein gemessener Vorteil für einen vollständigen Wechsel liegt derzeit nicht vor.

PowerShell und optionales ClamAV bleiben getrennte Abhängigkeiten. Entwicklung verwendet Pester und PSScriptAnalyzer. Keine KI-Laufzeit und kein Modell sind integriert oder für die Weitergabe freigegeben. Siehe [Drittanbieterhinweise](THIRD_PARTY_NOTICES.de.md).

Siehe [Roadmap](DEVELOPMENT_ROADMAP.de.md), [Sicherheitsmodell](SECURITY_MODEL.de.md), [Kompatibilität](COMPATIBILITY_MATRIX.de.md) und [Prüfbericht](VERSION_2.2.0.de.md).
