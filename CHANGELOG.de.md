[English](CHANGELOG.md) | [Deutsch](CHANGELOG.de.md)

# Änderungsprotokoll

Entwicklungsänderungen sind keine veröffentlichten Releases. Dieses Dokument verändert keine vorhandenen Release-Dateien oder Tags.

## 2.2.0 — Entwicklung, nicht veröffentlicht

### Kandidat 2.2.0-rc.3

- Stille asynchrone ClamAV-Metadatenprüfung für Engine/Datenbanken mit konfigurierbaren Zeitlimits, standardmäßig 24 Stunden Cache, begrenzten Wiederholungen/Wartefristen und Beenden eigener Prüfprozesse.
- Getrennter semantischer Engine-Vergleich und offizielle Datenbank-TXT-/Headerversionen; unbekannte, veraltete oder offline ermittelte Angaben erscheinen nicht als aktuell.
- Antivirus-Auswahl U/I, bestätigte komponentenbezogene Updates und eine Updateentscheidung je Scan mit gesonderter Zustimmung nach Fehlern.
- Atomarer Updatezustand und exklusive Metadaten-/Updatesperre; fehlende Prüfsummen, nicht vertrauenswürdige Paketquellen und Downgrades bleiben gesperrt.
- Alle sechs Oberflächensprachen sowie Anleitungen auf Englisch/Deutsch. Vorhandene Antivirus-Nummern/APIs und rc.2-Fortschrittsanzeigen bleiben erhalten. [Verhalten und Prüfung](docs/CLAMAV_SMART_UPDATES.de.md).

### Kandidat 2.2.0-rc.2

- Gemeinsamer messbarer/unbestimmter Fortschritt, aktuelle Phasen/Einträge, Laufzeit, Eingabewarten und beschriftete Farben in den Verarbeitungsbereichen.
- Laufende Prozessausgabe und Lebenszeichen mit begrenzter Ergebniserfassung und Aufräumen eigener Prozesse bei Callback-Fehlern.
- Zusammengefasste Antivirus-Erfassung, Dateirückmeldungszähler und ausdrückliche Teil-/Fehlerergebnisse statt fester Scanphasen-Prozente.
- Fortschrittstexte in sechs Sprachen und zusätzliche Regressionstests. Siehe [Verhalten, Prüfung und offene Arbeit](docs/RELEASE_2.2.0_RC2.de.md). Die Veröffentlichung bleibt zurückgestellt.

### Kandidat 2.2.0-rc.1

- Prozess-Zeitlimits fordern das Beenden des gestarteten Prozessbaums an und warten begrenzt auf Aufräumen. Ausgabeabschluss teilt das Zeitlimit; leere Argumente bleiben erhalten.
- Quellsicherungen schließen oberste Git-Metadaten, erzeugte Pakete und alte Zwischenordner aus; die Standardversion entspricht dem Kandidaten.
- Paketierung eines sauberen Commits erzeugt ZIP, internes Datei-SHA-256-Manifest und Archiv-Prüfsumme. Vorhandene Ausgaben werden nie überschrieben.
- Prüfung weist geänderte Inhalte, fehlende/nicht gelistete Dateien, unsichere Pfade, auch bei Groß-/Kleinschreibung doppelte Namen und falsche Archiv-Prüfsummen ohne Entpacken ab.
- CI baut, prüft und lädt den Quellkandidaten als Workflow-Artefakt hoch; sie veröffentlicht kein GitHub-Release.
- Kosmetisches Bildschirmleeren lässt den Start bei fehlenden Cursor-APIs, einschließlich umgeleiteter Ausgabe, nicht mehr abbrechen.
- Regressionstests wachsen auf 89 Fälle einschließlich echten Starts/Beendens im Hauptmenü. Siehe [Prüfstand und Grenzen](docs/RELEASE_2.2.0_RC1.de.md).

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
