[English](RELEASE_2.2.0_RC6.md) | [Deutsch](RELEASE_2.2.0_RC6.de.md)

# 2.2.0-rc.6 — Worker-Prüfung und Korrekturen

Entwicklungskandidat auf `fix/clamav-worker-validation`. Dieser Nachfolger bearbeitet die offenen Prüfungen aus [rc.5](PRIVATE_SCAN_ENGINE.de.md); er ist kein stabiles Release und kein REMNEXA 3.0.

## Korrigierter Start mit erhöhter Hauptanwendung

Eine tatsächlich per UAC erhöhte Hauptanwendung reproduzierte einen Fehler beim Worker-Handshake. Ein eingeschränktes Token muss auf seine eigenen Prozessobjekte zugreifen können, auch wenn der Ersteller erhöht läuft. Der Starter gewährt dem aktuellen Benutzer und SYSTEM nun ausdrücklich Zugriff über die Standard-DACL des Tokens und die Sicherheitsdeskriptoren des neuen Prozesses/Startthreads. Er verlässt sich nicht auf einen geerbten Deskriptor nur für Administratoren. Vererbungsliste mit drei Handles, eingeschränktes Token mittlerer Integrität, Ablehnung erhöhter Worker und Job-Limits bleiben erhalten.

Die Wiederholungsprüfung bestand mit normaler und erhöhter Hauptanwendung. Der erhöhte Test umfasste die echte native Bibliothek, harmlose eigene Signaturen, Archiverkennung, Wiederverwendung, Leerlaufende, Abbruch über die öffentliche Scan-API und Prüfung privater Verzeichnis-ACLs. Der Worker selbst blieb ohne Administratorrechte. Siehe [Host-Prüfprotokoll](benchmarks/rc6-worker-host.json).

## Speicher- und Ressourcenprüfungen

Der Testrechner hat ungefähr 16 GiB physischen RAM und eine SSD. Eine eingerichtete Windows-Sandbox-/Hyper-V-Testumgebung und eine HDD fehlen. Die folgenden Prüfungen behaupten keinen 8-GiB-VM- oder physischen HDD-Test.

- Simulierte verfügbare Speichermengen prüfen die Startgrenze von 2 GiB und die Wiederverwendungsgrenze von 512 MiB, ohne den Host-RAM auszuschöpfen.
- Ein echter Scan lädt die vollständige installierte Signaturdatenbank mit einem Thread unter einem tatsächlichen **Windows-Prozess-Commit-Limit von 1,5 GiB**. Er bestand und nutzte denselben Worker an der simulierten Warmstartgrenze weiter. Unter der Grenze wurde der Scan abgewiesen und der eigene Worker beendet.
- Beobachtet wurden nach dem Scan 1.103.081.472 private Bytes und ein maximaler Arbeitssatz von 1.178.931.200 Bytes. Privater Commit und Arbeitssatz sind unterschiedliche Zähler.
- Ein Kindprozess fragt den Windows-Kernel nach Speicherlimit, CPU-Obergrenze, Ein-Prozess-Limit und Beenden beim Schließen ab. Er prüft außerdem die Standard-DACL des eingeschränkten Tokens. Es wird kein Speicher bis zum Versagen belegt.

Siehe [Speicher-Prüfprotokoll](benchmarks/rc6-worker-memory.json). Die Ressourcenmeldung ist simuliert; Scans und Windows-Job-Grenzen sind real. Systemweite Speicherknappheit, Paging und HDD-Zeiten benötigen weiterhin die fehlenden Testumgebungen.

## Erweiterter harmloser Scanbestand

Elf Fälle decken sauberen Text, Unicode-, Leer- und Zufallsdateien, direkte Erkennung einer eigenen Signatur, sauberes ZIP, ZIP mit Treffer, verschachteltes ZIP, GZip, TAR und einen ausdrücklichen Dateilimit-Hinweis ab. `clamscan` und private Engine lieferten die erwarteten Kategorien. Eine exklusiv geöffnete Datei erzeugte in beiden Scanpfaden einen Fehler statt eines sauberen Ergebnisses.

Geprüft werden außerdem Wiederverwendung bei unveränderten Signaturen und automatisches Neuladen nach Änderung der isolierten eigenen Signaturdatenbank. Installierte Signaturen bleiben unverändert. Keine Quarantäne, kein EICAR und keine echte Malware. Dies prüft Format- und Ablaufverhalten, nicht die Erkennungsleistung gegen einen realen Malware-Bestand. Siehe [Prüfprotokoll des Testbestands](benchmarks/rc6-worker-corpus.json).

## CI und Wiederholung

Der GitHub-Lauf für rc.5 scheiterte an Worker-Tests. Nach der Startkorrektur bestanden Worker-Vorprüfung, Pester-Tests und Analyseprüfung auf GitHub; der nächste Fehler betraf die Quellpaketierung. Testberichte werden nun ausdrücklich im ignorierten `dist/` abgelegt, unabhängig von Gits Behandlung der Groß-/Kleinschreibung. Ein Regressionstest prüft beide Pester-Berichtsschreibweisen mit strikt vergleichender Git-Konfiguration. Buildfehler erhalten eine begrenzte Diagnoseannotation statt nur eines Exit-Codes.

Der Paketfehler entstand durch mehrere `git`-Programme im PATH des Runners, die als ein gemeinsamer Programmpfad behandelt wurden. Der Paketbauer wählt nun die erste passende Anwendung; ein Regressionstest reproduziert mehrere Fundstellen. CI bewahrt Host-/Pester-Berichte auf und beendet überholte Läufe desselben Branches. Den aktuellen Remote-Status zeigt der [Qualitätsworkflow](https://github.com/gaibkhanov/REMNEXA/actions/workflows/quality.yml).

Der korrigierte Code bei `5b8f622` bestand den [vollständigen GitHub-Qualitätslauf](https://github.com/gaibkhanov/REMNEXA/actions/runs/44920947626), einschließlich Tests, Analyse, Quellpaketierung, Integritätsprüfung und Artefakt-Upload. Lokal bestanden 181 Tests vor dem letzten zusätzlichen Paket-Regressionstest; anschließend bestanden alle acht Pakettests separat. Vierundneunzig PowerShell-Dateien wurden ohne Syntaxfehler geparst; Analyzer 1.24.0 meldete null Fehler, 492 Warnungen und 69 Informationshinweise. Die Warnungsbasis bleibt offen.

Gezielte lokale Prüfungen mit bereits eingerichteter ClamAV-1.5.4-Installation:

```powershell
./tools/Test-ClamAVWorkerHost.ps1 -IncludeNativeEngine
./tools/Test-ClamAVMemoryPolicy.ps1
./tools/Test-ClamAVCorpus.ps1
```

Den Host-Test zusätzlich aus einer erhöhten PowerShell ausführen, um diese Startkonfiguration zu prüfen; nur diese isolierten Tests sind dort notwendig. Sie aktualisieren ClamAV nicht, verändern keine Windows-Sicherheitseinstellungen und scannen keine persönlichen Ordner.

Quellpakete nutzen einen sauberen Commit, Version `2.2.0-rc.6`, ein Dateimanifest und eine SHA-256-Begleitdatei. Das ZIP enthält weder PowerShell noch ClamAV-Binärdateien oder Datenbanken. Vorhandene Kandidaten werden nicht überschrieben. Oberfläche/Transport bleiben MIT-lizenziert; der optionale native Adapter bleibt GPL-2.0-or-later gemäß [Drittanbieterhinweisen](THIRD_PARTY_NOTICES.de.md).

## Verbleibende Grenzen

Eine echte Windows-VM mit 8 GiB RAM, HDD-Messungen und ein kontrolliertes Malware-Labor stehen weiterhin nicht zur Verfügung. Die native Engine läuft noch nicht in einer vollständigen Sandbox gegen Exploits. Automatisches Bereinigen von Extraktionsverzeichnissen nach abruptem Besitzerabsturz ist nicht implementiert. Bestehende Analysewarnungen gelten nicht als behoben. Ein stabiles Release benötigt eigene Validierung und Freigabe.
