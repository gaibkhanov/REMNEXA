[English](RELEASE_2.2.0_RC1.md) | [Deutsch](RELEASE_2.2.0_RC1.de.md)

# REMNEXA 2.2.0-rc.1

**Status: Quellcode-Release-Candidate, keine stabile Version.** Veröffentlichung benötigt Maintainer-Freigabe. Vorhandene Releases werden nicht ersetzt. Der Kandidat erweitert die [Basis 2.2.0](VERSION_2.2.0.de.md).

## Verbesserungen

- Bildschirmleeren fällt bei umgeleiteter Ausgabe oder fehlenden Cursor-APIs sicher aus. Ein Starttest des entpackten Pakets deckte diesen Absturz auf; ein echter Hauptmenü-/Beenden-Test schützt nun dagegen.

- Bei Prozess-Zeitüberschreitung wird das Beenden des gestarteten Prozessbaums angefordert. Aufräumen wartet höchstens fünf zusätzliche Sekunden; Fehler werden statt falschem Erfolg gemeldet. Auch Ausgabeabschluss hält das Zeitlimit ein. Dies ergänzt weder einen allgemeinen UI-Abbruchknopf noch garantierte Kontrolle über abgetrennte/erhöhte Prozesse.
- Die Windows-Argumentkodierung erhält leere Argumente.
- Quellcode-Zwischenstände schließen oberste Git-Metadaten, erzeugte Pakete und alte Zwischenordner aus. Überschreibschutz und SHA-256-Prüfung bleiben erhalten.
- Ein Paketwerkzeug für saubere Commits übernimmt nur versionierten Quellcode, prüft Pfade, verweigert vorhandene Ausgaben und kontrolliert das fertige Archiv.
- Das Paket enthält ein Dateimanifest; eine getrennte SHA-256-Datei sichert das ZIP. Prüfung ohne Entpacken weist veränderte/fehlende/nicht gelistete Inhalte, ungültige Pfade, doppelte Namen und falsche erwartete Hashes ab.
- Der Qualitätsworkflow baut und lädt das geprüfte Quellarchiv als Artefakt hoch. Er veröffentlicht kein GitHub-Release.

Die Oberfläche zeigt `2.2.0-rc.1`. Bestehende Deinstallation, Autostart-, Antivirus-, Navigations- und Sprachfunktionen bleiben erhalten.

## Lokale Prüfung

| Prüfung | Ergebnis |
| --- | --- |
| Unveränderte Ausgangsbasis, Pester 3.4.0 | 79 bestanden, 0 fehlgeschlagen. |
| Kandidatensuite, Pester 3.4.0 / PowerShell 7.6.9 | 89 bestanden, 0 fehlgeschlagen, 0 übersprungen. |
| Kandidatensuite, Pester 5.7.1 / PowerShell 7.6.9 | 89 bestanden, 0 fehlgeschlagen, 0 übersprungen. |
| Eigene Syntax- und Analyzer-Fehlerprüfung | 68 PowerShell-Dateien, 0 Syntaxfehler, 0 Analyzer-Fehler. |

Dies sind lokale Ergebnisse. Remote-CI und eine frische Windows-10/11-Installationsmatrix sind damit nicht belegt. Verbleibende Warnungen sind [getrennt dokumentiert](STATIC_ANALYSIS_BASELINE.de.md). Jedes erzeugte Paket muss vor Veröffentlichung die Paketprüfung und einen Selbsttest der entpackten Anwendung bestehen.

## Bauen und prüfen

Für Maintainer im sauberen committeten Checkout mit Git und PowerShell ab 7.5:

```powershell
$package = .\tools\New-RemnexaPackage.ps1 -Version '2.2.0-rc.1'
.\tools\Test-RemnexaPackage.ps1 -Path $package.Package -ExpectedSha256 $package.SHA256
```

Ausgabe: `dist/REMNEXA-2.2.0-rc.1-source.zip` und zugehörige `.sha256`-Datei. Das Manifest nennt Quellcommit, Version, Dateigrößen und Hashes, keine Entwickler-Rechnerpfade. Ausgaben werden nie überschrieben. Für einen zweiten Build einen anderen Ausgabeordner verwenden. Bauen benötigt Git; Anwender brauchen für das entpackte Paket kein Git.

Erwarteten Archiv-Hash aus dem vertrauenswürdigen Release-Kanal beziehen. Eine gemeinsam mit einem nicht vertrauenswürdigen Paket gelieferte Prüfsumme beweist keine Echtheit. Eine digitale Signatur liegt nicht vor.

## Kandidaten starten

Archiv prüfen, in ein neues Verzeichnis entpacken und darin `REMNEXA.cmd` im Versionsordner starten. PowerShell ab 7.5 muss installiert und über `PATH` erreichbar sein. Das Quellpaket enthält weder optionale Laufzeit noch ClamAV-Engine/Signaturen oder KI-Modell. Vorversion und unabhängige Sicherungen behalten. Laufende REMNEXA-Instanzen neu starten, damit der neue Code geladen wird.

Diagnoseprüfung im entpackten Anwendungsordner:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
```

Dies prüft ausgewählte Fähigkeiten, keine vollständige Wiederherstellung oder Sicherheit. Das [Benutzerhandbuch](USER_GUIDE.de.md) erklärt Entfernungsvorschauen und Bestätigungen.

## Zurückgestellte Arbeit und Veröffentlichungsgrenze

Neuer Installer, Paket mit Laufzeit, Modell-/KI-Laufzeitintegration und digitale Signierung sind nicht geliefert. Windows-VM-Abdeckung, echte Rollbacks, Mehrbenutzerentfernung und vollständige Offline-Pakettests bleiben offen. Pfad-Zeitfenster und heuristische Rückstandszuordnung bleiben bekannte Grenzen.

Der Quellkandidat kommt nach Paketprüfung und Freigabe als ausdrücklich gekennzeichnete Vorabversion infrage. Diese Prüfungen machen ihn weder zum stabilen Release noch zu REMNEXA 3.0. Siehe [Roadmap](DEVELOPMENT_ROADMAP.de.md).
