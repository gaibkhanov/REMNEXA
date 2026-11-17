function Get-AVConfig {
    <#
    .SYNOPSIS
    Liest die ClamAV-Konfiguration.

    .DESCRIPTION
    Liest config/antivirus.json, expandiert jedoch keine Pfade. Dadurch kann die
    Konfiguration unveraendert gespeichert und zwischen Rechnern uebertragen werden.

    .PARAMETER Path
    Optionaler Pfad zu einer alternativen JSON-Konfigurationsdatei.

    .EXAMPLE
    Get-AVConfig

    .EXAMPLE
    Get-AVConfig -Path 'D:\Config\antivirus.json'
    #>
    [CmdletBinding()]
    param([string]$Path = $script:AVConfigPath)

    $resolvedPath = Expand-AVPath $Path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Antivirus-Konfiguration nicht gefunden unter '$resolvedPath'."
    }
    try {
        $config=Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach($entry in @{AutoCheckUpdates=$true;UpdateCheckIntervalHours=24;UpdateNetworkTimeoutSeconds=3;UpdateRetryCount=1;UpdateRetryBackoffSeconds=1}.GetEnumerator()) {
            if(-not $config.PSObject.Properties[$entry.Key]) { $config|Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value }
        }
        return $config
    }
    catch {
        throw "Antivirus-Konfiguration '$resolvedPath' ist ungueltig: $($_.Exception.Message)"
    }
}
