function Get-ClamAVQuarantine {
    <#
    .SYNOPSIS
    Listet die von der Anwendung verwalteten ClamAV-Quarantaene-Eintraege auf.

    .DESCRIPTION
    Liest alle JSON-Manifeste aus dem konfigurierten Quarantaene-Ordner und gibt
    flache Objekte zur Anzeige in Konsole oder WPF-DataGrid zurueck.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .PARAMETER IncludeRestored
    Zeigt zusaetzlich bereits wiederhergestellte Eintraege.

    .EXAMPLE
    Get-ClamAVQuarantine | Format-Table QuarantineId, Signature, OriginalPath
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:AVConfigPath,
        [switch]$IncludeRestored
    )

    $config = Get-AVConfig -Path $ConfigPath
    $root = Expand-AVPath ([string]$config.QuarantinePath)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    foreach ($manifestFile in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($IncludeRestored -or $manifest.Status -ne 'Restored') {
                [PSCustomObject]@{
                    QuarantineId    = [string]$manifest.QuarantineId
                    Status          = [string]$manifest.Status
                    OriginalPath    = [string]$manifest.OriginalPath
                    QuarantinedPath = [string]$manifest.QuarantinedPath
                    ManifestPath    = $manifestFile.FullName
                    Signature       = [string]$manifest.Signature
                    Sha256          = [string]$manifest.Sha256
                    SizeBytes       = [int64]$manifest.SizeBytes
                    QuarantinedAt   = [string]$manifest.QuarantinedAt
                    RestoredAt      = [string]$manifest.RestoredAt
                    FilePresent     = Test-Path -LiteralPath ([string]$manifest.QuarantinedPath) -PathType Leaf
                }
            }
        }
        catch {
            Write-AVLog -Message "Ungueltiges Quarantaene-Manifest '$($manifestFile.FullName)': $($_.Exception.Message)" -Level 'Warning' -Event 'Quarantine'
        }
    }
}
