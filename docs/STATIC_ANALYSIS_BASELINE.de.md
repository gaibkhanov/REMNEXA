[English](STATIC_ANALYSIS_BASELINE.md) | [Deutsch](STATIC_ANALYSIS_BASELINE.de.md)

# Basis der statischen Analyse

**Werkzeug:** PSScriptAnalyzer 1.24.0 auf PowerShell 7.6.9. Dies ist ein dokumentierter Anwendungscode-Stand und kein neuer Scan der Dokumentationsänderung.

## Umfang und Ergebnisse

64 eigene PowerShell-Quell-, Modul-, Manifest-, Test- und Werkzeugdateien. Historische Sicherungen, fremde Laufzeit-/ClamAV-Inhalte und Analyzer-Abhängigkeiten sind ausgeschlossen.

| Lauf | Fehler | Warnungen | Informationen | Bedeutung |
| --- | --- | --- | --- | --- |
| Frühere sequenzielle Vollanalyse desselben Anwendungscodes | 0 | 322 | 49 | Dokumentierte Warnungsbasis, kein Nachweis von Warnungsfreiheit. |
| Prüfung ausschließlich auf Fehler im Git-Checkout | 0 | Nicht angefordert | Nicht angefordert | Über 64 Dateien vollständig abgeschlossen. |
| Vollanalyse mit Warnungen im Git-Checkout | Unvollständig | Unvollständig | Unvollständig | Zeitweiser Nullreferenzfehler bei `tests/Navigation.Tests.ps1`. |

Eine erfolgreiche reine Fehlerprüfung und einen unvollständigen Vollscan nicht als vollständige neue Analyse zusammenfassen. Frühere Zahlen mit kleinerem Dateiumfang sind überholt und nicht wie identische Scans vergleichbar.

## Prüfprioritäten

- Leere Catch-Blöcke und zustandsändernde Funktionen ohne einheitliches `ShouldProcess` prüfen.
- Zuweisungen an automatische Variablen, ungenutzte Parameter und globale Kompatibilitätszustände vor Umbau untersuchen.
- `Write-Host` ist oft beabsichtigte Konsolenausgabe; einzelne Warnungen trotzdem im Kontext prüfen.
- Beim Ändern pluraler Namen und älterer Verben bestehende Aufrufbarkeit erhalten.
- Reine Datenkonstruktoren ändern das System nicht nur wegen New im Namen; Befunde einzeln bewerten.
- Kodierung, Kommentarhilfe und Ausgabetypen gegen die PowerShell-7.5+-Voraussetzung bewerten.

Keine ganzen Kategorien pauschal unterdrücken oder jede Warnung als harmlos darstellen. Regelzahlen kleinerer früherer Scans sind keine aktuelle vollständige Prüfung.

## Reproduzieren

PSScriptAnalyzer 1.24.0 installieren, dann im Projektordner:

```powershell
pwsh -NoProfile -File .\tools\RunPSScriptAnalyzer.ps1 -ProjectRoot (Get-Location).Path
```

Der Runner zeigt Befunde und scheitert bei Analyzer-Fehlern. Der Vollscan kann den dokumentierten Werkzeugfehler reproduzieren. Bereinigte Fehlerdetails erfassen und ein minimales Beispiel isolieren; Tests nicht zum Verbergen des Fehlers verändern.

Der [CI-Workflow](../.github/workflows/quality.yml) prüft ausschließlich Fehler. Seine Definition belegt keinen erfolgreichen Remote-Lauf. Siehe [Entwicklungsablauf](DEVELOPMENT_WORKFLOW.de.md) und [Prüfbericht](VERSION_2.2.0.de.md).
