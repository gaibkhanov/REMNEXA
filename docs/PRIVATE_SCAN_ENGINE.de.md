[English](PRIVATE_SCAN_ENGINE.md) | [Deutsch](PRIVATE_SCAN_ENGINE.de.md)

# Private wiederverwendbare Scan-Engine — 2.2.0-rc.5

Entwicklungskandidat auf `feature/clamav-private-worker`; diese Änderung veröffentlicht kein stabiles Release. Der [rc.4-Scanbericht](CLAMAV_SCAN_PERFORMANCE.de.md) beschreibt den früheren CLI-Scanpfad und bleibt als historischer Bericht erhalten.

## Ausführung

REMNEXA kann **libclamav 1.5.4** in einem separaten Windows-Prozess wiederverwenden. Signaturen werden einmal geladen; weitere Scans nutzen die kompilierte Engine bis zum Leerlaufende, einer Konfigurations-/Datenbankänderung, einem Abbruch oder einem ausdrücklichen Stopp. Dies ist eine Alternative zu `clamd`, keine authentifizierte Konfiguration des unveränderten Daemons.

Der mitgelieferte Windows-Daemon bietet TCP ohne Authentifizierung. Ein vorgeschalteter Vermittler würde diesen Zugang bestehen lassen. Diese Implementierung öffnet **keinen TCP-Listener und keine öffentliche Named Pipe**. Nur drei ausdrücklich ausgewählte anonyme Pipe-Handles werden an den eigenen Kindprozess vererbt: Eingabe, Ergebnisse und Diagnose. Scanaufträge enthalten Dateiname und Dateiinhalt; ursprüngliche Quellpfade oder Shellbefehle erhält der Worker nicht.

Die Oberfläche verarbeitet eine auf Datenträger gespeicherte Dateiliste. Ein begrenztes Fenster beschränkt offene Aufträge und umsortierte Antworten. Ergebnisse erreichen die bestehende Fortschritts-/Ergebnisverarbeitung in der Reihenfolge der Liste. Doppelte, fehlende oder ungültige Antworten führen zum Scanfehler. Es gibt keinen Cache sauberer Dateien: Jeder weitere Scan übergibt die ausgewählten Dateien erneut. Größenlimits und Zugriffsprobleme bleiben sichtbar und lösen keine Malware-Quarantäne aus.

## Ressourcen und Lebenszyklus

| Modus | Maximale native Threads | CPU-Obergrenze | Prozesspriorität |
|---|---|---|---|
| Eco | 1 | 25 % | Idle |
| Balanced | 2 | 50 % | BelowNormal |
| Fast | 4 | 80 % | Normal |

Logische Kerne, verfügbarer Speicher und gemessene Auslastung begrenzen die Threads zusätzlich. Unter 4 GiB verfügbarem RAM oder bei Ressourcenknappheit wird ein Thread gewählt. Fast benötigt mindestens 6 GiB verfügbaren Speicher für vier Threads. Bei geänderten Ressourcen kann das aktive Scanfenster einer laufenden Engine verkleinert werden; bereits belegter Speicher der kompilierten Engine wird dadurch nicht verkleinert.

Ein Windows Job Object erzwingt einen Kindprozess, ein Prozess-Commit-Limit von 1,5–3 GiB und die CPU-Grenze. Das sind Obergrenzen, keine Speicherreservierung oder Leistungsversprechen. Ein Kaltstart benötigt mindestens 2 GiB verfügbaren Speicher; eine geladene Engine kann ab 512 MiB weiterverwendet werden. Pro konfigurierter Installation bleibt ein REMNEXA-Scan/Update gleichzeitig zulässig. Mehrere Anwendungsinstanzen können zwischen Scans jeweils eine eigene Engine behalten; die Speicherprüfung bleibt aktiv.

Der Worker startet angehalten, wird seinem Job zugeordnet und vor der Ausführung auf erhöhte Rechte geprüft. REMNEXA versucht ein eingeschränktes Token mit mittlerer Integrität. Scheitert dies, ist ein Standardbenutzer-Fallback nur bei einer nicht erhöhten Hauptanwendung zulässig. Ein erhöhter Fallback wird abgewiesen. Der native Worker verweigert selbst ebenfalls ein Administratortoken. Der eingeschränkte Start wurde lokal geprüft; der Start aus einer erhöhten Hauptanwendung benötigt noch einen eigenen Windows-Test.

Der Job endet mit seinem Besitzer, auch bei einem abrupten Absturz. X, Esc, Strg+C und Abbruchtoken behalten die bestehende Kennzeichnung unvollständiger Scans. Nach standardmäßig 60 Sekunden Leerlauf wird die Engine freigegeben. Updates beenden vor Dateiänderungen nur den eigenen REMNEXA-Worker. Fremde ClamAV-Prozesse, Dienste und Windows-Sicherheitseinstellungen bleiben unangetastet.

Native Archivextraktion nutzt ein zufälliges Verzeichnis mit Zugriff nur für das aktuelle Konto und SYSTEM. Beim normalen Beenden wird dieser eigene Baum entfernt. Verweigert Windows das Löschen eines unerwarteten geschützten/verlinkten Eintrags, bleibt er erhalten; Zielberechtigungen werden nicht zum Erzwingen der Löschung geändert.

Ein abrupter Absturz des Besitzers kann ein privates Extraktionsverzeichnis zurücklassen. Der Job beendet den Worker trotzdem; eine automatische Bereinigung verwaister Verzeichnisse ist nicht implementiert.

## Konfiguration und Fallback

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Set-AVConfig -Values @{
    ScanBackend = 'Auto'
    ScanEngineIdleSeconds = 60
    ScanEngineStartupSeconds = 120
}
Get-ClamAVScanEngineState
Stop-ClamAVScanEngine
```

`Auto` versucht den privaten Worker, wenn neben dem Scanner eine `libclamav.dll` liegt. Nicht unterstützte ABI/Version, Start-/Speicherfehler oder ungeeignete Limits führen **vor dem ersten Dateiscan** zum bisherigen `clamscan`-Pfad mit verständlichem Hinweis. Nach Scanbeginn entsteht bei Worker-Fehlern ein unvollständiges/fehlerhaftes Ergebnis statt eines stillen Neustarts. Ein fehlgeschlagener Start wird für diesen Konfigurations-/Datenbankfingerabdruck fünf Minuten zurückgestellt.

`ClamScan` wählt ausdrücklich den bisherigen Scanpfad. `PrivateWorker` verlangt die neue Engine und meldet Startfehler. Leerlaufzeit: 15–600 Sekunden; Startzeitlimit: 15–300 Sekunden. Der native Adapter unterstützt derzeit konfigurierte Dateilimits von 1 Byte bis 128 MiB, ein expandiertes Scanlimit von 400 MiB und 120 Sekunden native Scanzeit pro Datei. Erreichte Limits sind Hinweise auf unvollständige Prüfung, keine sauberen Ergebnisse. Für andere Dateilimits ist `ClamScan` zu verwenden. Die Parallelisierung überspringt keine Dateitypen oder Altersklassen stillschweigend.

SHA-256-Fingerabdrücke berücksichtigen die Engine-DLL und jede Datei im flachen Datenbankverzeichnis, nicht nur Änderungszeiten. Änderungen verhindern die Wiederverwendung und laden Signaturen neu. HTTPS, Hashprüfung, Staging, Rücksicherung und ausdrückliche Updatebestätigung bleiben erhalten. Ein Scanstart lädt oder aktualisiert keine Komponenten.

## Sicherheitsgrenzen und Lizenzen

Private Handles, reduzierte Rechte, begrenzte Nachrichten und Job-Limits verringern die Angriffsfläche. Dies ist **kein AppContainer und keine vollständige Sandbox gegen eine native Sicherheitslücke**. Ein Standardbenutzerprozess kann weiterhin auf für sein Konto freigegebene Ressourcen zugreifen. Pfadprüfungen reduzieren Linkangriffe, garantieren jedoch keine vollständig rennbedingungsfreie Dateiverarbeitung. Engine und Signaturen müssen vertrauenswürdig und aktuell bleiben.

PowerShell-Oberfläche und IPC-Transport bleiben MIT-lizenziert. Der optionale Adapter `Antivirus/Workers/NativeEngine.cs` und `NativeScan.ps1` steht unter **GPL-2.0-or-later**; der [Lizenztext liegt bei](../Antivirus/Workers/COPYING.txt). ClamAV und Abhängigkeiten behalten ihre eigenen Lizenzen. Das Quell-ZIP enthält Adapterquellen, keine ClamAV-Binärdateien, Datenbanken oder PowerShell. Siehe [Drittanbieterhinweise](THIRD_PARTY_NOTICES.de.md).

## Reproduzierbare Prüfungen

Lokal bestanden **177/177 Tests mit Pester 5.7.1**, einschließlich bestehender Scan-/Update-/Quarantänetests und 17 neuer Regressionstests für die private Engine. Neunzig PowerShell-Dateien wurden ohne Syntaxfehler geparst. PSScriptAnalyzer 1.24.0 meldete **0 Fehler**, 484 Warnungen und 66 Informationshinweise; die Warnungsbasis bleibt offen. Das [native Prüfprotokoll](benchmarks/private-engine-native-rc5.json) bestätigt eigene Signatur-/Archiverkennung, Wiederverwendung, Leerlaufende, öffentlichen Startabbruch und private temporäre ACLs. Kein EICAR oder echte Malware wurde auf dem Rechner abgelegt.

Die 17 neuen Regressionstests bestanden auch mit Pester 3.4.0; die vollständige Suite lief mit 5.7.1. Alle zwölf Anwendungsselbsttests bestanden für rc.5.

Zwei Durchläufe in wechselnder Reihenfolge scannten dieselben 1.000 harmlosen Dateien mit festem Seed (4.608.000 Bytes) und installierten Signaturen auf einem Windows-/SSD-Rechner mit acht logischen Kernen. Während des Zeitvergleichs liefen keine Tests oder weiteren REMNEXA-Scans; normale Systemaktivität bleibt eine Schwankungsquelle.

| Mittlere Messung | CLI | Privat, kalt | Privat, warm |
|---|---|---|---|
| Gesamte Scanzeit | 88,82 s | 75,65 s | 10,07 s |
| Zeit bis zum ersten Dateiergebnis | 39,02 s | 45,92 s | 2,78 s |
| Erfasste Scanner-CPU-Sekunden | 84,02 s | 94,43 s | 5,43 s |
| Erfasste CPU, Anteil am gesamten Rechner | 11,83 % | 15,61 % | 6,77 % |
| Maximaler erfasster Scanner-Arbeitssatz | 971,88 MiB | 1.132,70 MiB | 1.132,70 MiB |

Die Gesamtzeit sank bei diesem Datensatz **kalt um 14,83 %** und **warm um 88,67 %**. Kaltstart/erstes Ergebnis waren langsamer, die kalte CPU-Arbeit stieg. Der native Prozess benötigte ungefähr **160,82 MiB mehr Spitzen-RAM**, ohne Oberfläche. Der warme Höchstwert enthält die Initialisierung. Signaturen bleiben zwischen Scans bis zum Leerlaufende im RAM; das ist eine Abwägung zwischen Geschwindigkeit und Speicher. Zwei Wiederholungen belegen keine allgemeine Beschleunigung.

Die Pester-Suite prüft Protokoll, begrenzte Warteschlangen, Ressourcenregeln, doppelte Antworten, Zugriffs-/Limithinweise und das Beenden eigener Prozesse. `tools/Test-ClamAVPrivateEngine.ps1` benötigt zusätzlich eine lokale ClamAV-1.5.4-Installation und prüft eine harmlose eigene Signatur, ZIP-, Unicode-/Leerdateien, Wiederverwendung und natives Leerlaufende. Installierte Datenbanken werden nicht verändert.

`tools/Measure-ClamAVPrivateEngine.ps1` vergleicht CLI-, kalte und warme private Scans identischer harmloser Zufallsdaten mit festem Seed. Keine Downloads oder Quarantäne. CPU-/RAM-Stichproben erfassen den Scannerprozess, nicht die Oberfläche. Siehe [Messdaten](benchmarks/private-engine-rc5.json). SSD/HDD-Vergleich, VMs mit wenig Speicher, der Start aus einer erhöhten Hauptanwendung und ein breiter Malware-Testbestand bleiben eigene Prüfschritte. Lokale Ergebnisse sind keine allgemeinen Geschwindigkeits- oder Schutzgarantien.

```powershell
./tools/Test-ClamAVPrivateEngine.ps1 -TestStartupCancellation
./tools/Measure-ClamAVPrivateEngine.ps1 -FileCount 1000 -Repetitions 2
```

Die optionale Abbruchprüfung lädt die installierte Datenbank nur bis zum Start des echten Workers, bricht über die öffentliche Scan-API ab und prüft Prozess-/Dateibereinigung sowie die ACL des privaten Verzeichnisses. Passende Engine-Version und installierte Datenbanken sind Voraussetzung; kein Update wird angefordert.

Quellpakete entstehen aus einem sauberen Commit mit `tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.5'`. Sie enthalten ein Dateimanifest und eine SHA-256-Begleitdatei für das Archiv. `tools/Test-RemnexaPackage.ps1` prüft sie. Diese Quellartefakte enthalten weder Laufzeit noch Scanner und sind kein Installer oder stabiles Release.
