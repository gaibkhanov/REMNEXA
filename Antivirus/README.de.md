[English](README.md) | [Deutsch](README.de.md)

# Optionale ClamAV-Integration

REMNEXA bindet ClamAV für lokale Prüfungen bei Bedarf ein. Es bietet keinen residenten Schutzdienst und ersetzt weder Microsoft Defender noch einen anderen Antivirus. Beachte [Benutzerhandbuch](../docs/USER_GUIDE.de.md) und [Sicherheitsmodell](../docs/SECURITY_MODEL.de.md).

## Bestandteile und Voraussetzungen

Der Quellcode enthält die PowerShell-Anbindung, nicht ClamAV-Programme oder Signaturdatenbanken. Die Einrichtung benötigt ein unterstütztes Windows-ClamAV-Paket, Internet und passende Berechtigungen. Die Anwendung erklärt die Rechteerhöhung vor Öffnen des Antivirus-Bereichs. Bei Modulaufrufen müssen erforderliche Rechte für Systemziele oder Installationspfade bereitstehen.

Modul im Projektordner laden:

```powershell
Import-Module .\Antivirus\Antivirus.psd1
Get-ClamAVStatus
Get-AVConfig
```

## Intelligente Updateprüfung

Kandidat rc.3 prüft beim Start offizielle Engine-/Datenbankmetadaten in einem stillen Hintergrundprozess, normalerweise einmal täglich. Diese Prüfung installiert keine Pakete. Im Antivirus-Bereich steht der gespeicherte Zustand; **U** prüft sofort und bietet unterstützte Updates an, **I** zeigt Details. Konsolenscans bieten bestätigte ausstehende Updates an und fragen nach einem Updatefehler gesondert vor dem Weiterlaufen. Mit einer vorhandenen funktionsfähigen Datenbank bleiben Offline-Scans möglich. Nachrichten in sechs Sprachen, Einstellungen, Cache-/Wiederholungsregeln und Prüfgrenzen beschreibt die [Updateanleitung](../docs/CLAMAV_SMART_UPDATES.de.md).

## Installation und Updates

Nutze die Einrichtung in der Anwendung oder fordere die Installation ausdrücklich an:

```powershell
Initialize-ClamAV -Install
Update-ClamAVSignature
```

Downloads benötigen HTTPS und einen gültigen, passenden SHA-256-Wert. Die automatische Einrichtung ist von geeigneten Upstream-Release-Metadaten abhängig; fehlende oder fehlerhafte Prüfsummen brechen die Installation ab. Direkte Archivinstallation erfordert `-DownloadUri` und `-ExpectedSha256` aus vertrauenswürdiger Quelle. Keine Prüfsumme erfinden und die Prüfung nicht umgehen.

Die Installation bereitet die Engine neben dem Ziel vor, erhält vorhandene Signaturen und bewahrt die ersetzte Engine auf. Fehler bei der Konfigurationsübernahme führen zur vorherigen Engine zurück. Ein anschließender Signaturupdate-Fehler liegt außerhalb dieser Transaktion; nicht jeder frühere Zustand wird automatisch wiederhergestellt. Für behaltene Engine-Sicherungen gibt es keine Wiederherstellungsoberfläche.

`Update-ClamAVEngine` aktualisiert die Engine; `Update-ClamAVSignature` verwendet freshclam für Signaturen. Das sind getrennte Vorgänge. Signaturalter-Warnungen gelten standardmäßig ab sieben Tagen; prüfe die tatsächliche Konfiguration.

## Scans

Beispiele nach Einrichtung von Engine und Signaturen:

```powershell
Invoke-ClamAVScan -ScanType Quick
Invoke-ClamAVScan -ScanType Full
Invoke-ClamAVScan -ScanType Custom -Path '.\scan-fixture' -Timeout 1800
```

Das eigene Prüfziel im Beispiel muss als Ordner existieren. Wähle Ziele bewusst.

| Typ | Umfang |
| --- | --- |
| Quick | Konfigurierte typische Infektionsorte, einschließlich temporärer und Autostart-Orte. |
| Full | Definierte Windows-, Programm- und Benutzerwurzeln; keine Garantie für jeden Datenträger/jede Datei. |
| Custom | Ausdrücklich angegebene vorhandene Ziele; mindestens eines ist erforderlich. |

`-IncludePUA` aktiviert die Erkennung potenziell unerwünschter Anwendungen und kann Fehlalarme erhöhen. `-MaxFileSize`, Ausschlüsse und Limits beeinflussen die Abdeckung. Gesperrte Dateien, Berechtigungen, Archivgrenzen und Zeitlimits können vollständige Prüfung verhindern.

ClamAV-Exitcode 0 bedeutet keine Funde, 1 Funde und 2 einen Scanfehler. Ein Fund ist keine automatisch bestätigte Infektion; keine Funde sind kein Sicherheitsbeweis.

Kandidat rc.2 erfasst Dateien vor dem ClamAV-Aufruf, fasst überlappende Wurzeln zusammen und überspringt verknüpfte Pfade. Beim Scan verwendet die Prozentzahl gemeldete Dateiergebnisse im Verhältnis zur Erfassung, ergänzt um Phase, aktuellen Eintrag und Laufzeit. Laden der Engine und Erfassung erhalten keine erfundene Zeitprozentzahl. Fehlende Rückmeldungen oder übersprungene Erfassung ergeben Hinweise und unvollständige Abdeckung; Fehler sind rot, erfolgreicher Abschluss ist grün. Zähler beschreiben Dateirückmeldungen, keine vollständige Prüfung aller Archivmitglieder oder Restzeitschätzung. Ausschlüsse und ClamAV-Grenzen gelten weiterhin. Siehe [Fortschritts- und Prüfdetails](../docs/RELEASE_2.2.0_RC2.de.md).

Scans nutzen lokale Engine/Signaturen und sind offline möglich. Die Scanfunktion lädt selbst keine neuen Signaturen. Einrichtung, ausdrückliche Updates und andere konfigurierte Aktualisierungsschritte können Internet benötigen; bereite die Offline-Konfiguration vor und prüfe sie. Veraltete Signaturen begrenzen den Nutzen.

## Quarantäne und Wiederherstellung

Normale Scans melden Funde. `-Quarantine` erlaubt ausdrücklich das Verschieben erkannter Dateien in verwaltete Quarantäne mit SHA-256-gesichertem JSON-Manifest. Der allgemeine Standardpfad lautet `%ProgramData%\REMNEXA\Quarantine`; die Konfiguration kann ihn ändern.

`Get-ClamAVQuarantine` listet Einträge. Prüfe Erkennung, Originalpfad und Wiederherstellungsziel, bevor du die Wiederherstellung in der Anwendung oder `Restore-ClamAVQuarantine -Identifier` nutzt. Wiederherstellen kann eine Bedrohung zurückbringen. Das Modul prüft den gespeicherten Hash und verweigert vorhandene Zieldateien.

`-Force` ist keine Fehlerumgehung: Es überspringt die Modulbestätigung, nicht Integritäts- und Überschreibschutz. Die Oberfläche zeigt vor dem Aufruf eine eigene ausdrückliche Warnung. Keine Quarantänedateien oder privaten Manifeste veröffentlichen.

## Konfiguration

Kandidat rc.4 ergänzt **P** im Antivirus-Menü für Eco/Balanced/Fast-Prozessprioritäten. Während eines Scans brechen **X**, **Esc** oder **Strg+C** den Vorgang mit unvollständiger Abdeckung ab. Je konfigurierter Installation läuft höchstens ein REMNEXA-Scan/Update. Engine-Limitwarnungen sind sichtbar und werden nie als Malware in Quarantäne verschoben. Siehe [Verhalten und Benchmark-Grenzen](../docs/CLAMAV_SCAN_PERFORMANCE.de.md).

Verwende `config/antivirus.json`, `Get-AVConfig` und `Set-AVConfig`; bevorzuge unterstützte validierte Schreibvorgänge:

```powershell
Set-AVConfig -Values @{
    ScanBeforeRemoval = $false
    ScanAfterRemoval = $true
    IncludePUA = $false
    MaxFileSize = '100M'
}
```

Die Einstellungen ändern zukünftiges Verhalten und starten nicht unmittelbar einen Scan. Prüfe vor großen Scans Pfade, Ausschlüsse, Signaturrichtlinie und Zeitlimit. Logs und Quarantäne werden gemäß Konfiguration ausgeschlossen. Das [Ablaufbeispiel](../Examples/Invoke-AntivirusWorkflow.ps1) zeigt die Modul-API.

## Fehlerbehebung und Lizenzen

Prüfe Engine-/Signaturbereitschaft, konkrete Fehler, Berechtigungen und konfigurierte Pfade vor einem neuen Versuch. Eine Warnung zum Signaturalter ist etwas anderes als ein Startfehler der Engine. Deaktiviere vorhandene Sicherheitssoftware nicht, um REMNEXA zu erzwingen.

ClamAV hat eigene Lizenz- und Drittanbieterhinweise, unabhängig von REMNEXAs MIT-Lizenz. Erhalte diese bei Weitergabe. Siehe [Drittanbieterhinweise](../docs/THIRD_PARTY_NOTICES.de.md) und [offizielle ClamAV-Dokumentation](https://docs.clamav.net/).
