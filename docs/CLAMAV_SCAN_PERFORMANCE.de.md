[English](CLAMAV_SCAN_PERFORMANCE.md) | [Deutsch](CLAMAV_SCAN_PERFORMANCE.de.md)

# ClamAV-Scanleistung — 2.2.0-rc.4

Dies ist ein Entwicklungskandidat auf `feature/clamav-scan-performance`, kein stabiles Release. Nach Quellcodeänderungen die Anwendung neu starten.

## Scanverfahren und Umfang

Ausgangsstand (`c95b462`) und Kandidat verwenden **einen `clamscan.exe`-Prozess je Scan**, mit allen bereinigten Zielpfaden in einer gemeinsamen UTF-8-Dateiliste. Signaturen werden einmal je Prozess geladen. Ein späterer Scan lädt seine Datenbank erneut; es gibt keinen inkrementellen Sauber-Dateien-Cache, der nach Signaturupdates veralten könnte.

Das installierte Windows-Paket ClamAV 1.5.4 enthält `clamd`, `clamdscan`, `MaxThreads` und `MaxQueue`. Seine Windows-Konfiguration bietet TCP; laut mitgelieferter offizieller Protokolldokumentation ist TCP nicht authentifiziert. Ein lokaler Scanner mit erhöhten Rechten würde den Zugriff auf Dateien und Daemon-Befehle erweitern. Ein sicherer, benutzerbezogener authentifizierter Endpunkt wurde hier nicht hergestellt. Deshalb bleibt das bisherige Prozessverfahren erhalten. Es werden keine Daemons, Dienste, Ports, Firewallregeln oder Fremdinstallationen angelegt, kontaktiert oder umkonfiguriert. Scanübergreifende Datenbankwiederverwendung und Engine-Multithreading sind **nicht implementiert**. Stattdessen werden keine zusätzlichen signaturspeicherintensiven Prozesse gestartet.

Quick/Full/Custom behalten ihre bisherigen Suchbereiche. Quick ist kein vollständiger Laufwerksscan; die bestehende ProgramData-Suche berücksichtigt ausführbare Inhalte. Custom übergibt ausgewählte Dateien unabhängig von Endung, Alter oder Größe. Full behält die dokumentierten Windows-/Profilwurzeln und wird nicht heimlich inkrementell.

## Änderungen und Bedienung

- Eine verzögert gelesene Tiefensuche schreibt Verzeichniseinträge gepuffert in eine temporäre Liste. Der Speicherbedarf richtet sich nach Verzeichnistiefe (höchstens 1.024 offene Ebenen), expliziten Wurzeln und maximal 20 Fehlerbeispielen statt sämtlichen Kindern großer Ordner. Ausschlüsse und Reparse-Point-Prüfungen bleiben; alle übersprungenen Zähler sind sichtbar. Eine vollständig rennbedingungsfreie Traversierung über Dateihandles wird nicht behauptet.
- Scannerbestätigungen folgen der geordneten Liste auf dem Datenträger. Eine vollständige Hash-Menge bestätigter Pfade entfällt. Fehlende/unerwartete Antworten führen zu unvollständiger Abdeckung; doppelte Antworten erhöhen den Fortschritt nicht.
- Datenbereitschaft ersetzt feste Wartezeiten beim Lesen. `--verbose` entfällt, Bestätigungen sauberer Dateien bleiben. Der reine Scan-Vorabcheck startet keine zusätzlichen Versions-/sigtool-Prozesse; die ausführliche Statusfunktion behält diese Felder.
- Im Antivirus-Menü wählt **P** zwischen **Eco**, **Balanced** (Standard) und **Fast**. Gespeichert wird mit der vorhandenen atomaren Konfigurationsfunktion.

| Modus | Prozesspriorität der Engine | Gleichzeitige Scannerprozesse |
|---|---|---|
| Eco | Idle | 1 |
| Balanced | BelowNormal | 1 |
| Fast | Normal | 1 |

Freier physischer Speicher und gesamte CPU-Auslastung werden über dokumentierte Windows-APIs gemessen. Unter 3 GiB freiem RAM oder ab 80 % gemessener CPU-Auslastung sinkt die Priorität auf Idle. Unter 2 GiB freiem RAM wird ein neuer Scan mit Erklärung abgewiesen. Nicht verfügbare Messungen bleiben unbekannt. Logische Kerne werden angezeigt, aktivieren jedoch keine nicht unterstützten clamscan-Threads. Der Datenträgertyp wird nicht geraten oder zur Änderung der Abdeckung verwendet. Priorität ist ein Scheduler-Hinweis, **keine feste CPU-, I/O- oder RAM-Grenze**; der Speicherbedarf kann nach dem Vorabcheck steigen.

Ein installationsbezogener Windows-Mutex weist gleichzeitige REMNEXA-Scan-/Updateprozesse ab. So laden zwei Aufträge dieselbe Datenbank nicht parallel. Maßgeblich sind normalisierte konfigurierte Engine-/Datenbankpfade; Aliaspfade und unabhängige fremde ClamAV-Prozesse werden nicht verwaltet. Fremde Dienste bleiben unangetastet.

Während Dateierfassung/Scan brechen **X**, **Esc** oder **Strg+C** den Vorgang ab. In normalen Menüs behält X seine bisherige Funktion zum Beenden der Anwendung. Skripte können einen `CancellationToken` übergeben. Nur der eigene native Prozessbaum wird beendet. Ein Abbruch liefert `Status=Cancelled`, `CoverageComplete=false` und bereits erhaltene Funde; er bedeutet niemals einen sauberen Scan. Ausdrücklich angeforderte Quarantäne bleibt der bisherige separate Vorgang; Scanlimit-Hinweise kommen nie in Quarantäne.

Die Liveanzeige zeigt Modus, bestätigte Dateien, Funde, vergangene Zeit und die gemessene Antwortrate. Die erste Antwort enthält Initialisierung/erste Datei; die Ratenmessung beginnt dort. Prozentwerte benötigen die abgeschlossene Dateierfassung, sonst bleibt die Anzeige unbestimmt. Erfolgreiche Scanergebnisse enthalten Zeiten für Status, Erfassung, Scanner, erste Antwort und Ergebnisverarbeitung. Bisherige Größen-/Scan-/Rekursionslimits bleiben mit `--alert-exceeds-max=yes` erhalten; `Heuristics.Limits.Exceeded*` wird als sichtbarer **LimitExceeded**-Hinweis bei unvollständiger Abdeckung behandelt, nicht als Malwarediagnose.

## Messungen wiederholen

Gemessen auf Windows-Build 26300, PowerShell 7.6.9, ClamAV 1.5.4, 8 logischen Kernen, etwa 15,85 GiB installiertem RAM und SATA-SSD. Jede Version scannte dieselben 4.000 deterministischen harmlosen Dateien (18.432.000 Byte) zweimal in wechselnder Reihenfolge. Alle Durchläufe bestätigten sämtliche Dateien mit vollständiger Abdeckung. Die Datenbank-SHA-256-Werte blieben zwischen den Messrunden gleich. [Rohdaten ohne Dateipfade](benchmarks/clamav-scan-rc4.json).

| Messung | Ausgangsstand | Kandidat |
|---|---:|---:|
| Mittlere vollständige Scanzeit | 76,84 s | 73,48 s |
| Einzelmessungen | 76,05 / 77,63 s | 73,13 / 73,84 s |
| Mittlere Dateierfassung | 3,016 s | 0,380 s |
| Mittlerer Scannerprozess | 70,62 s | 72,05 s |
| Mittlere Zeit zur ersten Dateiantwort innerhalb des Scanneraufrufs | 12,54 s | 13,59 s |
| Dateien/s einschließlich Vorbereitung | 52,06 | 54,43 |
| CPU-Sekunden als Stichprobe, Anwendung + Kinder | 85,05 s | 80,54 s |
| Mittlere CPU-Stichprobe, Anteil am gesamten 8-Kern-Rechner | 13,53 % | 13,41 % |
| Maximales gleichzeitiges Working-Set als Stichprobe | 1.119,34 MiB | 1.159,83 MiB |

Die Gesamtzeit sank in diesem kleinen Vergleich um **4,37 %**, die Dateierfassung um **87,41 %**. Scannerphase und erste Antwort waren für sich langsamer; weniger Vorbereitungsaufwand ergab den Nettogewinn. Die RAM-Spitze stieg um etwa **40,50 MiB**, unter anderem einschließlich der im Prozess geladenen C#-Hilfs-/Compilerkomponenten. Dieser Benchmark belegt **keine niedrigere gesamte RAM-Spitze** und keine Engine-Thread-Beschleunigung. Ein früherer Versuch parallel zu Tests war langsamer und wurde aus diesem kontrollierten Vergleich ausgeschlossen: Prozessprioritäten machen Messungen unter Konkurrenzlast besonders variabel. Zwei Wiederholungen sind Beobachtungen, keine allgemeine Leistungsgarantie.

Benötigt werden ein Verzeichnis des Ausgangsstands und der Kandidat mit lokal eingerichteter ClamAV-Installation. Das Werkzeug lädt nichts herunter, aktualisiert keine Datenbanken und erstellt ausschließlich deterministische harmlose `.dat`-Dateien im isolierten temporären Verzeichnis. Custom-Scans laufen ohne Quarantäne, abwechselnd Ausgangsstand/Kandidat.

```powershell
./tools/Measure-ClamAVScan.ps1 -BaselineRoot ../REMNEXA-baseline -FileCount 4000 -Repetitions 2
```

Das Werkzeug benötigt `runtime/pwsh.exe` des Kandidaten; Quellpakete enthalten diese Laufzeit nicht. Berichte im ignorierten `dist/` enthalten Zähler, Zeiten und Datenbankhashes, keine gescannten Dateipfade. Temporäre Worker-/Konfigurations-/Datendateien bleiben zur Fehleranalyse im erzeugten Benchmark-Verzeichnis; vor Weitergabe oder Entfernung prüfen.

CPU und gleichzeitige Prozess-Working-Sets werden alle 100 ms erfasst, neue Kindprozesse alle 500 ms. Kurzlebige Prozess-CPU kann fehlen: Es handelt sich um Stichproben, nicht exakte Profilerwerte oder privaten zugesicherten Speicher. Datenträger-I/O-Zuordnung und HDD-Messungen wurden nicht erhoben. Parallel keine Tests, Builds oder Scans starten; Antivirusaktivität, Caches und andere Prozesse können trotzdem Einfluss haben.

## Prüfgrenzen

Regressionstests behandeln überlappende Wurzeln, doppelte/fehlende Bestätigungen, sichtbare Limitwarnungen, simulierte Offlinescans, fehlende Komponenten, Rückgabecodes, Ressourcenknappheit, gespeicherte Modi, Abbruch vor/während Verarbeitung, echte Prozessbeendigung, Ausschluss paralleler Prozesse, Menübedienung und Übersetzungsplatzhalter in sechs Sprachen. Bisherige Update-/Quarantänetests bleiben Bestandteil. Fund-/Abbruchtests simulieren Funde mit harmlosen Inhalten; auf dem Rechner wird keine EICAR-Datei angelegt.

Ein separater Praxistest brach den installierten echten clamscan während des Datenbankladens ab, lieferte einen unvollständigen Status und hinterließ null neue clamscan-Prozesse. Ein anschließender Offline-API-Scan einer harmlosen Datei mit Unicode-Dateinamen bestätigte genau eine Datei bei vollständiger Abdeckung. Datenbankupdates und Quarantäne wurden nicht angefordert.

Interaktive Pseudokonsolentests prüften außerdem **X**, **Esc** und **Strg+C** mit der echten Engine. Alle lieferten abgebrochene/unvollständige Ergebnisse und hinterließen keinen Scannerprozess. Strg+C unterbrach die äußere Test-Shell mit ihrem üblichen Fehler-Exitstatus; die Anwendung lieferte trotzdem ihr Abbruchergebnis und beendete den Scanner.

Abschließende automatisierte Prüfungen: jeweils **160 bestanden, 0 fehlgeschlagen, 0 übersprungen** unter Pester 3.4.0 und 5.7.1; 82 PowerShell-Dateien ohne Parserfehler; alle 12 Anwendungs-Selbsttests bestanden. PSScriptAnalyzer 1.24.0 meldete **0 Fehler**, 430 Warnungen und 66 Informationshinweise. Der Warnungsbestand wird nicht als behoben dargestellt.

Gemessen wurde nur die Windows-/SSD-Umgebung dieses Entwicklungsrechners. Eine 8-GiB-VM, HDD, produktive große Verzeichnisbäume, andere Terminal-Hosts und echte Malwareerkennung sind durch diese Prüfungen nicht zertifiziert. Es gibt kein pauschales Beschleunigungsversprechen und keinen Antivirus-Ersatzanspruch. Stabile Releaseprüfung und Freigabe bleiben separat.
