[English](CHANGELOG.md) | [Deutsch](CHANGELOG.de.md)

# Änderungsprotokoll

Entwicklungsänderungen sind keine veröffentlichten Releases. Dieses Dokument verändert keine vorhandenen Release-Dateien oder Tags.

## 2.2.0 — Entwicklung, nicht veröffentlicht

### Ergänzt

- Architekturprüfung, priorisierte Roadmap, Sicherheitsmodell und Kompatibilitätsmatrix.
- Sechs externe Sprachressourcen mit deutscher Rückfallsprache und Vollständigkeitsprüfung.
- Kernmodule für validierte Einstellungen, Logs, native Prozesse, Rechteprüfung, versionierte Ergebnisse und lesende Systemdaten.
- Systemübersicht im Hauptmenü für Windows, CPU, RAM und feste Laufwerke.
- Ausschließlich beratende KI-Ein-/Ausgabeverträge; keine Inferenzlaufzeit und kein Modell.
- Lokale Pester-/Analyzer-Runner, Quellcode-Sicherungswerkzeug und Windows-Qualitätsworkflow.
- Regressionstests für Sicherheit, Konfiguration, Navigation, Rechte und Abschlussverhalten.
- Englisch/deutsche Dokumentpaare, Dokumentationsübersicht und vollständige Benutzerhandbücher.
- Freiwilliger PayPal-Spendenlink und Button.

### Korrigiert

- Fehlende optionale Laufzeit/ClamAV lassen den Quellpaket-Selbsttest nicht mehr scheitern.
- ClamAV-Archivinstallation verlangt HTTPS und gültigen passenden SHA-256.
- Engine-Wechsel bereitet Installation vor, erhält Signaturen und stellt bei Konfigurationsübernahmefehlern die alte Engine wieder her.
- Unterstützte Anwendungs-/Antivirus-Einstellungen werden validiert und atomar geschrieben.
- Datenschutz-Restore prüft feste Registry-Liste und Schema vor Änderungen.
- Dateikandidaten und Löschung weisen Reparse-Point-Eltern und unprüfbare Pfade ab.
- WindowsApps bleiben bewusst erhaltene Treffer statt allgemeine Löschziele; keine Besitz-/ACL-Übernahme.
- Registry-Exitcode 1 gilt als Fehler; Kindabdeckung nur nach erfolgreicher Elternlöschung.
- Entfernungsergebnis/Historie und 100 % stehen vor optionaler Systemzustandsprüfung.
- Dienste-/Antivirus-Meldungen erklären Bedarfsstart, Drittanbieterregistrierung und Unsicherheit ohne doppelte Defender-Warnungen.
- Wiederherstellungspunkt-Erfolg verlangt einen bestätigten neuen Punkt mit eindeutiger Beschreibung.
- Rechteanfragen haben aktionsbezogene Erklärungen; Antivirus kann nach Freigabe direkt fortgesetzt werden.
- Nächste/vorherige Seite nur bei Gültigkeit; ungültige Befehle erklären verfügbare Auswahl.
- Genau eine direkte Beenden-Auswahl je Eingabe: 0, wo es beendet, sonst X.
- Quarantäne-Restore erhält Warnung, Integritätsprüfung und Überschreibschutz.
- Dokumentation entfernt mitwirkendenbezogene Dateipfade und trennt vorhandene Funktionen von Plänen.

### Prüfung und bekannte Grenzen

Der dokumentierte Anwendungsstand hat 79 bestandene lokale Pester-Tests und 12 Selbsttest-Prüfungen. Dokumentationsänderungen bedeuten keinen neuen Anwendungstest. Analyzer-Warnungen/Vollanalysefehler, Pfad-Zeitfenster, unvollständige Wiederherstellung, ungeprüfte Windows-/CI-Matrix, fehlende KI/Installer und fehlender Release Candidate bleiben offen. Siehe [Entwicklungsbericht](docs/VERSION_2.2.0.de.md).

## 2.1.3 — Quellcode-Basis

Die vorherige Quellversion bildet die Grundlage für Deinstallation und Wartung. Frühere Release-Details sind anhand ursprünglicher Tags und Artefakte zu prüfen; dieses Protokoll rekonstruiert keine ungeprüften historischen Release Notes.
