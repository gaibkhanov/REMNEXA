[English](USER_GUIDE.md) | [Deutsch](USER_GUIDE.de.md)

# Benutzerhandbuch

Gilt für die **Entwicklungsversion 2.2.0**. Installation: [Projekt-README](../README.de.md). Prüfgrenzen: [Kompatibilitätsmatrix](COMPATIBILITY_MATRIX.de.md).

## Start und Berechtigungen

Starte `REMNEXA.cmd` oder führe aus:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1
```

PowerShell ab 7.5 ist erforderlich. Das Hauptmenü startet ohne Administratorabfrage. Vor erhöhtem Zugriff für eine Aktion oder den Antivirus-Bereich erklärt REMNEXA den Grund. Enter öffnet die Windows-Abfrage; Ja erlaubt die Erhöhung, Nein lehnt ab. Im Hinweis kehrt 0 zurück und X beendet. Ein bereits erhöhter Prozess fragt nicht erneut.

Die Administratorfreigabe startet einen erhöhten Anwendungsprozess. Sie erlaubt nicht beliebige Änderungen; gesonderte Aktionsbestätigungen bleiben erforderlich.

## Navigation und Beenden

Beachte die Auswahlmöglichkeiten der aktuellen Eingabe. Eine Nummer aus einem anderen Bildschirm wählt hier keine Aktion.

- Wo **0 Beenden bedeutet**, ist dies die einzige angezeigte Beenden-Option.
- Wo **0 Zurück bedeutet** oder normale Texteingabe vorgesehen ist, bietet **X** direktes Beenden.
- `x` und `exit` bleiben Beenden-Aliasse. Vor dem Schließen wird die Sitzungsprotokollierung versucht.
- Angezeigte Zurück-Optionen führen zur vorherigen Funktion oder Programmliste; beim Zurückkehren zur Programmliste bleiben Seite und Filter erhalten.
- Programm- und Autostart-Listen zeigen nächste/vorherige Seiten nur bei deren Existenz. Verfügbare Befehle stehen im Menü; nicht verfügbare Seitenwechsel werden erklärt.

Beenden gilt, solange REMNEXA auf Eingaben wartet. Es ergänzt keinen Abbruchmechanismus für laufende fremde Deinstallationsprogramme, Scans, Reparaturbefehle oder Windows-Rechteabfragen. Warte bei kritischen Schreibvorgängen auf deren Abschluss; erzwungenes Schließen kann sie unterbrechen.

## Anwendung entfernen

1. Öffne den Deinstallationsbereich, filtere bei Bedarf und wähle die angezeigte Programmnummer.
2. Prüfe das genaue Produkt und die Vorschau. Treffer können Dateien, Registry-Einträge, Dienste und Aufgaben umfassen; sie sind kein eindeutiger Eigentumsnachweis.
3. Lies Schutz- und Administratorhinweise. Unterstützte Schreibvorgänge versuchen einen Wiederherstellungspunkt. Kann kein neuer Punkt bestätigt werden, erklärt der Hinweis Abbruch oder ausdrücklich bestätigtes Fortfahren ohne neuen Punkt.
4. Bestätige die reguläre Deinstallation und beachte die Abfragen des Herstellers.
5. Prüfe die neue Rückstandssuche. Bestätige die Bereinigung getrennt oder behalte die Reste.
6. Lies verbleibende Einträge und Ergebnisse. Ergebnis und Historie werden gespeichert; der Vorgang erreicht vor der optionalen Systemzustandsprüfung 100 %.
7. Öffne das Protokoll, kehre zur vorherigen Programmliste zurück oder beende über die angezeigte Auswahl.

Die normale Rückstandssuche schließt persönliche Ordner aus. Die erweiterte Suche kann persönliche Dateien einbeziehen: Prüfe diese Kandidaten besonders sorgfältig.

### Store-Pakete und behaltene Einträge

Unterstützte Appx-Entfernung betrifft das ausgewählte Paket des aktuellen Benutzers. Eine optionale Änderung der Bereitstellung beeinflusst zukünftige Benutzerprofile; sie entfernt die Anwendung nicht automatisch aus allen bestehenden Profilen.

Windows verwaltet WindowsApps-Verzeichnisse selbst. Diese bleiben erhalten, statt manuell gelöscht zu werden. Sie können andere Profile, bereitgestellte Pakete oder ausstehende Windows-Bereinigung betreffen; der Verzeichnisname allein belegt keine bestimmte Ursache. REMNEXA übernimmt keinen Besitz und ändert keine ACLs, um Löschung zu erzwingen.

Ein bewusst übersprungener Windows-Pfad ist etwas anderes als eine fehlgeschlagene Löschung. Prüfe bei tatsächlichen Zugriffsfehlern Pfad und konkrete Meldung. Administratorrechte machen nicht jeden Pfad sicher oder beschreibbar.

### Zahlen verstehen

Vorherige und nachfolgende Suchläufe sind getrennte Momentaufnahmen. Ein erfolgreich entfernter Registry-Elternschlüssel kann Kindwerte mitentfernen; diese werden getrennt von einzelnen Löschaufrufen gezählt. Übersprungen, fehlgeschlagen und noch vorhanden bedeuten Unterschiedliches und sind nicht einfach unabhängige Summanden.

Änderungen des freien Speicherplatzes hängen auch von anderen Programmen und Windows ab. Sie messen nicht exakt die durch REMNEXA freigegebenen Bytes.

## Sichere Vorschau per Kommandozeile

Im Projektordner:

```powershell
pwsh -NoProfile -File .\REMNEXA.ps1 -Name 'Example application' -DryRun
pwsh -NoProfile -File .\REMNEXA.ps1 -Name 'Example application' -ResidualOnly -DryRun
```

Ersetze den Beispielnamen durch das gewünschte Produkt. Behalte `-DryRun` für eine rein lesende Vorschau. `-ResidualOnly` allein garantiert keinen schreibfreien Ablauf. Erweiterte Umgehungsoptionen ersetzen weder die Prüfung geplanter Änderungen noch Sicherungen.

## Autostart-Verwaltung

Prüfe Speicherort, Befehl und Geltungsbereich, bevor du einen unterstützten Eintrag deaktivierst. Die unterstützte Wiederherstellung aktiviert ihn wieder. Systemweite Änderungen können erhöhte Rechte benötigen. Sicherungen umfassen unterstützte Eintragstypen, nicht sämtliche Autostart-Mechanismen oder eine vollständige Windows-Wiederherstellung.

## Systemübersicht und Windows-Werkzeuge

Die Systemübersicht liest bei Aufruf Windows-/CIM-Daten: Windows-Version und Build, CPU, Arbeitsspeicher und feste Laufwerke. Sie optimiert Windows nicht automatisch.

Der Dienste-Bereich zeigt Zustände. Die optionale Zustandsprüfung repariert keine Dienste. Gestoppt/manuell kann normal sein. Antivirus-Registrierung und Defender-Daten liefern Kontext, aber keine Schutzgarantie und keinen Beweis für einen Deinstallationsschaden.

Ausgewählte erweiterte Werkzeuge bieten Windows-Reparatur, optionale Features, Prüfung von Registry-Kandidaten und Datenschutzeinstellungen. Lies jede Bestätigung und mögliche Neustartanforderung. Einzelne Werkzeuge können Installationsmedien oder Internet benötigen. Ändere Richtlinien oder Dienste nicht pauschal ohne Verständnis der Wirkung.

Unterstützte Datenschutzsicherungen werden vor Wiederherstellung gegen eine feste Registry-Liste geprüft. Das ist eine begrenzte Konfigurationswiederherstellung, kein vollständiges System-Rollback.

## Antivirus

Der optionale Antivirus-Bereich erklärt die Rechteerhöhung und bietet Engine-/Signatur-Einrichtung, Scans und Quarantäne. Lies vor Verwendung die [ClamAV-Anleitung](../Antivirus/README.de.md). Ein Scan bietet keinen Echtzeitschutz.

## Protokolle, Historie und Wiederherstellung

Entfernungsprotokolle liegen unter `%LOCALAPPDATA%\REMNEXA\Logs`, die Historie unter `%LOCALAPPDATA%\REMNEXA\History.jsonl`. Dies sind allgemeine Anwendungspfade. Nach Schließen des Protokollfensters kehrt die Öffnen-Aktion zum Ergebnis zurück. Bewahre benötigte Protokolle vor dem Leeren auf.

Protokolle und Konfigurationssicherungen können private Pfade, Befehle oder Programmnamen enthalten. Prüfe und bereinige sie vor Weitergabe. Veröffentliche keine Quarantänedateien.

Die [Sicherungsanleitung](BACKUP_AND_CHECKPOINTS.de.md) erklärt Quellcode-Zwischenstände. Weder diese noch ein Wiederherstellungspunkt installieren jede entfernte Anwendung neu oder retten sämtliche persönlichen Daten.

## Fehlerbehebung

| Symptom | Prüfen |
| --- | --- |
| Starter findet PowerShell nicht | PowerShell ab 7.5 installieren oder Paket mit passender Laufzeit verwenden. |
| Rechteanfrage abgelehnt | Aktion erneut öffnen und nur nach Prüfung des Hinweises freigeben. |
| WindowsApps-Einträge bleiben | Beabsichtigter Schutz; unterstützte Windows-Paketverwaltung verwenden. |
| Kein neuer Wiederherstellungspunkt | Gemeldete Einschränkung lesen; ein vorhandener Punkt ist keine neue Sicherung. |
| Antivirus-Engine/Signaturen fehlen | Optionale Einrichtung abschließen; Installation und Signaturupdates benötigen Internet. |
| Menüaktion nicht verfügbar | Auswahl des aktuellen Bildschirms verwenden; Seitenwechsel nur bei vorhandener weiterer Seite. |

Für reproduzierbare Fehler gelten die Hinweise zu bereinigten Berichten in [CONTRIBUTING.de.md](../CONTRIBUTING.de.md).
