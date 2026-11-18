[English](SECURITY_MODEL.md) | [Deutsch](SECURITY_MODEL.de.md)

# Sicherheitsmodell

Gilt für den implementierten Entwicklungsquellcode 2.2.0. Geplante Schutzmaßnahmen gelten nicht als fertig. Sicherheitsmeldungen: [SECURITY.de.md](../SECURITY.de.md).

## Schutzgüter und Vertrauensgrenzen

Zu schützen sind Benutzerdateien, gemeinsam genutzte Programmressourcen, Registry-Zustand, Dienste-/Aufgabenkonfiguration, Quarantäneintegrität und vertrauliche Diagnosedaten.

Anwendungsnamen, registrierte Deinstallationsbefehle, Dateimetadaten, heruntergeladene Archive, Restore-Daten, Logs und künftige KI-Ausgaben sind nicht vertrauenswürdig. Ein Namenstreffer belegt keine Zugehörigkeit. Erhöhte Rechte vergrößern mögliche Schäden und ersetzen keine Validierung.

## Implementierte Maßnahmen

| Grenze | Aktueller Schutz | Einschränkung |
| --- | --- | --- |
| Berechtigungen | Hauptmenü ohne Erhöhung; aktionsbezogener RunAs-Hinweis; Abbruchpfade | Erhöhung startet einen erhöhten Anwendungsprozess, keinen getrennten Rechte-Broker. |
| Bereinigung | Vorschau/Bestätigung, Standardschutz, WindowsApps-Ausschluss, Elternpfadprüfung | Zuordnung teils heuristisch; Dateisystem-Zeitfenster bleibt. |
| Downloads | HTTPS und passender SHA-256 vor ClamAV-Entpacken | Vertrauenswürdige Metadaten/Quelle nötig; kein allgemeines signiertes Update-System. |
| Konfiguration | Schema, atomare Ersetzung und Rücklesen unterstützter Einstellungen | Keine Sicherung des gesamten Windows-Zustands. |
| Datenschutz-Restore | Unterstützte Registry-Pfade/-Namen/-Typen vor Schreiben prüfen | Keine allgemeine kryptografische Authentisierung oder transaktionale Systemwiederherstellung. |
| Prozesse | Gemeinsamer Prozessadapter ruft seine Prozesse ohne Shell auf | Registrierte Hersteller-Deinstallationsprogramme bleiben Vertrauensgrenze. |
| Quarantäne | Bewusste Aktion, Manifest/Hash und Überschreibschutz beim Restore | Wiederherstellen kann Schadsoftware zurückbringen. |
| Logging | Strukturierte Ereignisse und klare Ergebniskategorien | Logs können sensible Pfade oder Befehle enthalten. |

Windows muss einen neuen Wiederherstellungspunkt mit eindeutiger Beschreibung bestätigen. Fehler oder Frequenzsperren gelten nicht als Erfolg. Unterstützte interaktive Abläufe erlauben ausdrücklich bestätigtes Fortfahren ohne neuen Punkt; nicht interaktiv müssen Schutzbedingungen erfüllt werden oder der Ablauf stoppen.

Die optionale native Scan-Engine nutzt private vererbte Pipes, einen nicht erhöhten Worker, einen Versuch mit eingeschränktem Token sowie Job-Limits und Beenden beim Ende des Besitzers. Sie öffnet keinen Daemon-TCP-Zugang. Dies ist keine vollständige Sandbox gegen native Sicherheitslücken. Der Start aus einer erhöhten Hauptanwendung und weitere Windows-Konfigurationen benötigen eigene Tests; siehe [Sicherheitsgrenzen der privaten Engine](PRIVATE_SCAN_ENGINE.de.md).

## KI-Grenze

`Core/AiContracts.psm1` begrenzt ausdrücklich gelieferte Daten und validiert Empfehlungen; Befehlsfelder werden abgewiesen. **Modell und Inferenzlaufzeit fehlen.** Die Verträge sind Vorarbeit, keine nachgewiesene Prozessisolation.

Künftige KI darf weder Shell, Löschung, Registry-Änderung, Dienstesteuerung noch Rechteerhöhung auslösen. Empfehlungen bleiben inaktiv. Nur geprüfte regelbasierte Funktionen dürfen bestätigte Änderungen ausführen. Systemberichte und Modelltexte gelten als nicht vertrauenswürdige Daten; generierte Befehle gehören nicht direkt in eine Shell.

## Wiederherstellung und sicherer Fehlerfall

Geschützte Pfade nicht beschreibbar erzwingen und keinen Besitz übernehmen, um Reste zu löschen. Bewusst übersprungene Einträge, Fehler und verbleibende Treffer unterscheiden. Fehlgeschlagene Registry-Elternlöschung darf Kinder nicht stillschweigend als entfernt behandeln.

Die gestufte ClamAV-Installation stellt bei Konfigurationsübernahmefehlern die vorherige Engine wieder her. Signaturupdate-Rollback, vollständige Dienste-/Aufgaben-/Dateiwiederherstellung und ein zentrales Restore-Center sind offen. Keine vollständige Erholung von fremden Deinstallationen versprechen.

## Prüfprioritäten

Gezielte Tests mit simulierten Aufrufen und isolierten Daten decken ausgewählte Maßnahmen ab. Offen sind angegriffene Pfad-Zeitfenster, gemeinsame Ressourcen, Berechtigungsfehler unter echten Windows-Konten, unterbrochene Vorgänge, Installer-/Deinstaller-VMs und vollständige Wiederherstellungstests.

Keine destruktiven Tests gegen echte Benutzerdaten ohne ausdrückliche Freigabe. Beachte [Kompatibilitätsgrenzen](COMPATIBILITY_MATRIX.de.md) und [Analyse-Basis](STATIC_ANALYSIS_BASELINE.de.md), bevor du Testerfolge als umfassenden Sicherheitsnachweis deutest.
