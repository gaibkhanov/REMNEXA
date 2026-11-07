# Optionale ClamAV-Integration

Dieses Submodul erweitert REMNEXA um lokale On-Demand-Scans. Es
implementiert keinen Echtzeitschutz, keinen Hintergrunddienst und keine eigene
Signaturdatenbank. Funde werden nie automatisch geloescht. Eine Datei wird nur
mit dem ausdruecklichen Parameter `-Quarantine` verschoben.

## Voraussetzungen

- Windows 10 oder 11 und PowerShell ab Version 7.5.
- Internetzugang fuer Installation und Signaturaktualisierung.
- Administratorrechte fuer Windows-, Program-Files- und ProgramData-Pfade.
- Die offizielle portable ClamAV-Windows-Version. `Initialize-ClamAV` kann das
  aktuelle Paket aus den offiziellen Cisco-Talos-Releases beziehen. Standardziel
  ist der portable Unterordner `ClamAV` direkt im Anwendungsverzeichnis.

Offizielle Dokumentation:

- https://docs.clamav.net/manual/Installing.html
- https://docs.clamav.net/manual/Usage/SignatureManagement.html
- https://docs.clamav.net/manual/Usage/Scanning.html

## Schnellstart

```powershell
Import-Module .\Antivirus\Antivirus.psd1 -Force
Initialize-ClamAV
Update-ClamAVEngine
Update-ClamAVSignature
Invoke-ClamAVScan -ScanType Quick
```

Eine vollstaendige, interaktive Abfolge steht in
`Examples/Invoke-AntivirusWorkflow.ps1`.

## Konfiguration

Die Datei `config/antivirus.json` enthaelt alle Pfade und Standards. Die Datei
bleibt bewusst gueltiges JSON; Erlaeuterungen stehen deshalb in `_comment` statt
in JavaScript-artigen Kommentarzeilen.

```powershell
Get-AVConfig
Set-AVConfig -Values @{
    ScanBeforeRemoval = $false
    ScanAfterRemoval  = $true
    IncludePUA        = $false
    MaxFileSize       = '100M'
}
```

Umgebungsvariablen wie `%ProgramData%` und `%LocalAppData%` duerfen in den
Pfaden verwendet werden. Der Quarantaene- und der Logordner werden automatisch
vom Scan ausgeschlossen.

## Funktionen

- `Initialize-ClamAV`: erkennt eine Installation oder richtet das portable
  offizielle Windows-Paket gefuehrt ein.
- `Update-ClamAVEngine`: aktualisiert die portable Scan-Engine getrennt von den
  Signaturen und stellt bei einem fehlgeschlagenen Austausch die alte Version
  automatisch wieder her.
- `Update-ClamAVSignature`: aktualisiert die Datenbank mit `freshclam.exe` und
  warnt nach dem konfigurierten Hoechstalter, standardmaessig sieben Tage.
- `Get-ClamAVStatus`: liefert Version, Signaturstand, Pfade und Bereitschaft.
- `Invoke-ClamAVScan`: Quick-, Full- oder Custom-Scan.
- `Invoke-ClamAVTargetedScan`: scannt konkrete Reste aus der Deinstallation.
- `Get-ClamAVScanResult`: parst ClamAV-Ausgabe in flache Ergebnisobjekte.
- `Get-ClamAVQuarantine`: listet aktive Quarantaene-Manifeste.
- `Restore-FromClamAVQuarantine`: stellt nach Warnung und Bestaetigung wieder her.
- `Get-AVConfig` und `Set-AVConfig`: lesen und aendern die JSON-Konfiguration.

Alle oeffentlichen Funktionen besitzen Comment-Based Help, zum Beispiel:

```powershell
Get-Help Invoke-ClamAVScan -Full
```

## Scanarten und Sicherheit

`Quick` prueft Temp, AppData, LocalAppData, Downloads, beide Startup-Ordner und
typische ausfuehrbare Dateien unter ProgramData. `Full` prueft die definierten
Windows-, Programm- und Benutzerpfade. `Custom` verlangt mindestens einen
existierenden Pfad.

ClamAV-Exit-Codes werden wie vorgesehen behandelt: 0 ist sauber, 1 bedeutet
mindestens einen Fund, 2 ist ein Scanfehler. Ein Fund ist daher kein technischer
Fehler. Das Zeitlimit beendet einen haengenden Prozess.

`-IncludePUA` kann mehr Fehlalarme verursachen. Eine PUA-Meldung bedeutet nicht
automatisch Schadsoftware. Vor einer Wiederherstellung prueft das Modul den im
Manifest gespeicherten SHA-256-Hash. Ein bereits vorhandener Originalpfad wird
nie ueberschrieben.

## Integration in REMNEXA

Das Hauptprogramm importiert das Modul beim Start. Unter `[9] Erweiterte
Windows-Werkzeuge` steht `[6] ClamAV-Malware-Pruefung` bereit. Dort sind die
Engine-Aktualisierung und die Signaturaktualisierung getrennte Optionen. Die Optionen
`ScanBeforeRemoval` und `ScanAfterRemoval` steuern die automatische, rein
meldende Pruefung der gefundenen Datei- und Ordnerreste. Diese Integration
verwendet bewusst nicht `-Quarantine`: Verschieben bleibt eine ausdrueckliche
Nutzerentscheidung.

## Bekannte Einschraenkungen

- ClamAV ist eine zusaetzliche Zweitmeinung und ersetzt unter Windows keinen
  aktuellen residenten Schutz wie Microsoft Defender.
- Verschluesselte oder kennwortgeschuetzte Archive koennen nicht vollstaendig
  geprueft werden.
- Zugriffsrechte, Dateisperren und ClamAV-Groessenlimits koennen Dateien
  ueberspringen.
- Bei `--infected` meldet ClamAV nur Funde. `Write-Progress` zeigt deshalb die
  Vorbereitungs-, Scan- und Auswertungsphasen sowie die Zahl der Scan-Ziele,
  nicht eine erfundene exakte Dateiprozentzahl.
- Die portable Installation verwendet keinen ClamAV-Dienst und keinen
  Echtzeitschutz.
- Der komplette Anwendungsordner kann kopiert werden; `ClamAVPath` und
  `DatabasePath` sind standardmaessig relativ und bleiben dadurch portabel.
