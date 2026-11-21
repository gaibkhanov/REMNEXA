[English](BACKGROUND_SCANS.md) | [Deutsch](BACKGROUND_SCANS.de.md)

# Antivirus-Scans im Hintergrund — 2.2.0-rc.7

Entwicklungskandidat auf `feature/antivirus-background-scans`; diese Änderung veröffentlicht kein stabiles Release. Grundlage sind die [Worker-Korrekturen aus rc.6](RELEASE_2.2.0_RC6.de.md).

## Scanverwaltung bedienen

Starte einen Schnellscan oder benutzerdefinierten Scan im bisherigen Antivirus-Menü. Der Aufruf kehrt ins Menü zurück, während ein eigener PowerShell-Runspace den Scan steuert. Du kannst zum Hauptmenü zurückgehen und andere REMNEXA-Funktionen verwenden.

- Gib `/scan` an einer normalen REMNEXA-Eingabe ein oder wähle **B** im Antivirus-Menü.
- Die Scanverwaltung aktualisiert sich in einer interaktiven Konsole alle zwei Sekunden. Andere Hosts bieten eine manuelle Eingabe zur Steuerung.
- **P** fordert eine Pause an, **R** setzt fort, **C** bricht ab und **0** kehrt ins vorherige Menü zurück, während der Scan weiterläuft.
- **D** öffnet eine ruhige Momentaufnahme der Befunde/Probleme. **0** kehrt zur Liveansicht zurück.
- **X** beendet REMNEXA. Beim Beenden wird der eigene Scan abgebrochen und aufgeräumt; er läuft nicht als unabhängiger Dienst nach Programmende weiter.

Angezeigt werden Phase, Leistungsmodus, bestätigte Dateien, Befunde, verstrichene Zeit und durchschnittliche Dateien pro aktiver Sekunde. Der Durchschnitt schließt Vorbereitung/Ladezeit ein und abgeschlossene Pausenzeiten aus; er ist keine momentane Scanrate. Prozentwerte erscheinen erst nach der Erfassung einer belastbaren Gesamtzahl. Auch die Bestätigung aller erfassten Dateien beweist keine vollständige erfolgreiche Prüfung: Ausschlüsse, Zugriffsfehler und Engine-Limits gelten weiterhin.

Die Liveansicht zeigt die letzten 20 Befund-/Fehlerzeilen. Die Momentaufnahme hält bis zu 1.000 Zeilen vor und nennt zusätzlich ausgeblendete Meldungen. Endergebnis und bisherige lokale Scanprotokollierung bleiben davon getrennt. Ausgaben und Dateinamen gelten als nicht vertrauenswürdig; Steuerzeichen werden vor der Konsolenausgabe entfernt. Dieser Ablauf verschiebt Funde nicht automatisch in Quarantäne.

## Lebenszyklus und gleichzeitige Aktionen

Hauptmenü und Scan besitzen getrennte Sitzungszustände und teilen nur synchronisierte Statusdaten im Speicher. Der Hintergrundscan liest keine Konsolentasten und registriert keinen Abbruchhandler für die Hauptkonsole. Er verwendet die bisherige Dateierfassung, Engine-Auswahl, Signaturregelung, Ergebnisverarbeitung, Abdeckungsprüfung, Updatesperre und Quarantänelogik.

Es wird jeweils ein Hintergrundscan angenommen. Die Installationssperre verhindert zudem konkurrierende Scans und Änderungen an Signaturen/Engine, auch während einer Pause. Lesende Werkzeuge bleiben nutzbar; Dateisystemänderungen anderer Funktionen können einen laufenden Scan unvollständig machen. Ein optionaler Scan nach einer Deinstallation meldet die belegte Installation, statt eine zweite Engine zu starten.

Die Pause wird am nächsten Prüfpunkt umgesetzt, normalerweise beim nächsten Lebenszeichen, nicht sofort beim Tastendruck. Vorbereitung und Dateierfassung pausieren kooperativ. Bei `clamscan` und dem privaten Worker halten dokumentierte Windows-Thread-Funktionen ausschließlich den Scannerprozess an, dessen PID der eigene Start-/Statuspfad liefert. Der Anwendungshost darf nicht angehalten werden. Erfolgreiche Suspend-Aufrufe werden bei Fortsetzung/Abbruch ausgeglichen; ein Fehler nimmt die Pause zurück und meldet den Scan als fehlgeschlagen. Der Scanner behält RAM und möglicherweise offene Dateihandles. Die äußeren REMNEXA-Zeitlimits für Scan/Start rechnen Pausen heraus; interne Engine-Dateilimits bleiben unverändert und können nach langen Pausen weiterhin ein unvollständiges Ergebnis auslösen.

Ein Abbruch erhält bereits beobachtete Befunde und kennzeichnet die Abdeckung als unvollständig. Ein Abschluss wird erst angezeigt, wenn Ergebnisse und Worker-Bereinigung eingesammelt wurden. Beim Beenden wird der Abbruch angefordert und höchstens 15 Sekunden gewartet; eine nicht bestätigte Bereinigung wird gemeldet. Es entstehen keine Windows-Dienste, geplanten Aufgaben, Listener, Sicherheitsausnahmen oder automatischen Updates.

## Modulschnittstelle

```powershell
Import-Module ./Antivirus/Antivirus.psd1
Start-ClamAVBackgroundScan -ScanType Quick -Language de
Get-ClamAVBackgroundScan
Set-ClamAVBackgroundScan -Action Pause
Set-ClamAVBackgroundScan -Action Resume
Set-ClamAVBackgroundScan -Action Cancel
Stop-ClamAVBackgroundScan
Get-ClamAVBackgroundScan -IncludeResults
```

Die synchronen Befehle `Invoke-ClamAVScan` und `Invoke-ClamAVTargetedScan` bleiben für Skripte und geordnete Deinstallationsabläufe erhalten. Hintergrundaufträge aktualisieren keine Komponenten und verschieben keine Funde automatisch in Quarantäne. Der Scan-Runspace bleibt zwischen Aufträgen erhalten, damit die native Engine ohne erneutes Laden aller Signaturen wiederverwendet werden kann. Die eigene Engine endet nach ihrer bisherigen konfigurierten Leerlaufzeit (standardmäßig 60 Sekunden). Vor synchronen Scans oder Updates werden die inaktive Hintergrund-Engine und ihr Runspace freigegeben; abgeschlossene Ergebnisse bleiben erhalten. Auch Beenden/Modulentfernung geben sie frei. Es wird kein Dienst und keine eigenständige dauerhafte Anwendung installiert.

## Kandidatenpaket

Aus einem sauberen Checkout des Kandidatenbranches lässt sich mit PowerShell 7.5 oder neuer ein Quellpaket erstellen und prüfen:

```powershell
$package = ./tools/New-RemnexaPackage.ps1 -Version '2.2.0-rc.7'
./tools/Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

ZIP und SHA-256-Begleitdatei entstehen unter `dist/`. Dies ist ein Quellkandidat ohne mitgelieferte PowerShell, ClamAV-Binärdateien oder Signaturdatenbanken, kein Installer und kein stabiles Release. Die bisherigen Voraussetzungen für Laufzeit und Einrichtung gelten weiterhin.

## Prüfung

`tests/BackgroundScan.Tests.ps1` prüft einen tatsächlich asynchronen Runspace und einen harmlosen externen Testscanner: bedienbarer Aufrufer, frühe Befunde, echte Prozesspause/Fortsetzung, Abbruch aus der Pause, erhaltene Befunde, Installationssperre, Fehler, begrenzte Vorschau und Texte in sechs Sprachen. `tests/BackgroundScanUI.Tests.ps1` prüft Hintergrundstart, Rückkehr nach `/scan` und zustandsabhängige Bedienung. Die bisherigen Tests für synchrone Scans und Update-Rückfragen bleiben anwendbar.

Abschließende lokale Regression: **191 bestanden, 0 fehlgeschlagen, 0 übersprungen** mit Pester 5.7.1 und PowerShell 7.6.9. Die statische Analyse fand keine Fehler im geänderten PowerShell-Code. Die entfernte CI dieses Kandidaten wurde noch nicht bestätigt, weil GitHub den öffentlichen API-Statusabruf begrenzt hat.

Zusätzlich lief `tools/Test-ClamAVBackgroundScan.ps1` mit installiertem ClamAV 1.5.4: **2.501 harmlose Dateien und ein eigener Hash-Testfund pro Scanverfahren**, jeweils mit echtem CLI-Scanner und eingeschränktem nativem Worker. Beide pausierten ohne weitere Dateibestätigungen, setzten mit vollständiger Testabdeckung fort und brachen einen zweiten Scan aus der Pause ab. Es gab keine automatische Quarantäne. Installierte Signaturdateien und persönliche Ordner wurden nicht verändert oder gescannt. Das isolierte Testmodul ändert ausschließlich die Bereitschaftsanzeige für seine harmlose HDB-Datenbank; Scanner- und Prozesscode entsprechen der Anwendung.

Der native Test prüft zusätzlich dieselbe Engine-PID beim nächsten Auftrag und die Freigabe der zwischengespeicherten Engine eines abgeschlossenen Scans vor synchronem Zugriff. Die protokollierten Rückkehrzeiten des Hintergrundstarts enthalten unterschiedliche einmalige Vorbereitungen. Sie beschreiben die Bedienbarkeit und sind kein Vergleich der Engine-Leistung. Siehe [bereinigte Messergebnisse](benchmarks/rc7-background-scan.json).

Geprüft wurde auf dem verfügbaren Windows-11-Rechner mit SSD und 16 GB RAM. Damit sind Windows 10, HDD, eine echte 8-GB-VM, Malware-Erkennungsleistung und lange Pausen bei sämtlichen Dateiformaten nicht nachgewiesen. Die bisherigen [Grenzen und Lizenzhinweise der nativen Engine](PRIVATE_SCAN_ENGINE.de.md) gelten weiterhin.
