[English](DEVELOPMENT_ROADMAP.md) | [Deutsch](DEVELOPMENT_ROADMAP.de.md)

# Entwicklungsroadmap

Die Entwicklungsversion 2.2.0 ist ein schrittweiser Ausbau von 2.1.3 und nicht die fertige REMNEXA-3.0-Plattform. Funktionierende Bereiche erhalten und Risiken reduzieren. Siehe [Architekturprüfung](ARCHITECTURE_AUDIT.de.md).

## Phasenstatus

| Phase | Status | Vorhanden | Offene Abnahmearbeit |
| --- | --- | --- | --- |
| A: Audit | Für verfügbaren Quellumfang abgeschlossen | Architektur, Risiken, Kompatibilität und Plan | Unabhängige Prüfung und breitere Integration. |
| B: Stabilisierung | Teilweise implementiert | Download-/Konfigurations-/Pfadschutz, klarere Ergebnisse, Regressionstests | Umfassende Wiederherstellungs- und Unterbrechungstests. |
| C: Modularisierung | Teilweise implementiert | Kernmodule, Kompatibilitätswrapper, externe Sprachen | Kleinerer Dispatcher und vollständige typisierte Grenzen. |
| D: lokale KI | Über Verträge hinaus nicht implementiert | Begrenzte Eingabe-/Empfehlungsschemas | Laufzeit, Modellauswahl, Lizenzen, Benchmarks, Chat und Offline-Tests. |
| E: Systemmodule | Teilweise implementiert | Lesende Systemdaten/Oberfläche und bestehende Werkzeuge | Erweiterte Speicheranalyse und bessere Deinstallationszuordnung. |
| F: UI/UX | Teilweise implementiert | Konsolennavigation, Beenden/Seitenwechsel und Rechtehinweise | Bewertete GUI, Barrierearmut und bedienbare Aufgaben/Abbrüche. |
| G: QA | Teilweise implementiert | Lokale Tests/Selbsttest/Fehlerprüfung und CI-Definition | Bestätigte CI, VM-Matrix, Restore-, Offline-, Leistungs- und Pakettests. |
| H: Release Candidate | Nicht implementiert | Entwicklungsquellcode | Geprüfter Installer/Artefakte, Prüfsummen, Release Notes und Freigabe. |

## Priorität 1: Sicherheit und Zuverlässigkeit

- Rückstände anhand Produktkennungen, Hersteller-/Pfadmetadaten und gemeinsamer Abhängigkeiten zuordnen; unklare Zugehörigkeit standardmäßig behalten.
- Isolierte Tests für Rechtefehler, gemeinsame Dateien, manipulierte Pfade und Unterbrechungen erweitern.
- Vorgangsbezogene Sicherungen mit geprüfter Wiederherstellung unterstützter Registry-, Autostart-, Datei-, Aufgaben- und Diensteänderungen entwerfen.
- Pfad-Zeitfenster reduzieren; Elternpfadprüfungen nicht als vollständigen Schutz darstellen.
- Analyzer-Warnungen einzeln prüfen und Vollanalyse-Absturz reproduzieren.

## Priorität 2: Wartbarkeit und Bedienung

Kernlogik weiter auslagern, ohne Kommandozeile oder Sprachen zu brechen. Einheitliche Ergebnisse, Fortschritt und sichere Abbrüche definieren. Sprachschlüssel extern halten; englische/deutsche Dokumente gemeinsam pflegen.

Startzeit, Inventar, Rückstandssuche, Leerlaufspeicher und Systemscans messen, bevor Leistungsziele festgelegt werden. Native Windows-GUI anhand tatsächlicher Speicher-, Start-, Packaging- und Barrierearmutsanforderungen vergleichen, bevor die Migration beschlossen wird.

## Priorität 3: eingebettete Offline-KI

`llama.cpp` für Windows-CPU-Betrieb, Ressourcenbegrenzung, Abbruch, Isolation und Inaktivitätsende prüfen. Mindestens drei weitergebbare kompakte Instruct-Modelle einschließlich passender Qwen-Kandidaten anhand fester deutscher/englischer Systembericht-Prompts vergleichen.

Modell/Version/Quantisierung, Lizenzen, Hashes, Hardware, RAM, Ladezeit, Tokens/Sekunde, Anweisungsbefolgung und sachliche Qualität dokumentieren. Weder Modellwahl noch Benchmarkergebnis liegen vor.

Die geplante Standard-Ausgabe kann ein geprüftes optionales Modell laden; Complete muss alle Laufzeit-/Modellabhängigkeiten enthalten und ohne Netz getestet werden. Beide Pakete fehlen bisher. Endnutzer sollen weder Python, Node.js, Docker, Ollama, Cloud-Schlüssel noch kostenpflichtige APIs benötigen.

KI bleibt beratend ohne Ausführungs- oder Administratorrechte. Klassische Funktionen dürfen nicht von Modellverfügbarkeit abhängen.

## Release-Freigabe

Bestehende Funktionen erhalten, aussagekräftige Sicherheits-/Wiederherstellungs- und Windows-Tests bestehen, Offline-Pakete und Drittanbieterrechte prüfen und Artefakte mit Prüfsummen und ehrlichem Signaturstatus vorbereiten. Vor produktiver Veröffentlichung ausdrückliche Maintainer-Freigabe einholen. Einen unvollständigen Stand nicht durch Umbenennung in 3.0 als fertig darstellen.
