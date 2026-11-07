#requires -Version 5.1

<#
Dieses Beispiel installiert nichts ungefragt und loescht keine Datei.
Die Quarantaene wird erst nach einer ausdruecklichen Auswahl aktiviert.
#>

[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Antivirus\Antivirus.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module -Name $ModulePath -Force -ErrorAction Stop

$status = Initialize-ClamAV
if (-not $status.Installed) {
    Write-Warning 'ClamAV wurde nicht eingerichtet. Der Ablauf wird beendet.'
    return
}

# Die Engine-Aktualisierung ist bewusst eine getrennte Aktion:
# Update-ClamAVEngine

if (-not $status.Ready -or $status.SignaturesOutdated) {
    $status = Update-ClamAVSignature
}

Write-Host 'ClamAV-Status:' -ForegroundColor Cyan
$status | Format-List Installed, Ready, Version, SignatureDate, SignatureAgeDays, Signatures, ClamScanPath, DatabasePath

$results = @(Invoke-ClamAVScan -ScanType Quick)
$results | Format-Table Status, Severity, Signature, Path -AutoSize

$findings = @($results | Where-Object { $_.Status -eq 'Infected' })
if ($findings.Count -gt 0) {
    Write-Warning "Funde: $($findings.Count). Es wurde noch nichts verschoben oder geloescht."
    $answer = (Read-Host 'Gefundene Einzeldateien jetzt in Quarantaene verschieben? [j/N]').Trim()
    if ($answer -match '^(?i:j|ja|y|yes)$') {
        $filePaths = @($findings.Path | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($filePaths.Count -gt 0) {
            Invoke-ClamAVScan -Path $filePaths -ScanType Custom -Quarantine |
                Format-Table Status, Signature, Path, QuarantineId -AutoSize
        }
    }
}

Write-Host 'Aktive Quarantaene-Eintraege:' -ForegroundColor Cyan
Get-ClamAVQuarantine | Format-Table QuarantineId, Signature, OriginalPath, QuarantinedAt -AutoSize
