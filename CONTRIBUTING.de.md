[English](CONTRIBUTING.md) | [Deutsch](CONTRIBUTING.de.md)

# Mitwirken

REMNEXA begrüßt Fehlerkorrekturen, Übersetzungen, Tests und Dokumentation. Arbeite vom aktuellen Entwicklungsbranch aus; `main` enthält nicht zwangsläufig den neuesten Entwicklungsstand.

## Vor Codeänderungen

1. Lies [Architekturprüfung](docs/ARCHITECTURE_AUDIT.de.md), [Sicherheitsmodell](docs/SECURITY_MODEL.de.md) und [Entwicklungsablauf](docs/DEVELOPMENT_WORKFLOW.de.md).
2. Erstelle einen klar abgegrenzten Feature-Branch von der vorgesehenen Basis.
3. Erhalte bestehende Funktionen und Übersetzungsschlüssel. Begründe erforderliche Verhaltensänderungen.
4. Ergänze aussagekräftige Regressionstests, insbesondere für Löschung, Prozessaufrufe, Berechtigungen und Wiederherstellung.
5. Führe destruktive Tests ausschließlich in isolierten Testdaten oder wegwerfbaren Windows-VMs aus.

Test-Deinstallationen, großflächige Löschung, echte Registry-Wiederherstellungen oder Änderungen an Sicherheitsfunktionen gehören nicht auf den produktiv genutzten Entwicklungsrechner.

## Prüfungen

Mit PowerShell ab 7.5 im Projektordner:

```powershell
pwsh -NoProfile -File .\tools\Invoke-RemnexaTests.ps1
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
```

Installiere zuvor passende Pester- und PSScriptAnalyzer-Module in der Entwicklungsumgebung. CI-Versionen und Grenzen der lokalen Prüfung stehen im Entwicklungsablauf. Nenne Werkzeugversionen, Testzahlen, Fehler und übersprungene Fälle. Alte Ergebnisse sind kein neuer Testlauf.

Bei reinen Dokumentationsänderungen: relative Links, Sprachfassungen, Beispiele, private Angaben und Versionsaussagen prüfen. Keine destruktiven Beispiele ausführen.

## Pull Requests

Beschreibe Problem, neues Verhalten, Tests und verbleibende Grenzen. Trenne unabhängige Änderungen. Keine Laufzeitdateien, Signaturen, Modellgewichte, Sicherungen, Zugangsdaten, privaten Logs oder rechnerbezogenen Pfade aufnehmen. Prüfe vor dem Push `git diff --cached`.

Für Sicherheitslücken gilt [SECURITY.de.md](SECURITY.de.md). Öffentliche Fehlerberichte sollen bereinigte Versions-/Build-Angaben, Reproduktionsschritte und erwartetes/tatsächliches Verhalten enthalten.

## Sprachen und Lizenzen

Halte die sechs Oberflächenressourcen konsistent. Pflege englische und deutsche Dokumentation gemeinsam und verlinke die Sprachfassungen gegenseitig. Codebezeichner nicht übersetzen; rechtliche Lizenztexte nicht ändern.

Prüfe vor Aufnahme von Abhängigkeiten oder Weitergabe von Binärdateien/Modellen deren Lizenzen. Die MIT-Lizenz des Projekts gilt nicht automatisch für Drittkomponenten.

Ein Entwicklungs-Push ist keine Release-Freigabe. Produktive Veröffentlichungen benötigen erfolgreiche Prüfung und ausdrückliche Freigabe des Maintainers.
