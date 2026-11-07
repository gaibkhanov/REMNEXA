function Restore-FromClamAVQuarantine {
    <#
    .SYNOPSIS
    Stellt eine Datei aus der verwalteten ClamAV-Quarantaene wieder her.

    .DESCRIPTION
    Prueft Manifest und SHA-256-Hash, zeigt eine ausdrueckliche Sicherheitsabfrage
    und verschiebt die Datei an ihren Originalpfad. Eine vorhandene Datei am
    Originalpfad wird niemals ueberschrieben.

    .PARAMETER Identifier
    QuarantineId, Pfad zur Quarantaene-Datei oder Pfad zum JSON-Manifest.

    .PARAMETER Force
    Ueberspringt nur die interaktive Sicherheitsabfrage. Vorhandene Zieldateien
    werden auch mit Force nicht ueberschrieben.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .EXAMPLE
    Restore-FromClamAVQuarantine -Identifier '20261106-120000000-a1b2c3d4e5f6a7b8'

    .EXAMPLE
    Get-ClamAVQuarantine | Select-Object -First 1 | ForEach-Object { Restore-FromClamAVQuarantine $_.QuarantineId }
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNullOrEmpty()][string]$Identifier,
        [switch]$Force,
        [string]$ConfigPath = $script:AVConfigPath
    )
    process {
        $config = Get-AVConfig -Path $ConfigPath
        $root = Expand-AVPath ([string]$config.QuarantinePath)
        $manifestPath = Resolve-AVQuarantineManifest -Identifier $Identifier -QuarantinePath $root
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $source = [string]$manifest.QuarantinedPath
        $destination = [string]$manifest.OriginalPath
        if ($manifest.Status -eq 'Restored') { throw "Eintrag '$($manifest.QuarantineId)' wurde bereits wiederhergestellt." }
        if (-not (Test-AVPathIsWithin -Path $source -Parent $root)) { throw "Quarantaene-Dateipfad liegt ausserhalb des konfigurierten Ordners: '$source'." }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Quarantaene-Datei fehlt: '$source'." }
        if (Test-Path -LiteralPath $destination) { throw "Originalpfad '$destination' ist bereits belegt. Es wird nichts ueberschrieben." }
        $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$manifest.Sha256).ToLowerInvariant()) { throw 'SHA-256-Pruefung der Quarantaene-Datei ist fehlgeschlagen. Wiederherstellung wurde abgebrochen.' }

        if (-not $Force) {
            $question = "Die Datei wurde als '$($manifest.Signature)' erkannt. Trotzdem nach '$destination' wiederherstellen?"
            if (-not $PSCmdlet.ShouldContinue($question, 'Sicherheitswarnung: Quarantaene wiederherstellen')) { return }
        }
        if (-not $PSCmdlet.ShouldProcess($destination, "Quarantaene-Eintrag '$($manifest.QuarantineId)' wiederherstellen")) { return }

        try {
            $parent = Split-Path -Parent $destination
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
            Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
            $manifest.Status = 'Restored'
            $manifest.RestoredAt = [DateTimeOffset]::Now.ToString('o')
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
            Write-AVLog -Message "Quarantaene-Eintrag '$($manifest.QuarantineId)' nach '$destination' wiederhergestellt." -Level 'Warning' -Event 'QuarantineRestore' -Data $manifest
            return [PSCustomObject]@{
                QuarantineId = [string]$manifest.QuarantineId
                Status       = 'Restored'
                RestoredPath = $destination
                Signature    = [string]$manifest.Signature
                RestoredAt   = [string]$manifest.RestoredAt
            }
        }
        catch {
            Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'QuarantineRestore'
            throw
        }
    }
}
