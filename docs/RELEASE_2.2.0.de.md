[English](RELEASE_2.2.0.md) | [Deutsch](RELEASE_2.2.0.de.md)

# REMNEXA 2.2.0

Dieses Quellrelease übernimmt die geprüfte rc.8-Anwendung als Version 2.2.0. Es verbindet die bestehende Deinstallations- und Wartungsbasis mit den schrittweisen Verbesserungen aus dem [Änderungsprotokoll](../CHANGELOG.de.md).

## Herunterladen und starten

Lade `REMNEXA-2.2.0-source.zip` und die zugehörige `.sha256`-Datei vom [Release v2.2.0](https://github.com/gaibkhanov/REMNEXA/releases/tag/v2.2.0) herunter. Entpacke das Archiv in einen lokal beschreibbaren Ordner. Verwende Windows x64 mit PowerShell 7.5 oder neuer und starte `REMNEXA.cmd`. Der Starter bevorzugt eine passende Laufzeit unter `runtime/`, andernfalls `pwsh.exe` im PATH. Das Quellpaket enthält weder PowerShell noch ClamAV-Programme oder Signaturdatenbanken. Antivirus-Einrichtung und Updates benötigen Internet; mit installierten Signaturen sind Offline-Scans möglich. Benötigte erhöhte Rechte werden aktionsbezogen angefordert.

ZIP vor dem Entpacken prüfen:

```powershell
$archive = './REMNEXA-2.2.0-source.zip'
$expected = ((Get-Content ($archive + '.sha256') -Raw).Trim() -split '\s+')[0]
if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or
    (Get-FileHash $archive -Algorithm SHA256).Hash -ine $expected) {
    throw 'Die Download-Prüfsumme stimmt nicht überein.'
}
```

Das Release liefert außerdem englische/deutsche Hinweise. Installer, gebündelte Laufzeit/Engine, Modellgewichte, Windows-Dienst und digitale Signatur werden nicht mitgeliefert. Das Quellmanifest enthält den genauen Git-Commit und SHA-256-Werte je Datei. Prüfsummen erkennen Beschädigungen; beziehe sie von der vertrauenswürdigen Release-Seite.

## Wesentliche Änderungen

- Unabhängiges Antivirus-Scanfenster: REMNEXA weiter nutzen oder den Scan nach dem Beenden der Hauptanwendung fortsetzen. Pause, Fortsetzung, Abbruch und Befunde sind erreichbar; Endergebnisse werden lokal gespeichert.
- Ausdrückliche Auswahl Fortsetzen/Abbrechen/Zurück beim Beenden mit aktivem Scan. Ein pausierter Scan wird vor bestätigtem Fortsetzen wieder aufgenommen. Schließen des Scanfensters beendet dessen Scanner.
- Wiederverwendbarer eingeschränkter nativer ClamAV-Worker, CLI-Ausweichpfad, Eco/Balanced/Fast, begrenzte Ressourcen und Hinweise bei unvollständiger Abdeckung.
- Stille zwischengespeicherte Updateprüfung, manuelle Updateauswahl und bestätigte Updates über die vorhandenen sicheren Download-, Staging- und Rücksicherungsfunktionen.
- Klarerer Fortschritt, Seitenwechsel nur bei vorhandenen Seiten, einheitliche Beenden-Auswahl und Hinweise vor erhöhten Rechten in sechs Oberflächensprachen.
- Bereinigungspfad-Prüfungen, Schutz Windows-verwalteter Paketdateien, präzisere Bereinigungs-/Dienstemeldungen und geprüfte Quellpaket-Integrität.

Lies [Verhalten unabhängiger Scans](INDEPENDENT_SCANS.de.md), [ClamAV-Anleitung](../Antivirus/README.de.md), [Sicherheitsmodell](SECURITY_MODEL.de.md) und [Drittanbieterhinweise](THIRD_PARTY_NOTICES.de.md) vor erweiterten Aktionen. Hintergrundscans verschieben Befunde nicht automatisch in Quarantäne; REMNEXA ersetzt keinen Echtzeit-Antivirus.

## Prüfung und Umfang

Die funktional unveränderte rc.8-Basis bestand **204 Pester-Tests**, **12 Selbsttests im entpackten Quellpaket** sowie Syntax- und PSScriptAnalyzer-Fehlerprüfungen. Auch deren [GitHub-Qualitätslauf](https://github.com/gaibkhanov/REMNEXA/actions/runs/44929088151) bestand Tests, statische Analyse, Quellpaketbau/-prüfung und Artefakt-Upload. Der endgültig versionierte Quellstand wird vor Veröffentlichung erneut geprüft; die Release Notes nennen den genauen Release-CI-Lauf und die Paketprüfsumme.

Echte ClamAV-1.5.4-CLI- und Privat-Worker-Scans verarbeiteten jeweils 2.501 harmlose Dateien mit einem eigenen Hash-Signaturtreffer, liefen nach Ende des erzeugenden Prozesses weiter und speicherten vollständige Ergebnisse. Frühere Protokolle decken erhöhten Start, native Job-Limits, Speicherfreigabegrenzen, Cache-Wiederverwendung, Signaturwechsel, Abbruch und harmlose Archive ab. Dies belegt weder Malware-Erkennungsleistung noch universelle Deinstallationskompatibilität.

Die dokumentierten Laufzeittests nutzen Windows 11 x64, SSD und 16 GB RAM mit PowerShell 7.6.9. Windows 10, echte 8-GB-VM, HDD, vollständige Konto-/UAC-Matrix und Malware-Labor bleiben ungeprüft. Lokale KI, grafisches Dashboard, Installer und vollständige Offline-Distribution bleiben geplant. Zeitfenster zwischen Pfadprüfung und Zugriff sowie aktionsbezogene Rücksicherungsgrenzen bleiben bestehen; wichtige Daten unabhängig sichern. Siehe [Kompatibilitätsmatrix](COMPATIBILITY_MATRIX.de.md).

Dieses stabile Quellrelease schließt die REMNEXA-3.0-Roadmap nicht ab. Vorhandene Releases und Tags bleiben unverändert.
