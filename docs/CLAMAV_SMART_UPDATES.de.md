[English](CLAMAV_SMART_UPDATES.md) | [Deutsch](CLAMAV_SMART_UPDATES.de.md)

# Intelligente ClamAV-Updates — 2.2.0-rc.3

**Implementierte Entwicklungsfunktion, kein stabiles Release.** Dieser Stand erweitert [rc.2](RELEASE_2.2.0_RC2.de.md). Vorhandene APIs für Scan, Einrichtung, Status, Quarantäne und Wiederherstellung bleiben verfügbar.

## Ablauf

Beim Programmstart prüft REMNEXA Konfiguration, lokale Installation und gespeicherte Metadaten. Bei Fälligkeit startet es einen versteckten eigenen PowerShell-Prüfprozess und setzt das Hauptmenü sofort fort. Ohne ClamAV entfallen Onlineprüfungen. Auf dem Hauptbildschirm erscheinen keine Updatehinweise. Normales Programmende, direktes Beenden und Entladen des Moduls stoppen den eigenen Prüfprozess; Netzwerkaufrufe und Wiederholungen sind zusätzlich zeitlich begrenzt. Es entstehen keine Dienste, geplanten Aufgaben oder Autostart-Einträge.

Der Prüfprozess liest die Engine-Version und kleine lokale Datenbank-Header. Er holt Metadaten des neuesten stabilen Windows-Releases aus dem offiziellen Cisco-Talos-GitHub-Repository und fragt ClamAVs offiziellen TXT-Eintrag `current.cvd.clamav.net` über Windows-DNS ab. Er führt weder Installation noch FreshClam oder Scans aus. Engine-Archive und Datenbankupdates werden nicht heruntergeladen.

Engine-Versionen werden semantisch einschließlich Vorabversionen verglichen. Ein neuerer stabiler Stand wird nur mit unterstütztem Windows-Paket, offizieller HTTPS-Quelle und gültigen SHA-256-Metadaten zur Aktualisierung angeboten. Fehlt die Prüfsumme, bleibt die Engine-Updateaktion gesperrt. Die eigentliche Installation ermittelt und prüft das Paket erneut; der Cache erteilt keine Installationsberechtigung. Engine-Updates weisen Downgrades und unbekannte Paketversionen ab und erhalten Staging, Rücksicherung und die vorhandene Datenbank.

Datenbankversionen stammen aus lesbaren CVD-/CLD-Headern für `main`, `daily` und `bytecode` sowie der offiziellen TXT-Feldzuordnung. Fehlende, widersprüchliche oder unzuverlässige lokale Header bleiben unbekannt. Fehlerhafte oder über drei Stunden alte DNS-Einträge werden abgewiesen. DNS ist ein Verfügbarkeitshinweis, kein signierter Download oder Schutzbeweis. FreshClam übernimmt bestätigte Datenbankupdates mit seinen eigenen Integritätsprüfungen. Unbekannte Versionen ergeben eine Empfehlung, kein erfundenes verfügbares Update.

## Bedienung im Antivirus-Bereich

- Vorhandene Nummern **1–7** bleiben erhalten.
- **U** prüft Metadaten sofort unabhängig vom Intervall und bietet unterstützte Updates für Datenbanken, Engine oder beides an. Offlineprüfungen führen ohne erzwungene Aktualisierung zurück ins Menü.
- **I** zeigt Komponentenstatus, lokale/verfügbare Datenbankversionen und die letzte erfolgreiche Metadatenprüfung.
- Vor einem Konsolenscan bieten bestätigte ausstehende Updates **J** für Aktualisieren und Scannen, **N** für Scannen ohne Update, **I** für Informationen und **0** für Zurück an. `Y` wird zusätzlich als nicht angezeigter Bestätigungsalias akzeptiert; die sichtbaren Tasten sind in allen Sprachen gleich.
- Nach einem Updatefehler wird nur nach gesonderter ausdrücklicher Zustimmung gescannt. Innerhalb dieses Scans wird das Update nicht wiederholt angefragt. Der Scan prüft die lokale Einsatzbereitschaft von Engine und Datenbank erneut.
- Direkte Modulscans bleiben ohne Rückfragen und laden keine Updates. Auch nichtinteraktive Entfernungsscans aktualisieren nicht. Die ältere Einstellung `AutoUpdateSignatures` erlaubt im Konsolen-Entfernungsablauf kein stilles Update mehr; ausdrückliche Update-APIs und Beispielabläufe bleiben getrennt.

Hinweise für Engine und Signaturen veralten unabhängig. Ein erreichbarer Signatur-Endpunkt bleibt nützlich, wenn die Releaseabfrage fehlschlägt. Offlinebetrieb, veraltete Daten und fehlgeschlagene Prüfungen erscheinen nie uneingeschränkt als aktuell. Metadatenfehler löschen oder deaktivieren keinen vorhandenen Scanner.

## Einstellungen und Speicherung

Einstellungen stehen in `config/antivirus.json`; ältere Dateien erhalten kompatible Vorgaben im Arbeitsspeicher. `Set-AVConfig` prüft die Werte vor dem Speichern.

| Einstellung | Vorgabe | Zulässig |
| --- | --- | --- |
| `AutoCheckUpdates` | `true` | Boolean; U kann auch bei abgeschalteter Automatik ausdrücklich prüfen. |
| `UpdateCheckIntervalHours` | `24` | 1–168 Stunden. |
| `UpdateNetworkTimeoutSeconds` | `3` | 1–10 Sekunden je HTTP-/DNS-/nativem Versionsaufruf. |
| `UpdateRetryCount` | `1` | 0–2 Wiederholungen nach dem ersten Versuch. |
| `UpdateRetryBackoffSeconds` | `1` | 1–30 Sekunden, zwischen Wiederholungen verdoppelt. |

Erfolgreiche Prüfungen werden innerhalb des Intervalls wiederverwendet. Fehlgeschlagene Versuche speichern zusätzlich eine Wartefrist: zunächst eine Minute, bei folgenden durch Programmstarts angestoßenen Versuchen bis höchstens eine Stunde. Innerhalb einer Versuchsfolge werden bereits erfolgreich geprüfte Komponenten nicht unnötig erneut abgefragt. Es gibt keine dauerhaft laufende Abfrageschleife.

Der Zustand liegt unter `%LOCALAPPDATA%\REMNEXA\AntivirusUpdates.json`. Er enthält Versionen, Status und Zeitpunkte der Komponenten, Wiederholungsfristen und einen lokalen Konfigurationsfingerabdruck. Schreiben verwendet eine geprüfte temporäre Datei im selben Ordner und atomaren Austausch. Eine Dateisperre verhindert gegenseitiges Überschreiben gleichzeitiger Metadaten-/verwalteter Updatevorgänge. Beschädigte, übergroße, unsichere oder unpassende Zustände gelten als unbekannt. Die benachbarte Sperrdatei darf nach Ende leer zurückbleiben; sie ist kein laufender Prozess.

Die Prüfung überträgt keine persönlichen Dateien, Dateinamen, Berichte, Protokolle oder Installationspfade. Anfragen legen technisch übliche Netzwerkmetadaten wie die Quell-IP gegenüber Server beziehungsweise DNS-Resolver offen. Es gibt keine Telemetrie oder API-Schlüssel.

## Prüfung und Grenzen

Tests verwenden Mocks und isolierte Ordner. Sie prüfen fehlende Installation, Offlinebetrieb, aktuelle/neue Versionen, beide Komponenten, begrenzte Wiederholungen, beschädigte Angaben, Prüfsummen/Quellen, semantische Reihenfolge, Downgrade-Sperre, Fehler beim atomaren Austausch, Cachealter/Wartefristen, fehlgeschlagene Prüfprozesse, gleichzeitige Sperren, Zustimmung/Ablehnung/Fortsetzung nach Fehlern und sechs vollständige Sprachen. Echte Hauptmenütests verwenden einen isolierten absichtlich langsamen Prüfprozess und prüfen bedienbare Eingaben sowie dessen Ende beim Beenden.

Eine rein lesende Liveprüfung erkannte außerdem eine neuere Daily-Datenbank, ohne etwas zu aktualisieren. Ein späterer Livelauf prüfte den Teilerfolg bei fehlgeschlagener Releaseabfrage und weiterhin verfügbaren offiziellen Datenbankmetadaten. Das Starten der Hintergrundarbeit benötigte lokal ungefähr 0,18–0,45 Sekunden; dies ist kein allgemeiner Startzeit-Benchmark. Echte Downloads, erhöhte Engine-Ersetzung, echte Signaturinstallation und eine vollständige Windows-VM-Matrix wurden für diese Funktion nicht ausgeführt.

Lokale Prüfung mit PowerShell 7.6.9: Unter Pester 3.4.0 und 5.7.1 bestanden jeweils alle **144 Tests**, ohne Fehler oder übersprungene Fälle. Syntaxprüfung und PSScriptAnalyzer-1.24.0-Fehlerprüfung meldeten keine Fehler in **78 eigenen PowerShell-Dateien**. Der Selbsttest bestand **12 Prüfungen**. Alle sechs Sprachen enthalten **346 nicht leere Schlüssel**. Dokumentation auf Englisch/Deutsch und relative Links wurden geprüft; der Lizenztext ist unverändert. Dies sind lokale Ergebnisse, keine entfernte CI- oder vollständige Kompatibilitätszertifizierung.

Diese Änderung erzeugt kein stabiles Release. Ein Quell-Testpaket lässt sich aus dem Entwicklungscheckout so bauen:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.3'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Quellpakete enthalten keine optionalen PowerShell-/ClamAV-Pakete oder Signaturen. Starte eine ältere laufende Anwendung neu, um Änderungen zu laden. Allgemeine Bedienung: [Antivirus-Anleitung](../Antivirus/README.de.md).

Implementierungsreferenzen: [offizielle Release-Metadaten](https://api.github.com/repos/Cisco-Talos/clamav/releases/latest), [FreshClam-Feldzuordnung für Datenbanken](https://github.com/Cisco-Talos/clamav/blob/main/libfreshclam/libfreshclam_internal.c) und [DNS-Zeitprüfung](https://github.com/Cisco-Talos/clamav/blob/main/libfreshclam/libfreshclam.c). Das CVD-/CLD-Headerformat beschreibt die [ClamAV-Datenbankdokumentation](https://docs.clamav.net/manual/Signatures/Introduction.html).
