[English](THIRD_PARTY_NOTICES.md) | [Deutsch](THIRD_PARTY_NOTICES.de.md)

# Drittkomponenten und Lizenzen

Die [MIT-Lizenz](../LICENSE) betrifft REMNEXAs eigenen Code gemäß ihrem Wortlaut. Sie lizenziert keine Abhängigkeiten, fremden Binärdateien, Datenbanken, Modelle oder sonstigen Inhalte um. Originale rechtliche Hinweise unverändert erhalten.

| Komponente | Rolle | Weitergabe und Pflichten |
| --- | --- | --- |
| PowerShell | Erforderliche Laufzeit ab 7.5 | Im Quellcode-Checkout nicht enthalten. Bei Weitergabe gelten PowerShells MIT-Lizenz und paketbezogene Drittanbieterhinweise. |
| ClamAV | Optionaler Scanner/Updater bei Bedarf | Binärdateien/Signaturen nicht im Quellcode. Upstream-ClamAV ist GPLv2; mitgelieferte Lizenzen/Hinweise erhalten und Quellcode-/Bereitstellungspflichten des konkreten Pakets prüfen. |
| Pester | Entwicklungstests | Keine Endnutzer-Laufzeitabhängigkeit. Vor Bündelung Lizenz/Hinweise der konkreten Upstream-Version prüfen. |
| PSScriptAnalyzer | Entwicklungsanalyse | Keine Endnutzer-Laufzeitabhängigkeit. Vor Bündelung Lizenz/Hinweise der konkreten Upstream-Version prüfen. |
| KI-Laufzeit/Modell | Nur geplant | Nichts ausgewählt oder mitgeliefert. Lizenz-/Weitergabeprüfung ist Abnahmebedingung, keine bereits erteilte Freigabe. |

Dies ist eine Bestands- und Prüfhilfe, keine Rechtsberatung oder Erklärung, dass alle künftigen Pakete rechtskonform sind. Ein Lizenzkürzel allein deckt nicht sämtliche enthaltenen Drittinhalte oder Datenbanken ab.

## Prüfliste für Maintainer

1. Genaue Upstream-Version, Quelle, Hash und enthaltene Dateien bestimmen.
2. Lizenz und sämtliche Begleithinweise einschließlich indirekter Bestandteile lesen.
3. Änderungs-, Weitergabe-, Quellbereitstellungs- und Nennungspflichten prüfen.
4. Hinweise beim Paket erhalten und enthaltene Komponenten dokumentieren.
5. Downloadintegrität prüfen und Sicherheitsupdates nachvollziehbar halten.
6. Keine ungeprüften Modellgewichte verteilen oder unter REMNEXAs MIT-Lizenz darstellen.

## Offizielle Quellen

- [PowerShell](https://github.com/PowerShell/PowerShell)
- [ClamAV](https://github.com/Cisco-Talos/clamav)
- [Pester](https://github.com/pester/Pester)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

Bei Bewertung von `llama.cpp` oder einem Qwen-Modell vor Auswahl und Weitergabe die Lizenz der genauen Revision/des Modells prüfen. Siehe [Roadmap](DEVELOPMENT_ROADMAP.de.md).
