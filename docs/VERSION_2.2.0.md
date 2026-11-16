# REMNEXA 2.2.0 – lokaler Stand

Git-Übernahme: Der hier dokumentierte OneDrive-Stand wurde am 16. November 2026 in das bestehende Repository `C:\Dev\REMNEXA` auf den Branch `feature/2.2.0-development` übernommen. Künftige Entwicklung erfolgt dort. Der OneDrive-Ordner bleibt ein lauffähiger, unveränderter Ausgangsstand; es gibt keine automatische Synchronisierung. Details: [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md).

Stand: 16. November 2026. Diese Version wurde auf Wunsch des Maintainers aus dem getrennten Entwicklungsstand als lokale Version 2.2.0 zusammengestellt. Es wurde kein GitHub-Release veröffentlicht. Das ursprüngliche REMNEXA 2.1.3 und sein Ordner `Backup-2.1.3` bleiben erhalten.

## Start und Speicherort

- Ordner: `C:\Users\gaibk\OneDrive\Software\REMNEXA-2.2.0`
- Start: Doppelklick auf `REMNEXA.cmd`.
- Im Hauptmenü zeigt `[9]` die rein lesende Systemübersicht.
- Den gesamten Ordner zusammenhalten: `runtime`, `Core`, `locales`, `Antivirus`, `assets` und `config` werden benötigt.

## Enthaltene Verbesserungen

- Systemübersicht mit Windows-Version, Build, CPU-Auslastung, Arbeitsspeicher und lokalen Laufwerken; Abfrage nur auf ausdrücklichen Aufruf.
- Übersetzungen in sechs separaten Sprachdateien mit Fallback und Vollständigkeitsprüfung.
- Validierte, atomar geschriebene Einstellungen und Antivirus-Konfiguration.
- HTTPS- und SHA-256-Prüfung für neue ClamAV-Downloads; gestufte Erstinstallation mit Rückkehr zum vorherigen Stand bei fehlerhafter Konfigurationsübernahme.
- Validierung von Datenschutz-Backups gegen eine feste Registry-Liste vor dem Wiederherstellen.
- Zusätzliche Pfadprüfungen gegen Junctions und andere Verknüpfungen bei der Rückstandssuche und Bereinigung.
- Klare Eingabeprüfung bei der Quarantäne-Auswahl und getrennte Zustände für Vorgangsergebnisse.
- Beim Öffnen des Antivirus-Bereichs fordert REMNEXA bei Bedarf die Windows-Administratorfreigabe an und öffnet danach direkt wieder Antivirus. Ein manueller Neustart entfällt. Beim Abbrechen der Freigabe startet kein Scan. Das Hauptmenü benötigt weiterhin keine Administratorrechte.
- Lokaler Testaufruf: `runtime\pwsh.exe -NoProfile -File tools\Invoke-RemnexaTests.ps1`.

## Übernommene Komponenten

Die bereits lokal vorhandene portable PowerShell-Laufzeit und das ClamAV-Verzeichnis wurden aus dem bisherigen REMNEXA-Ordner übernommen. Die Lizenz- und Drittanbieterhinweise dieser Komponenten bleiben im jeweiligen Verzeichnis erhalten. Es wurden keine neuen Modellgewichte und keine neue Inferenz-Runtime heruntergeladen. Die übernommenen ClamAV-Dateien ersetzen keine Aktualisierung der Virensignaturen und sind keine neu durchgeführte Herstellerprüfung.

`COPY-PROVENANCE.csv` dokumentiert die beim Kopieren geprüften Ausgangsdateien. Die Versionsangaben und diese Dokumentation wurden danach angepasst; die abschließenden Dateihashes stehen in `FILES-SHA256.csv`.

## Grenzen und offene Punkte

- Lokale KI: nur Datenverträge vorbereitet; kein Chat, kein Modell und keine Inferenz.
- Keine vollständige Version 3.0.0, kein neuer grafischer Desktop und kein Installer.
- Die Pfadprüfung beseitigt das Zeitfenster zwischen Prüfen und Dateizugriff nicht vollständig. OneDrive und andere Verzeichnisverknüpfungen können deshalb zu bewusst abgewiesenen Bereinigungspfaden führen.
- Neue Downloads, erhöhte Registry-Wiederherstellung, reale Deinstallationen und Löschaktionen wurden für diese lokale Übergabe nicht auf dem Benutzerrechner getestet.
- Pester 5, GitHub Actions und eine vollständige Windows-10/11-Testmatrix bleiben offen.
- Der Stand nutzt weiterhin die vorhandenen Einstellungen und lokalen Logs unter `%LOCALAPPDATA%\REMNEXA`; eine getrennte Programmdatei-Kopie ist kein isoliertes Benutzerprofil.
- Historische Audit-Dokumente beschreiben die ursprüngliche 2.1.3 und die frühere Arbeitskopie. Für diesen Ordner gelten die Versionsangabe 2.2.0 und dieser Übergabebericht.

## Prüfung dieser Übergabe

Die Kopie wurde vor den lokalen Versionsanpassungen für alle 993 übernommenen Dateien per SHA-256 mit den jeweiligen Quellen verglichen.

- Pester 3.4.0 mit der mitgelieferten PowerShell 7.6.9: zuletzt 79 bestanden, 0 fehlgeschlagen, 0 übersprungen. Die Suite prüft auch bedingte Seitennavigation und die eindeutige Beenden-Anzeige. Keine reale UAC-Freigabe, kein echter Systemscan und keine reale Quarantäne-Wiederherstellung wurden für diese Änderungen ausgeführt.
- Selbsttest am endgültigen Speicherort: 12 von 12 Prüfungen bestanden; ausgegebene Version 2.2.0.
- 282 Übersetzungsschlüssel für alle sechs Sprachen bestanden die Vollständigkeitsprüfung.
- Die übernommene ClamAV-Engine meldet Version 1.5.4 und 3.642.956 Signaturen. Das ist eine Statusabfrage, kein neu ausgeführter Virenscan.
- Versionsanzeige, Selbsttest-Marke, README, deutschsprachige Anleitung und Changelog sind auf 2.2.0 angepasst.
- Der SHA-256-Wert der ursprünglichen `REMNEXA.ps1` und ihres 2.1.3-Backups stimmt weiterhin mit dem vorab erfassten Wert überein.
- Die abschließenden SHA-256-Werte der unveränderlichen Paketdateien stehen in `FILES-SHA256.csv`. Die Liste schließt sich selbst, `Backup-*` und die veränderlichen ClamAV-Datenbanken unter `ClamAV\database` aus.
- Die sichtbare Darstellung im interaktiven Terminal und die abgeschlossene OneDrive-Cloud-Synchronisierung wurden nicht geprüft.

Nachtrag Antivirus-Start: Die automatische Rechteabfrage ist mit vier isolierten Fällen geprüft; insgesamt bestehen 38 Tests. Die seit der Übergabe veränderten ClamAV-Signaturdateien wurden beibehalten. Sie werden künftig aus dem Paketmanifest ausgenommen, weil ein Signaturupdate Datenbankdateien ersetzen und alte Signaturbegleitdateien entfernen kann. Der Startfix selbst ändert weder die Scan-Engine noch Signaturen.

## Einheitliches Beenden

Vor Anwendungseingaben ohne eigene Beenden-Option steht zusätzlich `[X] Anwendung komplett beenden`. Wo 0 bereits das Programm beendet, erscheint kein zusätzliches X. Wo 0 zurückführt oder als Text eingegeben wird, bleibt X sichtbar. `x` und `exit` schließen weiterhin ohne Rückweg durch die Menüs. Bisherige Zurück- und Zahlenoptionen bleiben erhalten. Die Anwendung versucht dabei, die bisherigen Sitzungsdetails und den letzten Vorgangsstatus als eigenes lokales Protokoll zu sichern. Bei einem Schreibfehler erscheint ein Hinweis; das Beenden bleibt möglich. Bereits abgeschlossene Änderungen werden dadurch nicht rückgängig gemacht.

Der zentrale Eingabepfad wird durch eine AST-Prüfung abgedeckt. Isolierte Kindprozesse testen Untermenüs, Bestätigungen innerhalb von Fehlerbehandlung, das Ausführen von `finally`-Aufräumarbeiten, Antivirus-Ergebnisse, Pfadeingaben, Quarantäne-Auswahl und -Warnung, Logfehler sowie unveränderte normale Texteingaben. Alle 48 Tests sind bestanden; der PowerShell-5.1-Parser meldet in 60 aktiven Erstparteidateien keine Syntaxfehler.

Die Quarantäne-Wiederherstellung behält ihre explizite Warnung einschließlich Erkennungsname und Zielpfad. Erst die Bestätigung in dieser Warnung erlaubt dem Modul den Wiederherstellungsaufruf ohne eine zusätzliche fremde PowerShell-Abfrage. Seine Hash- und Überschreibschutzprüfungen bleiben erhalten.

Die Beenden-Option gilt, sobald die Anwendung auf eine Eingabe wartet. Laufende Scans, Windows-Reparaturen, UAC-Fenster und fremde Deinstallationsprogramme sind keine Eingabemenüs von REMNEXA; dieser Stand fügt dafür keinen neuen Abbruchmechanismus hinzu. Bereits geöffnete REMNEXA-Prozesse laden die Änderung erst beim nächsten Start.

## Verständliche Administratorhinweise

Vor allen von REMNEXA gestarteten Windows-Rechteabfragen erscheint ein Hinweis mit dem jeweiligen Grund. Die Hinweise unterscheiden Deinstallation, Rückstandsbereinigung, Registry, Windows-Funktionen, Datenschutz, Antivirus sowie das Deaktivieren und Wiederherstellen systemweiter Autostart-Einträge. Sie erklären die nächste Windows-Abfrage mit „Ja“ und „Nein“.

Enter öffnet die Windows-Abfrage erst nach dem Lesen. 0 kehrt ohne Rechteanfrage zurück; X beendet direkt. Ungültige Eingaben öffnen keine Abfrage. Bereits erhöhte Prozesse werden nicht erneut gefragt. `-NoElevation` verhindert die Anfrage weiterhin und zeigt einen allgemeinen, passenden Hinweis. Die Freigabe startet die Anwendung mit Administratorrechten; separate Bestätigungen für Systemänderungen bleiben erhalten.

Fünf zusätzliche Regressionstests prüfen Gründe und Reihenfolge aller Bereiche, Deinstallation gegenüber Rückstandsbereinigung, Zurück ohne Prozessstart, ungültige Eingaben und bereits erhöhte Prozesse. Ein weiterer Kindprozess-Test prüft X im Administratorhinweis. Insgesamt bestehen 54 Tests; der Parser meldet weiterhin keine Syntaxfehler in 60 aktiven PowerShell-Dateien. Die Tests simulieren die Windows-Anfrage und benötigen keine Administratorfreigabe auf dem Entwicklungsrechner.

## Abschluss, geschützte Reste und Sicherheitsstatus

Der vom Maintainer eingereichte Verlauf stammt aus 2.1.3. Die folgenden Korrekturen liegen ausschließlich im aktuellen Ordner `REMNEXA-2.2.0`. Bereits laufende Prozesse müssen zum Laden der Änderungen neu gestartet werden.

- `WindowsApps` unter Program Files und auf weiteren Laufwerken gehört zur Windows-Paketverwaltung. Treffer bleiben mit einem eigenen Hinweis sichtbar, werden aber nicht mehr dem rekursiven manuellen Löschen angeboten. Das betrifft auch die sechs Sticky-Notes-Verzeichnisse aus dem Verlauf. Sie können zu anderen Benutzern, bereitgestellten Paketen oder ausstehender Windows-Bereinigung gehören; dieser Stand behauptet keine bestimmte Ursache für jedes Verzeichnis. Die reguläre Appx-Deinstallation und ihre vorhandene Auswahl zur Provisionierung bleiben erhalten. Es gibt keinen Besitzwechsel und keine Änderung an Schutzrechten.
- Andere Zugriffsfehler enthalten einen verständlichen Hinweis und die tatsächliche Fehlermeldung. Geschützte Pakete zählen als bewusst übersprungen, echte fehlgeschlagene Löschaufrufe als Fehler. Über erfolgreich gelöschte Registry-Schlüssel mitentfernte Einträge werden gesondert gezählt. Ein Registry-Aufruf mit Exitcode 1 wird nicht länger als Erfolg gewertet; nach einem fehlgeschlagenen Elternschlüssel werden Kindwerte nicht stillschweigend ausgeschlossen.
- Das Bereinigungsergebnis, die Liste verbleibender Treffer und die Historie werden gespeichert; anschließend erreicht der Vorgang 100 %. Erst danach erscheint die optionale Dienste-/Sicherheitsprüfung. Deren Ergebnis wird getrennt protokolliert und verweist auf den ursprünglichen Lauf. Auch X an dieser Stelle lässt das bereits gespeicherte Bereinigungsergebnis bestehen.
- Die Dienstemomentaufnahme erklärt insbesondere `Stopped/Manual` als Start bei Bedarf und wertet dies allein nicht als Defekt. Deaktivierte oder nicht lesbare Dienste werden konkret benannt. Hinweise belegen keinen durch die Deinstallation verursachten Schaden; die Prüfung ändert keine Dienste.
- Antivirus wird aus `Get-MpComputerStatus` und der Windows-Sicherheitscenter-Registrierung eingeordnet. Ein registrierter Anbieter wie Panda Dome erklärt, warum Defender ruhen kann. Eine Registrierung ist ausdrücklich keine Bestätigung aktiven Echtzeitschutzes. Der nicht dokumentierte Zahlenwert `productState` wird protokolliert, aber nicht als Schutzgarantie interpretiert. Doppelmeldungen über denselben Defender-Zustand entfallen.
- Ein neuer Wiederherstellungspunkt muss von Windows mit einer eindeutigen, pro Aufruf neuen Kennung zurückgemeldet werden. Bei einer Frequenzsperre oder nicht bestätigtem Ergebnis erscheint keine falsche Erfolgsmeldung. Der bestehende Abbruch bzw. das ausdrücklich bestätigte Fortfahren ohne neuen Punkt bleibt bestehen. Windows-Richtlinien werden nicht geändert.

Vor diesen Änderungen wurden die betroffenen vorherigen Dateien in `Backup-2.2.0-completion-20261116-215309` gesichert und per SHA-256 geprüft. Das ist eine Teilsicherung dieses Korrekturschritts. Das vollständige Backup der ursprünglichen Version bleibt `REMNEXA\Backup-2.1.3`.

Fünfzehn neue, isolierte Regressionstests prüfen geschützte Pfade, Zugriffsfehler, Registry-Exitcodes und Abdeckung, bestätigte Wiederherstellungspunkte, die Reihenfolge beim Fortschrittsabschluss sowie verschiedene Antivirus- und Dienstestatus. Sie verwenden simulierte Lösch-/Registry-/Wiederherstellungsaufrufe und verändern keine realen Windows-Ressourcen. Insgesamt: 69 bestanden, 0 fehlgeschlagen. Der Parser meldet in 63 aktiven PowerShell-Dateien keine Syntaxfehler. Der Selbsttest im Auslieferungsordner besteht alle 12 Prüfungen.

Die zusätzliche rein lesende Prüfung auf dem Entwicklungsrechner bestätigt Panda Dome als registrierten Anbieter und Windows Update als `Stopped/Manual`; es entstehen daraus keine Warnungen. Der aktive Echtzeitschutz von Panda wurde nicht unabhängig verifiziert. Eine reale erneute Deinstallation von Sticky Notes, die interaktive Terminaldarstellung und die OneDrive-Cloud-Synchronisierung bleiben ungetestet.

PSScriptAnalyzer 1.24.0 wurde auf allen 63 aktiven PowerShell-Dateien ausgeführt: 0 Fehler, 305 Warnungen und 48 Informationseinträge. Die Warnungen betreffen unter anderem Konsolenausgaben, ungenutzte Parameter einschließlich Test-Doubles und bestehende Funktionskonventionen. Der Stand ist nicht warnungsfrei; ein produktiver Release wurde nicht veröffentlicht.

## Bedingte Seitennavigation und eindeutiges Beenden

Programm-, Autostart- und Dienstelisten verwenden jetzt dieselbe Prüfung für Seitenzahl und gültigen Seitenindex. Auf einer einzigen Seite werden weder nächste noch vorherige Seite angeboten. Auf der ersten Seite erscheint nur Weiter, auf der letzten nur Zurück, dazwischen beides. Nach einer Suche werden die Möglichkeiten neu ermittelt. Ein überholter Seitenindex wird auf den gültigen Bereich begrenzt.

Die bisherigen Tastennummern bleiben erhalten: Programme und Autostart nutzen -1/-2, Dienste 1/2. Nicht verfügbare Seitenbefehle ändern die Seite nicht. Der erklärende Hinweis steht beim nächsten Eingabemenü sichtbar neben den gültigen Optionen. Alle neuen Beschriftungen sind in sechs Sprachen enthalten.

An allen elf Eingabestellen, an denen 0 die Anwendung beendet, entfällt die zusätzliche X-Anzeige. Dazu zählen auch die Programmliste, Bestätigungen, Abschlussmenüs und gemischte Arbeitsabläufe. Bei 0 für Zurück bleibt X verfügbar. In Such- und Pfadeingaben bleibt 0 gewöhnlicher Text. Die stillen Kompatibilitätsbefehle x/exit und das Speichern beim direkten Beenden bleiben erhalten.

Vorherige Dateien: geprüfte Teilsicherung `Backup-2.2.0-navigation-20261116-221449` mit 14 Dateien. Das vollständige ursprüngliche 2.1.3-Backup bleibt unverändert.

Acht neue Regressionstests prüfen Seitenzustände, tatsächlich ausgegebene Menüoptionen in allen drei Listen, leere und exakt gefüllte Listen, Randseiten, Suchfilter, ungültige Seitenbefehle und alle Beenden-Kontexte. Zwei zusätzliche Kindprozess-Tests prüfen stille x-Beendigung und unveränderte 0-Eingaben ohne doppelte Anzeige. Gesamte Suite: 79 bestanden, 0 fehlgeschlagen. Die endgültige Anpassung zur dauerhaft sichtbaren Fehlermeldung wird zusätzlich mit den acht Navigationstests geprüft. Der Parser findet in 64 aktiven PowerShell-Dateien keine Syntaxfehler. Interaktive Darstellung im echten Benutzerfenster und OneDrive-Cloud-Synchronisierung wurden nicht manuell geprüft.

Der normale Sammellauf von PSScriptAnalyzer 1.24.0 brach einmal mit einem internen Nullverweisfehler ab. Als alternative Prüfung wurden alle 64 Dateien nacheinander mit demselben Analyzer geprüft: 0 Fehler, 322 Warnungen und 49 Informationseinträge. Der Stand ist weiterhin nicht warnungsfrei. Das Paketmanifest und die 14 Dateien der Teilsicherung wurden per SHA-256 geprüft; veränderliche ClamAV-Datenbanken bleiben ausgenommen.
