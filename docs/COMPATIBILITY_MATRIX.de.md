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
| Pester | CI/lokal 5.7.1 | rc.8: 204 lokale Tests bestanden; dessen GitHub-Qualitätslauf erfolgreich. Endgültige Release-CI wird vor Veröffentlichung geprüft. |
| PSScriptAnalyzer | 1.24.0 | rc.8: Fehlerprüfung für 106 PowerShell-Dateien bestanden; historische Fehler bleiben im ursprünglichen Bericht dokumentiert. |
| Desktop-/MSI-Entfernung | Registrierte unterstützte Deinstallationsprogramme | Simulierte/gezielte Tests; breite Herstellerintegration offen. |
| Store-/Appx-Entfernung | Unterstützte Pakete des aktuellen Benutzers | Bereitstellung hat anderen Umfang; Mehrbenutzermatrix offen. |
| Rechte | Navigation ohne Erhöhung, bei Bedarf bewusste Freigabe | Tatsächlicher erhöhter nativer Worker-Start unter Windows 11 geprüft; vollständige Konto-/UAC-Matrix offen. |
| ClamAV | Optionale unterstützte Windows-Engine und Signaturen | Einrichtungstests zertifizieren nicht jede Upstream-Version. |
| Offline-Nutzung | Lokale Werkzeuge mit vorhandenen Komponenten | Einrichtung/Updates und manche Reparaturen brauchen Internet/Medien; vollständiges Offline-Paket ungeprüft. |
| Sprachen | de, en, es, fr, ru, tr | Schlüssel-/Platzhaltergleichheit in sechs Sprachen geprüft; vollständige Sprach-/Barrierearmutsprüfung offen. |
| Lokale KI | Geplante eingebettete Laufzeit und Modell | Nicht implementiert; keine CPU-/RAM-/Modell-Benchmarks. |
| Installer/portable Ausgabe | Geplante geprüfte Pakete | Geprüftes Quell-ZIP mit Prüfsumme; kein 2.2.0-Installer, Complete-KI-Paket oder digitale Signatur. |

## Noch erforderliche Release-Prüfungen

Teste frische unterstützte Windows-Systeme, Standard-/Administratorkonten, gesperrte/gemeinsame Ressourcen, abgebrochene UAC, Neustarts, Reparaturfehler, unterbrochene Updates und Rollback in wegwerfbaren VMs. Dokumentiere genaue Builds, Hardware und Komponentenstände.

Prüfungen zu Scanlebenszyklus, CLI-/nativen Messungen und Ressourcenlimits liegen vor; siehe Release-Hinweise und verlinkte Messprotokolle. Daraus folgen keine universellen Beschleunigungsversprechen, Startzeit-/Leerlaufziele oder KI-Leistungswerte.

Siehe [Prüfbericht](VERSION_2.2.0.de.md) und [Roadmap](DEVELOPMENT_ROADMAP.de.md).

## Aktueller Prüfstand für 2.2.0

Der [Release-Prüfstand](RELEASE_2.2.0.de.md) ergänzt diese Matrix: rc.8 bestand 204 lokale Pester-Tests, 12 Selbsttests und die Fehleranalyse von 106 PowerShell-Dateien; auch dessen GitHub-CI war erfolgreich. Tatsächlicher erhöhter Worker-Start, Ressourcenlimits und CLI-/native Scans sind dokumentiert. Das endgültige Quellrelease wird erneut geprüft. Quell-ZIP und Prüfsumme ersetzen keinen Installer oder eine digitale Signatur. Windows 10, echte 8-GB-VM, HDD und die vollständige Konto-/UAC-Matrix bleiben ungeprüft.
