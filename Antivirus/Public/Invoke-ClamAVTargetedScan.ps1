function Invoke-ClamAVTargetedScan {
    <#
    .SYNOPSIS
    Scannt gezielt beim Entfernen eines Programms gefundene Datei-Reste.

    .DESCRIPTION
    Filtert Registry-, Dienst- und Aufgabenobjekte aus der Reste-Liste heraus und
    reicht nur vorhandene Dateien oder Ordner an Invoke-ClamAVScan weiter.

    .PARAMETER Path
    Ein oder mehrere konkrete Reste-Pfade.

    .PARAMETER Quarantine
    Verschiebt Funde in die konfigurierte Quarantaene.

    .PARAMETER IncludePUA
    Aktiviert PUA-Erkennung.

    .PARAMETER MaxFileSize
    Maximale Dateigroesse, zum Beispiel 100M.

    .PARAMETER Timeout
    Maximale Laufzeit in Sekunden.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .EXAMPLE
    Invoke-ClamAVTargetedScan -Path 'C:\ProgramData\OldApp', 'C:\Temp\old.dll'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Path,
        [switch]$Quarantine,
        [switch]$IncludePUA,
        [string]$MaxFileSize,
        [ValidateRange(1, 86400)][int]$Timeout = 0,
        [string]$ConfigPath = $script:AVConfigPath
    )

    $parameters = @{
        Path       = @($Path)
        ScanType   = 'Custom'
        Quarantine = [bool]$Quarantine
        IncludePUA = [bool]$IncludePUA
        ConfigPath = $ConfigPath
    }
    if ($MaxFileSize) { $parameters.MaxFileSize = $MaxFileSize }
    if ($Timeout -gt 0) { $parameters.Timeout = $Timeout }
    $results = @(Invoke-ClamAVScan @parameters)
    foreach ($result in $results) { $result.ScanType = 'Targeted' }
    return $results
}
