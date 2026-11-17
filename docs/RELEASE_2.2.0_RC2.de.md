[English](RELEASE_2.2.0_RC2.md) | [Deutsch](RELEASE_2.2.0_RC2.de.md)

# REMNEXA 2.2.0-rc.2: Verarbeitungsfortschritt

**Status: Entwicklungskandidat zum Testen. Die Veröffentlichung ist zurückgestellt.** Dieser Stand erweitert [rc.1](RELEASE_2.2.0_RC1.de.md) und erhält dessen Korrekturen. Er ist kein stabiles Release und kein REMNEXA 3.0.

## Implementiertes Verhalten

- Ein gemeinsamer Fortschrittsbaustein zeigt Vorgang, Phase, Laufzeit und aktuellen Eintrag. Bekannte Arbeit verwendet bearbeitet/gesamt; unbekannte Arbeit bleibt unbestimmt, statt eine zeitliche Prozentzahl zu erfinden.
- Türkis bedeutet laufend, Gelb bedeutet Eingabe erwartet, Hinweis oder Abbruch, Grün bedeutet erfolgreich abgeschlossen und Rot bedeutet Fehler. Text benennt den Zustand zusätzlich. Unvollständig bearbeitete Mengen behalten beim Abschluss mit Hinweis ihren tatsächlichen Anteil.
- Vor Konsoleneingaben wird aktive Arbeit als wartend gekennzeichnet. Die Beobachtung externer Prozesse aktualisiert die Laufzeit auch bei stiller Engine oder stillen Befehlen. Interaktive Konsolen zeichnen den nativen Balken neu; Hosts ohne sichtbaren nativen Fortschritt erhalten begrenzte farbige Statuszeilen.
- Antivirus-Scans erfassen zuerst erlaubte Ziele. Überlappende Verzeichniswurzeln werden zusammengefasst, Ausschlüsse bleiben wirksam, Verknüpfungen werden übersprungen und Erfassungsfehler gezählt. Eine ausdrückliche Dateiliste verhindert mehrfaches rekursives Prüfen überlappender Wurzeln durch ClamAV.
- Beim Scan steuern ClamAV-Rückmeldungen je Datei den Zähler. Laden der Engine und Ergebnisauswertung sind eigene Phasen. Fehlende Rückmeldungen, übersprungene Pfade und Dateifehler ergeben kein uneingeschränkt sauberes Ergebnis. Nicht zuordenbare Fund-Exitcodes führen zu einem Fehler. Funde bleiben sichtbar; Quarantäne muss ausdrücklich gewählt werden.
- Fortschritt begleitet außerdem Programminventar, Rückstandssuche, Registry-Abfragen, Entfernung, Autostart-Inventar/Änderungen/Wiederherstellung, Datenschutzänderungen und deren Rücknahme, Wiederherstellungspunkt-Anfragen, Dienste-/Feature-Abfragen, Protokollbereinigung, Quellsicherungen, Systemübersicht sowie Antivirus-Einrichtung/Updates/Status/Quarantäne.
- Bisherige feste Entfernungsprozente wählen jetzt ausschließlich Phasentexte. Der Gesamtvorgang bleibt bis zum Abschluss unbestimmt; messbare Teilvorgänge zeigen eigene Zähler. Das Speichern des Ergebnisses endet weiterhin vor der optionalen Systemprüfung.
- Alle sechs Oberflächensprachen enthalten die neuen Fortschrittstexte. Die Anwendung zeigt `2.2.0-rc.2` an.

## Bedeutung der Scan-Prozentzahl

Während des Scans entspricht die Prozentzahl dem Anteil erfasster Dateien, für die ClamAV ein Ergebnis gemeldet hat. Sie ist **keine Restzeitschätzung**, Bytezählung oder Messung sämtlicher Objekte innerhalb von Archiven. Eine große Datei kann länger brauchen als viele kleine. Nach einem Dateizähler von 100 % können Auswertung oder ausdrücklich gewählte Quarantäne folgen; der Zustand bleibt bis zum Vorgangsende laufend.

`FilesTotal`, `FilesReported`, `FilesUnconfirmed`, `InventorySkipped` und `CoverageComplete` dokumentieren Erfassung und Rückmeldungen. `CoverageComplete` hebt ClamAV-Größen-, Archiv- und Formatgrenzen nicht auf und garantiert weder vollständige Inhaltsprüfung noch Schadsoftwarefreiheit. Konfigurierte Ausschlüsse sind beabsichtigt und zählen nicht als Zugriffsfehler. Übersprungene Erfassung wird zusammengezählt; diese Änderung ergänzt kein Manifest mit jedem übersprungenen Pfad.

## Prüfung

Die lokale Prüfung verwendete PowerShell 7.6.9 und folgende Kontrollen:

| Prüfung | Ergebnis |
| --- | --- |
| Pester 3.4.0 | 107 bestanden, 0 fehlgeschlagen, 0 übersprungen. |
| Pester 5.7.1 | 107 bestanden, 0 fehlgeschlagen, 0 übersprungen. |
| Syntax eigener PowerShell-Dateien | 73 Dateien, 0 Syntaxfehler. |
| PSScriptAnalyzer 1.24.0 Fehlerprüfung | 73 Dateien, 0 Fehler; bisherige Warnungen gelten damit nicht als behoben. |
| Anwendungs-Selbsttest | 12 Prüfungen bestanden, Version 2.2.0-rc.2. |
| Vollständigkeit der Übersetzungen | 318 nicht leere Schlüssel in jeder der sechs Sprachen. |
| Dokumentation | 39 Dateien, 19 Sprachpaare, 262 relative Links und 30 PowerShell-Beispiele geprüft; keine erkannten privaten Rechnerverweise. |

Die echte ClamAV-Engine 1.5.4 beendete Schnelldurchläufe in einem isolierten Testprofil: fünf harmlose Dateien erfasst, fünf Rückmeldungen, keine übersprungenen oder unbestätigten Dateien, keine Funde, ungefähr 16–25 Sekunden in zwei Läufen. Eine gesonderte benutzerdefinierte Ein-Datei-Prüfung war ebenfalls erfolgreich. Testspezifische Umgebungsvariablen und Konfiguration begrenzten den Scan auf Testordner. Dies sind Funktionstests der echten Engine und des Quick-Ablaufs, **kein Scan eines gesamten Benutzerrechners**. Signaturen wurden nicht aktualisiert, Dateien nicht in Quarantäne verschoben und vorhandene Sicherheitssoftware nicht verändert.

Regressionstests prüfen fehlende Rückmeldungen, Fund-/Fehlerbehandlung, Ausschlüsse, verknüpfte Verzeichnisse, überlappende Ziele, Fortschrittsregeln, Eingabewarten, Callback-Fehler und Ausgabegrenzen externer Prozesse. Bisherige Tests für Navigation, Berechtigungen, Sicherung und Abschluss bleiben Teil der Suite.

## Grenzen und zurückgestellte Arbeit

- Synchrone Windows-/CIM-Aufrufe, Fremdinstaller und Webdownloads ohne nutzbare Rückmeldungen zeigen eine Phase. Sie liefern während dieses einzelnen blockierenden Aufrufs keine zuverlässige Prozentzahl oder durchgehende Laufzeitaktualisierung. Eine Oberfläche mit Hintergrundaufgaben bleibt offen.
- Es gibt keine neue allgemeine Abbruchschaltfläche oder garantierte Kontrolle über abgekoppelte/erhöhte Fremdinstaller. Bestehende Prozess-Zeitlimits bleiben wirksam. Signaturalter, Größen-/Formatgrenzen und unzugängliche Inhalte beeinflussen weiterhin den Nutzen eines Scans.
- Dateierfassung erfolgt vor dem Scan. Dateien können sich danach ändern; dies reduziert Doppelarbeit, beseitigt aber keine Dateisystem-Zeitfenster. Erfassung und Ergebniszählung benötigen Speicherplatz/Arbeitsspeicher entsprechend der ausgewählten Arbeitsmenge.
- Quell-Checkpoints sichern Anwendungscode, kein gesperrtes vollständiges Systemabbild oder Fremdkomponenten. Der vorherige Quellkandidat bleibt getrennt erhalten.
- Keine vollständige Windows-VM-Matrix, echte destruktive Deinstallations-/Wiederherstellungsprüfung, kein Installer, keine eingebettete lokale KI, vollständige Offline-Distribution oder digitale Signatur ist geliefert. Lokale Ergebnisse belegen keinen erfolgreichen entfernten CI-Lauf.

## Bauen und testen

Verwende den Branch `feature/2.2.0-progress`. Aus einem sauberen, committeten Checkout mit Git und PowerShell ab 7.5:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.2'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Das Quellarchiv enthält keine PowerShell-/ClamAV-Binärdateien, Signaturen oder KI-Modelle. Halte unterstützte optionale Komponenten getrennt verfügbar. Starte `REMNEXA.cmd` im aktualisierten Anwendungsordner; eine ältere laufende Instanz muss neu gestartet werden, um Änderungen zu laden. Vorhandene Releases werden nicht ersetzt.
