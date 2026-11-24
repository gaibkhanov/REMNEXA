[English](THIRD_PARTY_NOTICES.md) | [Deutsch](THIRD_PARTY_NOTICES.de.md)

# Drittkomponenten und Lizenzen

Die [MIT-Lizenz](../LICENSE) betrifft REMNEXA-Oberfläche und IPC-Transport. Der separate optionale native Adapter trägt eigene GPL-Hinweise. Die MIT-Lizenz lizenziert keine Abhängigkeiten, fremden Binärdateien, Datenbanken, Modelle oder sonstigen Inhalte um. Originale rechtliche Hinweise unverändert erhalten.

| Komponente | Rolle | Weitergabe und Pflichten |
| --- | --- | --- |
| PowerShell | Erforderliche Laufzeit ab 7.5 | Im Quellcode-Checkout nicht enthalten. Bei Weitergabe gelten PowerShells MIT-Lizenz und paketbezogene Drittanbieterhinweise. |
| ClamAV | Optionaler Scanner/Updater bei Bedarf | Binärdateien/Signaturen nicht im Quellcode. Upstream-ClamAV ist GPLv2; mitgelieferte Lizenzen/Hinweise erhalten und Quellcode-/Bereitstellungspflichten des konkreten Pakets prüfen. |
| Nativer REMNEXA-Scanadapter | Optionale libclamav-Anbindung in eigenem Prozess | `Antivirus/Workers/NativeEngine.cs` und `NativeScan.ps1` stehen unter GPL-2.0-or-later; der [GPL-Text](../Antivirus/Workers/COPYING.txt) liegt bei. `WorkerTransport.cs` bleibt MIT-lizenziert und ist beim Kompilieren in den Worker GPL-kompatibel. Quellenhinweise erhalten; weitergegebene verlinkte Worker müssen GPL-Quellcode-/Lizenzpflichten erfüllen. |
| Pester | Entwicklungstests | Keine Endnutzer-Laufzeitabhängigkeit. Vor Bündelung Lizenz/Hinweise der konkreten Upstream-Version prüfen. |
| PSScriptAnalyzer | Entwicklungsanalyse | Keine Endnutzer-Laufzeitabhängigkeit. Vor Bündelung Lizenz/Hinweise der konkreten Upstream-Version prüfen. |
| KI-Laufzeit/Modell | Nur geplant | Nichts ausgewählt oder mitgeliefert. Lizenz-/Weitergabeprüfung ist Abnahmebedingung, keine bereits erteilte Freigabe. |

Dies ist eine Bestands- und Prüfhilfe, keine Rechtsberatung oder Erklärung, dass alle künftigen Pakete rechtskonform sind. Ein Lizenzkürzel allein deckt nicht sämtliche enthaltenen Drittinhalte oder Datenbanken ab.

## Prüfliste für Maintainer

Complete-Kandidaten bündeln PowerShell mit originaler `LICENSE.txt` und `ThirdPartyNotices.txt`. Sie enthalten die unveränderten ClamAV-Laufzeitdateien und ursprünglichen `COPYING.txt`-/`COPYING/`-Hinweise sowie das passende offizielle Quellrelease unter `app/licenses/clamav/clamav-<version>.tar.gz`. Das Paketmanifest erfasst Upstream-Archivhashes und Signatur-Hashes. Debug-/Linkerartefakte entfallen, erforderliche Laufzeit-DLLs bleiben enthalten. UnRAR und Microsoft-Laufzeitbibliotheken behalten ihre eigenen Bedingungen; sie werden nicht als MIT/GPL umlizenziert. Quellen und GPL-Hinweise des nativen Adapters liegen weiterhin bei. Standard-/Quellpakete enthalten diese fremden Binärdateien und Datenbanken weiterhin nicht.

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
