[English](INDEPENDENT_SCANS.md) | [Deutsch](INDEPENDENT_SCANS.de.md)

# Unabhängige Antivirus-Scans — 2.2.0-rc.8

Entwicklungskandidat auf `feature/independent-antivirus-session`; kein stabiles Release veröffentlicht. Er ersetzt das Abbrechen beim Beenden aus dem [rc.7-Hintergrundscan](BACKGROUND_SCANS.de.md).

## REMNEXA während des Scans nutzen

Interaktive Antivirus-Scans starten jetzt ein separates PowerShell-Fenster. Nutze die Hauptanwendung weiter oder öffne **B** im Antivirus-Menü beziehungsweise **/scan** an einer Anwendungseingabe für Status und Befunde. Auch das Scanfenster unterstützt **P** (Pause), **R** (Fortsetzen) und **C** (Abbrechen). Engine-Auswahl, Ressourcenlimits, Offline-Scans, Updatesperren und bewusste Quarantäneentscheidungen bleiben erhalten.

Beim Beenden von REMNEXA über die Menüs oder **X** während eines aktiven Scans erscheint:

- **1 — Scan fortsetzen und nur REMNEXA beenden.** Ein pausierter Scan wird vor dem Trennen fortgesetzt. Das separate Antivirus-Fenster geöffnet lassen.
- **2 — Scan abbrechen und REMNEXA beenden.** Auf die Abbruchbereinigung warten; bisherige Befunde bleiben mit unvollständiger Abdeckung erhalten.
- **0 — Zur Anwendung zurückkehren.** Der Scanzustand bleibt unverändert.

Wird die Hauptanwendung außerhalb dieser Abfragen geschlossen oder erzwungen beendet, kann keine Bestätigung erscheinen; der unabhängige Scan läuft weiter. Das Schließen des separaten **Scanfensters** beendet dessen eigenen Scanner. Abmeldung, Windows-Herunterfahren und Beenden des Scanprozesses werden von der Fortsetzen-Option nicht überbrückt. Es werden weder Dienst noch geplante Aufgabe installiert.

Das Scanfenster zeigt tatsächliche Verarbeitungszahlen und verfügbare Befunde. Prozentwerte benötigen eine erfasste Gesamtzahl und garantieren keine vollständige Abdeckung. Befundanzeigen in Hauptanwendung und Scanfenster bereinigen Steuerzeichen. Eine Pause behält Scannerspeicher und möglicherweise Dateisperren bei. Verschwindet die Hauptanwendung während einer Pause ohne Auswahl 1, setzt **R** im Scanfenster den Scan fort.

## Zuständigkeit, Ergebnisse und Bereinigung

Der Scanhost besitzt den bisherigen Runspace und seine Scannerprozesse. Der native Worker behält sein eingeschränktes Token und die Windows-Job-Limits; auch der eigene CLI-Scanner gehört zu einem beim Schließen beendeten Job. Das Fortsetzen eines Scans verändert keine Windows-Sicherheitseinstellungen und startet keinen installierten Hintergrunddienst.

Die Steuerung nutzt begrenzte, typisierte Nachrichten über eine lokale Named Pipe für denselben Windows-Benutzer und dieselbe Berechtigungsstufe. Der Client prüft die Server-PID. Anfragen können keine beliebigen Shellbefehle enthalten. Sitzungsdaten liegen im konfigurierten ClamAV-Protokollordner unter `ScanSessions/scan-<zufällige-id>/`, mit Zugriff nur für den aktuellen Benutzer und SYSTEM. Dies ist keine Sicherheitsgrenze gegenüber anderen Programmen desselben Benutzers.

Der Status wird atomar geschrieben; Leser erlauben den atomaren Austausch. Prozessübergreifende Vorschauen enthalten höchstens 100 Befundzeilen mit jeweils maximal 2.048 Zeichen und weisen ausgelassene Befunde aus. Vollständige Endergebnisse erhalten je Scan eine eigene Datei `results-<anfrage-id>.json`. Ergebnisse können private Dateipfade enthalten; vor öffentlichem Teilen prüfen. Die jüngste Sitzung kann nach einem REMNEXA-Neustart mit derselben Konfiguration im Scanmanager eingesehen werden. Automatische Berichtslöschung und ein Berichtsbrowser sind nicht implementiert.

Solange die Hauptanwendung verbunden ist, bleibt der bisherige native Engine-Cache zwischen Scans nutzbar; abgeschlossene Sitzungen enden nach 60 Sekunden Inaktivität. Nach dem Trennen gibt der Abschluss Scanner/Cache frei und zeigt den Berichtspfad ungefähr 15 Sekunden vor dem Schließen des Fensters. Gespeicherte Berichte bleiben erhalten. Updates und Vordergrundscans geben einen inaktiven Host frei; ein aktiver Scan sperrt weiterhin widersprechende Schreibzugriffe.

## Modul-API

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Start-ClamAVBackgroundScan -ScanType Quick -Language de
Get-ClamAVBackgroundScan
Set-ClamAVBackgroundScan -Action Pause
Set-ClamAVBackgroundScan -Action Resume
Disconnect-ClamAVBackgroundScan -Resume # nach Ende des Aufrufers weiterscannen
# Ausdrücklicher Abbruch ist getrennt:
Stop-ClamAVBackgroundScan
Get-ClamAVBackgroundScan -IncludeResults
```

Das Entladen eines Moduls trennt dessen selbst gestartete Scans, statt sie abzubrechen. Synchrone Scan-APIs bleiben synchron. Der unabhängige Host benötigt die vorhandene PowerShell-7.5+-Laufzeit und eine Windows-Sitzung mit Konsolenunterstützung; ClamAV und Signaturen werden dadurch nicht mitgeliefert.

## Prüfung

`tests/IndependentScan.Tests.ps1` prüft das tatsächliche Ende des erzeugenden Prozesses, Pause/Fortsetzung vor dem Trennen, unerwartetes Verschwinden des Elternprozesses, ausdrücklichen Abbruch, Befund-/Berichtserhalt, Fernsteuerung, ungültige Befehle/Server-PID und erzwungenes Scanhost-Ende samt CLI-Kindprozessbereinigung. `tests/ScanExitChoice.Tests.ps1` prüft Fortsetzen/Abbrechen/Zurück, fehlgeschlagene Bereinigung, Rückkehr zur ursprünglichen Eingabe und alle sechs Sprachen. Die bisherigen Runspace-, Worker-, Update-, Quarantäne- und Navigationstests bleiben erhalten.

Abschließende lokale Regression mit PowerShell 7.6.9 und Pester 5.7.1: **204 bestanden, 0 fehlgeschlagen, 0 übersprungen**. Alle 106 PowerShell-Dateien sind syntaktisch gültig und bestehen die PSScriptAnalyzer-1.24.0-Fehlerprüfung. Links und Prüfungen auf private Pfade in der geänderten Dokumentation bestehen. Nach dem Testlauf bleiben keine Test-Scanhosts aktiv.

`tools/Test-ClamAVIndependentScan.ps1` lief mit installiertem ClamAV 1.5.4 über CLI und privaten nativen Worker gegen **jeweils 2.501 harmlose Dateien und einen benutzerdefinierten Hash-Signaturtreffer**. Jeder erzeugende Prozess endete bei noch aktivem Scan, ein pausierter Scan wurde vor dem Trennen fortgesetzt und der Scan endete mit vollständiger Testabdeckung und gespeichertem Bericht. Keine automatische Quarantäne, keine Prüfung persönlicher Ordner und keine Änderung installierter Datenbanken. Siehe [bereinigtes Prüfprotokoll](benchmarks/rc8-independent-scan.json). Diese eigene HDB-Testsignatur prüft den Lebenszyklus, nicht Malware-Erkennungsleistung oder die Geschwindigkeit mit vollständiger Datenbank.

Getestet wurde auf dem vorhandenen Windows-11-SSD-Rechner mit 16 GB RAM. Windows 10 wird in aktuellen Entwicklungsständen nicht unterstützt. Echte 8-GB-VM, HDD und Malware-Labor bleiben ungeprüft. Remote-CI ist eine eigene Prüfung; bestandene lokale Tests belegen keinen erfolgreichen GitHub-Lauf. Die bisherigen [Lizenzgrenzen der nativen Engine](PRIVATE_SCAN_ENGINE.de.md) gelten weiter.

Quellpaket aus einem sauberen Kandidaten-Checkout bauen und prüfen:

```powershell
$package = ./tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.8'
./tools/Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Das Quell-ZIP enthält weder gebündelte Laufzeit, ClamAV, Signaturen, Installer noch digitale Signatur.
