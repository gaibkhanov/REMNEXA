[English](SECURITY.md) | [Deutsch](SECURITY.de.md)

# Sicherheitsrichtlinie

REMNEXA kann Deinstallationsprogramme aufrufen sowie Dateien, Registry-Daten und unterstützte Systemeinstellungen ändern. Es ist ein Wartungswerkzeug mit sensiblen Aktionen und keine Sicherheitsgrenze oder Antivirus-Ersatz.

## Sicherheitslücke melden

Nutze GitHubs private Schwachstellenmeldung im Security-Bereich des Repositorys, **sofern aktiviert**. Ist sie nicht verfügbar, eröffne ein minimales Issue mit der Bitte um einen privaten Meldekanal. Veröffentliche keine Exploitdetails, Zugangsdaten, privaten Logs oder persönlichen Pfade. Hier ist keine private Kontaktadresse oder garantierte Antwortzeit festgelegt.

Nenne betroffene Version/Commit, bereinigte Reproduktionsschritte, Auswirkungen und gegebenenfalls einen Lösungsvorschlag. Verwende künstliche Testdaten. Keine Ausnutzung auf Systemen ohne Erlaubnis testen.

## Unterstützungsstatus

Der aktuelle 2.2.0-Branch ist ein Entwicklungsstand. Es bestehen keine formale Langzeitpflege oder garantierten Sicherheitsreaktionszeiten. Melde Probleme gegen den aktuellen Stand und nenne bekannte betroffene ältere Versionen. Eine vorhandene Veröffentlichung ist nicht automatisch sicherheitszertifiziert.

## Grenzen und bekannte Einschränkungen

- Vorschauen und Bestätigungen verringern versehentliche Änderungen, beweisen aber nicht die Zugehörigkeit jedes Treffers.
- Reparse-Point-Prüfungen verkleinern das Zeitfenster zwischen Pfadprüfung und Zugriff, schließen es jedoch nicht.
- Wiederherstellungspunkte und unterstützte Konfigurationssicherungen garantieren keine vollständige Wiederherstellung.
- ClamAV bietet optionale Prüfungen bei Bedarf, keinen dauerhaften Schutz.
- KI-Verträge existieren; Modell und Inferenzlaufzeit fehlen. Künftige KI-Ausgaben bleiben nicht vertrauenswürdige Empfehlungen.
- Prüfe die Herkunft registrierter Deinstallationsbefehle, bevor du ihnen vertraust.

[Sicherheitsmodell](docs/SECURITY_MODEL.de.md) und [Entwicklungsbericht](docs/VERSION_2.2.0.de.md) beschreiben Schutzmaßnahmen und offene Prüfungen.

## Diagnosedaten weitergeben

Entferne Benutzernamen, Kontokennungen, persönliche absolute Pfade, Tokens, Dateiinhalte sowie sensible Programm- und Befehlsdetails. Keine Malware- oder Quarantänedateien in öffentliche Issues hochladen. Sicherheitsupdates von Drittkomponenten müssen unabhängig von der REMNEXA-Version berücksichtigt werden.
