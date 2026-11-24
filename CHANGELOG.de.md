[English](CHANGELOG.md) | [Deutsch](CHANGELOG.de.md)

# Änderungsprotokoll

Entwicklungsänderungen sind keine veröffentlichten Releases. Dieses Dokument verändert keine vorhandenen Release-Dateien oder Tags.

## Nicht veröffentlicht — Windows-Launcher-Vorschau

- Complete zum Standard-Benutzerpaket machen: festgelegtes PowerShell 7.7.0, portables ClamAV 1.5.5, geprüfte FreshClam-Signaturstände, Laufzeitabhängigkeiten, Lizenzhinweise und passenden ClamAV-Quellcode bündeln. Unvollständige oder veraltete Builds abweisen; Standard nur ausdrücklich als Entwicklerprofil wählen.
- Upstream-Archiv-/Laufzeitbytes und Signaturintegrität prüfen, lokale Updater-Zustände ausschließen und Datenbankzeitstempel im ZIP erhalten. Isolierte Sicherheitsregressionen für den Paketbau ergänzen und Standard-CI-Artefakte als Entwicklerbuilds kennzeichnen.

- Gespeicherte Antivirus-Historie vom Live-Status trennen: datierte Übersicht auf der Startseite, H und /scans, bedingte Seitennavigation und klare Hinweise bei unvollständigen Scans. Einzelne Durchläufe bei Wiederverwendung des Scanfensters erhalten und alte Stände ohne erfundene Zeitangaben lesen.
- Benutzerordner mit einer EXE, kurzer README, app/ und optional runtime/ erläutern; Quellcode und kompatible Starter bleiben im Entwicklungsordner.

- Wiederholte Fortschrittsmeldungen und überlagerte Downloadbalken beheben. Tatsächliche Downloadbytes, abbrechbare begrenzte HTTPS-Übertragung und deutlichen Hinweis auf Aktualisierung vor dem Scan anzeigen; ein Abbruch startet keinen Scan.
- Wiederholtes Löschen der Scan-Konsole durch eine stabile Pufferaktualisierung ersetzen, Quick Edit nur im betroffenen Fenster deaktivieren, direkte P/R/C-Steuerung erhalten und U zum Aktualisieren der Momentaufnahme in der Hauptanwendung ergänzen. Isolierte Konsolen-/Maus-, Downloadfehler- und Abbruchtests hinzufügen.

- Windows 11 oder neuer (Client-Build ab 22000) in nativem Launcher und PowerShell-Einstieg voraussetzen; Windows 10/älter/Server vor Anwendungsinitialisierung abweisen, Hinweise in sechs Sprachen und Regressionstests der Versionsgrenzen ergänzen. Vorhandene Release-Artefakte bleiben unverändert.
- Optionale SHA-256-Authenticode-Signierung mit HTTPS-RFC-3161-Zeitstempeln, Prüfung von Zertifikat und Werkzeug, Verifikation vor Paketprüfsummen sowie isolierten Regressionstests. Das aktuelle Paket bleibt mangels Signierzertifikat und Werkzeug unsigniert.
- Nativen x64-Win32-Launcher mit offiziellem Mehrgrößen-Icon, geprüfter PowerShell-Auswahl und sicherer Argumentübergabe ergänzen; keine Policy-Umgehung oder pauschale Erhöhung.
- Erlaubnisbasiertes Benutzerpaket mit einer EXE, app/ und optionaler lizenzierter Laufzeit bauen; Entwicklerdateien und Backups ausschließen.
- Kompatible Quellcode-Starter erhalten, examples vereinheitlichen und lokale Backups mit Integritätsprüfung außerhalb des Repositorys aufbewahren.
- [Build, Struktur und Grenzen](docs/WINDOWS_LAUNCHER.de.md); bestehendes stabiles Release unverändert.

## 2.2.0 — 2026-11-21

### Stabiles Quellrelease

- Geprüften rc.8-Funktionsstand als 2.2.0 übernehmen; frühere Kandidatenberichte bleiben historische Prüfprotokolle.
- Quell-ZIP, SHA-256-Prüfsumme und englische/deutsche Release Notes; keine gebündelte Laufzeit, ClamAV-Datenbank, KI oder Installer.
- rc.8-GitHub-CI erfolgreich bestätigt. Der endgültige Release-Stand wird vor Veröffentlichung erneut geprüft. Siehe [Prüfstand und Grenzen](docs/RELEASE_2.2.0.de.md).

### Kandidat 2.2.0-rc.8

- Interaktive Scans laufen im unabhängigen PowerShell-Fenster; die Hauptanwendung kann beendet werden, während der Scan weiterläuft.
- Fortsetzen/Abbrechen/Zurück beim Beenden mit aktivem Scan; pausierte Scans vor bestätigtem Fortsetzen wieder aufnehmen und Befunde beim Abbruch erhalten.
- Lokale Pipe-Steuerung für denselben Benutzer/dieselbe Berechtigungsstufe, atomare private Status-/Ergebnisdateien, erneuter Zugriff auf die jüngste Sitzung und Bereinigung eigener CLI-Prozesse beim Ende des Scanhosts.
- Nativen Cache bei verbundener Anwendung wiederverwenden, nach getrenntem Abschluss freigeben und neue Bedienelemente in sechs Sprachen übersetzen.
- Ende des erzeugenden Prozesses mit echtem CLI-/Privat-Worker und jeweils 2.501 harmlosen Dateien geprüft. Siehe [Bedienung und Prüfgrenzen](docs/INDEPENDENT_SCANS.de.md). Kein stabiles Release veröffentlicht.

### Kandidat 2.2.0-rc.7

- Interaktive Antivirus-Schnellscans und benutzerdefinierte Scans laufen in einem Hintergrund-Runspace, während andere REMNEXA-Werkzeuge bedienbar bleiben.
- **B** und die globale Eingabe **/scan** öffnen Status/Befunde, Pause/Fortsetzung, Abbruch und eine ruhige Befund-Momentaufnahme; Texte in allen sechs Sprachen ergänzt.
- Ein aktiver Scan pro Installation; Befunde bleiben beim Abbruch erhalten und der Abschluss erscheint erst nach Ergebnissammlung/Bereinigung. Das Beenden von REMNEXA bricht den Scan ab.
- Pause/Fortsetzung und Abbruch aus der Pause mit echtem CLI-/Privat-Worker und jeweils 2.501 harmlosen Dateien geprüft. Siehe [Verhalten und Prüfgrenzen](docs/BACKGROUND_SCANS.de.md).

### Kandidat 2.2.0-rc.6

- Start des eingeschränkten Workers aus einer erhöhten Hauptanwendung korrigiert: ausdrücklicher Zugriff für aktuellen Benutzer/SYSTEM auf Token-Vorgaben und Prozess-/Threadobjekte.
- Echte Windows-CPU-/Speicher-/Prozesslimits und Scans mit vollständigen Signaturen unter 1,5-GiB-Prozessgrenze geprüft; Speicherfreigabegrenzen werden gezielt simuliert.
- Elf harmlose Fälle zwischen nativem und CLI-Scan verglichen: verschachteltes ZIP, GZip, TAR, Größenlimits, Dateisperren, Wiederverwendung und Neuladen geänderter Signaturen ohne Änderung installierter Datenbanken.
- CI-Hostdiagnosen, Testberichte unter `dist/` und Auswahl genau eines Git-Programms bei mehreren PATH-Treffern für die Quellpaketierung ergänzt.
- Siehe [Prüfprotokolle und fehlende VM-/HDD-Abdeckung](docs/RELEASE_2.2.0_RC6.de.md). Kein stabiles Release veröffentlicht.

### Kandidat 2.2.0-rc.5

- Wiederverwendbare native ClamAV-1.5.4-Engine mit vererbten privaten Pipes statt eines nicht authentifizierten TCP-Daemons. Engine-/Signaturupdates beenden den eigenen Cache und machen ihn ungültig.
- Begrenzte native Parallelität und Ergebnisumsortierung, reduzierte Worker-Rechte, Job-Limits für CPU/Speicher sowie Beenden bei Abbruch, Leerlauf oder Ende des Besitzers.
- CLI-Fallback bei nicht unterstützter Startkonfiguration; vollständige Dateizählung, ausdrückliche Limit-/Fehlerergebnisse sowie bestehende Update-/Quarantänekontrollen bleiben erhalten.
- Neue Start-/Wiederverwendungs-/Fallbacktexte in sechs Sprachen, Lebenszyklus-APIs, reproduzierbare native Tests und Kalt-/Warmscan-Benchmarks. Optionaler verlinkter Adapter unter GPL-2.0-or-later; Oberfläche/Transport bleiben MIT.
- Siehe [Implementierung und Prüfgrenzen](docs/PRIVATE_SCAN_ENGINE.de.md). Kein stabiles Release wird erstellt.

### Kandidat 2.2.0-rc.4

- Verzeichniseinträge über verzögert gelesene .NET-Enumeratoren in eine temporäre Dateiliste schreiben; keine vollständigen Verzeichnisinhalte und bestätigten Dateipfade im Speicher sammeln.
- Native Ausgabe bei verfügbaren Daten lesen, unnötige Wartezeiten und ausführliche Scannerzeilen vermeiden; Versions- und Signaturwerkzeuge beim reinen Scan-Vorabcheck nicht mehrfach starten.
- Antivirus P mit Eco/Balanced/Fast, gemessener Ressourcenanpassung, einem Scanprozess je konfigurierter Installation und mindestens 2 GiB freiem Arbeitsspeicher. Prioritäten sind keine Thread- oder festen Speicherlimits.
- Dateierfassung/Scan per X, Esc, Strg+C oder Cancellation Token abbrechen; eigene Prozesse beenden und bereits gefundene Hinweise als unvollständige Ergebnisse erhalten.
- Größen- und Rekursionslimits als unvollständige Hinweise statt Malware melden; solche Hinweise nie in Quarantäne verschieben. Bisherige Update- und Quarantäneschutzprüfungen bleiben erhalten.
- Updatebedienung und sechs Oberflächensprachen erhalten. [Messungen, Umfang und Prüfstand](docs/CLAMAV_SCAN_PERFORMANCE.de.md).

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
