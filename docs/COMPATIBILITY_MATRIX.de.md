[English](COMPATIBILITY_MATRIX.md) | [Deutsch](COMPATIBILITY_MATRIX.de.md)

# Kompatibilitätsmatrix

**Ziel** bedeutet nicht **validiert**. Diese Matrix trennt Voraussetzungen und dokumentierte lokale Prüfungen von einer Release-Zertifizierung.

| Bestandteil/Szenario | Ziel oder Voraussetzung | Prüfstatus |
| --- | --- | --- |
| Windows | Windows 10 / 11 | Prüfungen am Entwicklungsrechner; saubere VM-Matrix offen. |
| Architektur | Windows-x64-Paket | Keine vollständige x64-Installationsmatrix; ARM64 und 32 Bit nicht validiert. |
| PowerShell | Ab 7.5 | Lokale Tests auf 7.6.9 dokumentiert; Mindestversion wird geprüft. |
| Windows PowerShell 5.1 | Nicht als Anwendungslaufzeit unterstützt | Fehlerfreies Parsen macht sie nicht zur unterstützten Laufzeit. |
| Quellcode-Starter | Passende mitgelieferte Laufzeit, sonst `PATH` | Laufzeit optional und nicht im Quellrepository. |
| Pester | Lokaler Runner ab 3.4.0; CI fest 5.7.1 | 79 Tests auf 3.4.0 dokumentiert; CI mit 5.7.1 hier nicht bestätigt. |
| PSScriptAnalyzer | 1.24.0 | Fehlerprüfung bestanden; Warnungen und Vollanalyse-Absturz dokumentiert. |
| Desktop-/MSI-Entfernung | Registrierte unterstützte Deinstallationsprogramme | Simulierte/gezielte Tests; breite Herstellerintegration offen. |
| Store-/Appx-Entfernung | Unterstützte Pakete des aktuellen Benutzers | Bereitstellung hat anderen Umfang; Mehrbenutzermatrix offen. |
| Rechte | Navigation ohne Erhöhung, bei Bedarf bewusste Freigabe | Simulierte Erhöhungstests; vollständige Konto-/UAC-Matrix offen. |
| ClamAV | Optionale unterstützte Windows-Engine und Signaturen | Einrichtungstests zertifizieren nicht jede Upstream-Version. |
| Offline-Nutzung | Lokale Werkzeuge mit vorhandenen Komponenten | Einrichtung/Updates und manche Reparaturen brauchen Internet/Medien; vollständiges Offline-Paket ungeprüft. |
| Sprachen | de, en, es, fr, ru, tr | Je 282 Schlüssel geprüft; vollständige Sprach-/Barrierearmutsprüfung offen. |
| Lokale KI | Geplante eingebettete Laufzeit und Modell | Nicht implementiert; keine CPU-/RAM-/Modell-Benchmarks. |
| Installer/portable Ausgabe | Geplante geprüfte Pakete | Kein validierter 2.2.0-Installer, Complete-KI-Paket oder signiertes Release. |

## Noch erforderliche Release-Prüfungen

Teste frische unterstützte Windows-Systeme, Standard-/Administratorkonten, gesperrte/gemeinsame Ressourcen, abgebrochene UAC, Neustarts, Reparaturfehler, unterbrochene Updates und Rollback in wegwerfbaren VMs. Dokumentiere genaue Builds, Hardware und Komponentenstände.

Gemessene Ziele für Startzeit, Leerlaufspeicher, Scans oder KI-Leistung fehlen. Keine festen Beschleunigungs- oder Ressourcenversprechen ohne reproduzierbare Benchmarks.

Siehe [Prüfbericht](VERSION_2.2.0.de.md) und [Roadmap](DEVELOPMENT_ROADMAP.de.md).
