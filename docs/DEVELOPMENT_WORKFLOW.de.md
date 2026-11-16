[English](DEVELOPMENT_WORKFLOW.md) | [Deutsch](DEVELOPMENT_WORKFLOW.de.md)

# Entwicklungsablauf

Maßgeblicher Quellcode ist das [REMNEXA-Repository](https://github.com/gaibkhanov/REMNEXA). Verwende einen frei gewählten lokalen Checkout; Projektdokumentation darf nicht von persönlichen Dateipfaden eines Mitwirkenden abhängen.

## Branches und Umfang

- `main`: bestehende stabile Basis.
- `feature/2.2.0-development`: aktuelle Entwicklung von 2.2.0.
- Weitere Feature-Branches: klar abgegrenzte Änderungen von einem benannten Commit.

Prüfe vor Änderungen `git status`, Branch, Remote und Diff. Erhalte uncommittete Arbeit. Ohne erforderliche Maintainer-Freigabe keine Releases überschreiben, gemeinsame Historie umschreiben, Force-Pushes durchführen oder in den stabilen Branch zusammenführen.

Optionale Laufzeiten, ClamAV-Programme/-Signaturen, Sicherungen und private Logs gehören nicht zum Entwicklungsquellcode. Keine kompletten rechnerbezogenen Anwendungsordner nach Git kopieren.

## Lokale Prüfungen

Nutze PowerShell ab 7.5; installiere Pester (mindestens 3.4.0 für den lokalen Runner) und PSScriptAnalyzer 1.24.0 in der Entwicklungsumgebung.

```powershell
pwsh -NoProfile -File .\tools\Invoke-RemnexaTests.ps1
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
pwsh -NoProfile -File .\REMNEXA.ps1 -SelfTest
git diff --check
```

Führe dies im Projektordner aus. Liegen Analyzer-Module außerhalb des normalen Modulsuchpfads, übergib deren übergeordneten Ordner über `-ModuleRoot`. Der Runner meldet alle Befunde und scheitert bei Fehlern; Warnungen benötigen weiterhin Prüfung.

Der Selbsttest inventarisiert ausgewählte Systemfähigkeiten. Er deinstalliert keine Programme und belegt nicht die Sicherheit sämtlicher Vorgänge. Sensible Tests müssen isolierte Testdaten und simulierte Aufrufe verwenden.

## CI

[quality.yml](../.github/workflows/quality.yml) verwendet `windows-latest`, Pester 5.7.1 und PSScriptAnalyzer 1.24.0, führt Pester und eine Analyzer-Fehlerprüfung aus und verlangt PowerShell ab 7.5.

Pfadfilter starten den Workflow bei PowerShell-, Test- und Workflow-Änderungen; reine Dokumentations-Pushes lösen ihn nicht automatisch aus. Manueller Start ist vorgesehen. Eine konfigurierte CI ist kein Beleg eines erfolgreichen Laufs; prüfe die tatsächlichen Ergebnisse vor dem Zusammenführen.

## Prüfung und Veröffentlichung

1. Beschreibe Verhaltensänderung und betroffene Schnittstellen.
2. Führe passende Prüfungen aus und dokumentiere echte Versionen/Zahlen, Fehler und Grenzen.
3. Pflege betroffene englische/deutsche Dokumente und sechs Oberflächensprachen.
4. Prüfe vorgemerkte Änderungen auf Geheimnisse, private Pfade, erzeugte Dateien und versehentliche Löschungen.
5. Committe abgegrenzte Änderungen, pushe nur den vorgesehenen Branch und prüfe den Remote-Commit.
6. Bereite Release-Pakete erst nach gesonderter Kompatibilitäts-, Packaging-, Sicherheits- und Wiederherstellungsprüfung vor.

Siehe [Prüfstand 2.2.0](VERSION_2.2.0.de.md), [Analyse-Basis](STATIC_ANALYSIS_BASELINE.de.md) und [Sicherungsanleitung](BACKUP_AND_CHECKPOINTS.de.md). Ein Quellcode-Push ist weder ein stabiles Release noch die Erlaubnis zur Veröffentlichung.
