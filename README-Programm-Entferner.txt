REMNEXA 2.1.3 FÜR WINDOWS

VERSION 2.1.3
  - Setzt die dokumentierte Mindestversion PowerShell 7.5 durch und erlaubt den Start mit einer installierten PowerShell-Laufzeit.
  - Nach Werkzeugen führt die Rückkehr wieder zur vorherigen Funktionsauswahl, auch im erweiterten Werkzeugbereich.
  - Ergebnisbildschirme erklären genau, welche Nummern hier gültig sind und wie man zur Funktionsauswahl zurückkehrt.
  - Nach einem Vorgang werden gefundene, entfernte, fehlgeschlagene und verbleibende Spuren getrennt angezeigt.
  - Integritätshinweise sind direkt lesbar; das zugehörige Protokoll kann geöffnet und nach dem Schließen weiterbearbeitet werden.
  - Nach der Bereinigung kann zur zuvor verwendeten Programmliste mit Suchfilter und Seitenposition zurückgekehrt werden.
  - REMNEXA bündelt Deinstallation, Antivirus, Autostart und Dienste in einem Arbeitsbereich.
  - Optionale lokale ClamAV-Prüfung ohne residenten Hintergrunddienst.
  - Portable ClamAV-Engine und Virensignaturen lassen sich getrennt aktualisieren.
  - Quick-, Full-, Custom- und gezielte Reste-Scans mit Zeitlimit.
  - Hash-gesicherte Quarantäne mit JSON-Manifest und bestätigter Wiederherstellung.
  - Die bisherigen Programm-Entferner-Startdateien bleiben als Kompatibilitätsstarter erhalten.
Start:
  Doppelklick auf "REMNEXA.cmd"

Der Ordner "runtime" enthält eine eigene portable PowerShell-Laufzeit. Beim
Kopieren oder Verschieben muss der komplette Ordner "REMNEXA" zusammenbleiben.

Das Hauptmenü startet ohne Administratorabfrage. Windows fragt erst dann nach
Administratorrechten, wenn eine tatsächlich schreibende Systemaktion ausgewählt
und bestätigt wurde.

Arbeitsbereiche:
  [1] Programme deinstallieren und Spuren bereinigen
  [2] Antivirus- und Malware-Prüfung mit ClamAV
  [3] Autostart-Programme verwalten
  [4] Aktive Windows-Dienste anzeigen
  [5] Entfernungshistorie ansehen
  [6] Anwendungs-Logs verwalten
  [7] Sprache ändern
  [8] Erweiterte Windows-Werkzeuge
  [0] REMNEXA beenden

Erweiterte Windows-Werkzeuge:
  [1] Systemintegrität prüfen
  [2] AppX/UWP-Apps verwalten
  [3] Verwaiste Registry-Einträge suchen
  [4] Optionale Windows-Features verwalten
  [5] Systemoptimierung und Datenschutz
  [0] Zurück
Nummerierte Befehle in langen Listen:
  positive Nummer = Eintrag auswählen
  [0]  Programm beenden
  [-1] nächste Seite
  [-2] vorherige Seite
  [-3] suchen
  [-4] Filter löschen
  [-5] zurück zum Hauptmenü

Sicherheitsvorschau:
  Datei-, Ordner- und Registry-Reste werden vollständig angezeigt. Nach der
  regulären Deinstallation erfolgt ein neuer Scan. Auch dessen Ergebnis wird
  angezeigt und nur nach einer weiteren ausdrücklichen Bestätigung gelöscht.
  Ohne diese Bestätigung bleiben die Reste erhalten.

Wiederherstellungspunkt:
  Vor schreibenden Systemaktionen versucht das Programm einen Windows-
  Wiederherstellungspunkt zu erstellen. Ist die Systemwiederherstellung
  deaktiviert oder schlägt die Erstellung fehl, stoppt das Programm. Der Nutzer
  muss dann [1] Abbrechen oder [2] ausdrücklich ohne Wiederherstellungspunkt
  fortfahren wählen. Der Kommandozeilenparameter -NoRestorePoint ist ebenfalls
  ein ausdrücklicher Override.

Geschützte Komponenten:
  Folgende Kategorien werden durch eine feste Sperrliste geschützt:
    - Windows Defender und Security Center
    - Windows-Update-Dienste und Update-Komponenten
    - Microsoft-Store-Infrastruktur
    - .NET Framework und .NET Runtime
    - Microsoft Visual C++ Redistributables

  Ein Entfernungsversuch zeigt eine rote Warnung und wird standardmäßig
  abgebrochen. Nur [2] "Override: trotzdem fortfahren" entsperrt genau die
  erkannte Kategorie. Für automatisierte Aufrufe existiert der ausdrückliche
  Parameter -OverrideProtectedComponent. Sicherheitskritische Registry-
  Grundbereiche bleiben unabhängig davon gesperrt.

AppX/UWP:
  AppX- und Store-Apps können nur für den aktuellen Benutzer entfernt werden.
  Optional kann zusätzlich das bereitgestellte Paket mit
  Remove-AppxProvisionedPackage aus dem laufenden Windows-System-Image entfernt
  werden. Das betrifft neue Benutzerprofile; bereits vorhandene andere Profile
  werden nicht automatisch bereinigt. Store-Infrastruktur bleibt geschützt.

Registry-Reste:
  Die normale Restesuche unter [4] durchsucht programmspezifische Schlüssel unter
  HKLM:\Software, HKLM:\Software\WOW6432Node und HKCU:\Software.

  Der separate Scan unter [8] -> [3] zeigt nur verdächtige Uninstall-Einträge,
  deren Installationsordner und Deinstallationsprogramm fehlen. Jeder Eintrag
  wird einzeln angezeigt und muss vor dem Löschen bestätigt werden.

Optionale Windows-Features:
  Unter [8] -> [4] werden nur aktuell aktivierte optionale Features aufgelistet.
  Das ausgewählte Feature wird über die Windows-DISM-Schnittstelle deaktiviert.
  Vorschau, Bestätigung, Wiederherstellungspunkt und Neustarthinweis bleiben
  Pflicht.

Systemintegrität:
  Unter [8] -> [1] sowie optional nach einer Entfernung prüft das Programm:
    - Windows Update
    - Background Intelligent Transfer Service
    - Microsoft Defender Antivirus
    - Windows Security Health
    - Microsoft Store Install Service
    - Defender-Antivirus- und Echtzeitschutzstatus

  Das Ergebnis wird im JSON-Log des Vorgangs gespeichert. Ein gestoppter Dienst
  ist nicht automatisch ein Defekt; insbesondere Windows Update arbeitet häufig
  im manuellen Startmodus. Abweichungen werden deshalb als Hinweise protokolliert.

Systemoptimierung und Datenschutz:
  Unter [8] -> [5] wird vorab jede Änderung angezeigt. Das Profil reduziert
  Telemetrie, deaktiviert DiagTrack, Werbe-ID und Feedback-Anfragen, setzt die
  Policies für Cortana und Copilot, schaltet Bing in der Windows-Suche sowie
  Consumer Features und App-Vorschläge ab.

  Vor der ersten Anwendung werden die vorhandenen Registry-Werte und der
  DiagTrack-Status in
  %LOCALAPPDATA%\REMNEXA\PrivacyBackup.json
  gesichert. Menüpunkt [2] im Datenschutzmenü stellt genau diese Werte wieder her.

Speicherplatz:
  Vor und nach jeder echten Entfernung wird der freie Platz des Windows-Laufwerks
  gemessen. Ein positiver Unterschied wird in Bytes, KB, MB oder GB angezeigt,
  im JSON-Log gespeichert und in die Historie übernommen. Gleichzeitige Downloads,
  Updates oder andere Systemaktivitäten können diese Messung beeinflussen.

Historie:
  Nach jeder tatsächlich ausgeführten Entfernung werden Datum, Programmname,
  Anzahl entfernter Spuren, Abschlussstatus und gemessener Speichergewinn
  gespeichert. Die letzten drei Entfernungen erscheinen beim Start.

  Datei: %LOCALAPPDATA%\REMNEXA\History.jsonl

Logs:
  %LOCALAPPDATA%\REMNEXA\Logs

  Menüpunkt [7] löscht nur die dort von der Anwendung erstellten JSON- und
  LOG-Dateien. Historie, Sprache und Datenschutz-Sicherung bleiben erhalten.

Sprachen:
  Deutsch, English, Español, Français, Русский und Türkçe.

Fortschritt:
  Die Anzeige von 1 bis 100 Prozent zeigt die aktuelle Arbeitsphase. Sie ist
  keine sekundengenaue Zeitprognose.

Eigene Dateien:
  Desktop, Dokumente und Downloads werden standardmäßig nicht durchsucht oder
  gelöscht. Der erweiterte Parameter -IncludeUserFiles muss ausdrücklich gesetzt
  werden.

Nur prüfen, nichts verändern:
  .\runtime\pwsh.exe -NoProfile -File .\REMNEXA.ps1 -Name "Programmname" -DryRun

Nur nach Resten suchen:
  .\runtime\pwsh.exe -NoProfile -File .\REMNEXA.ps1 -Name "Programmname" -ResidualOnly

Wichtige Grenze:
  Kein allgemeines Werkzeug kann Spuren in verschlüsselten Datenbanken,
  Browser-Synchronisation, Cloud-Backups oder proprietären Fremdprogrammen
  zuverlässig erkennen. Deshalb bleiben Vorschau, Bestätigung und Log wichtig.
