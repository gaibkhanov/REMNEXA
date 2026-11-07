function Initialize-ClamAV {
    <#
    .SYNOPSIS
    Erkennt oder installiert die portable Windows-Version von ClamAV.

    .DESCRIPTION
    Sucht zuerst im konfigurierten Pfad, im PATH und in gaengigen Windows-Pfaden.
    Fehlt ClamAV, kann nach einer Bestaetigung das aktuelle offizielle portable
    Paket von Cisco-Talos geladen, geprueft, entpackt und eingerichtet werden.

    .PARAMETER Install
    Fuehrt die Installation ohne die zusaetzliche gefuehrte Rueckfrage aus.

    .PARAMETER InstallPath
    Zielpfad. Standard ist ClamAVPath aus config/antivirus.json.

    .PARAMETER DownloadUri
    Direkte offizielle ZIP-Adresse. Ohne ZIP-Adresse wird das neueste offizielle
    GitHub-Release automatisch ermittelt.

    .PARAMETER Force
    Erlaubt das Ersetzen eines unvollstaendigen Zielordners.

    .PARAMETER SkipSignatureUpdate
    Ueberspringt den ersten Aufruf von FreshClam.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .EXAMPLE
    Initialize-ClamAV

    .EXAMPLE
    Initialize-ClamAV -Install -InstallPath 'D:\Tools\ClamAV'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$Install,
        [string]$InstallPath,
        [string]$DownloadUri,
        [switch]$Force,
        [switch]$SkipSignatureUpdate,
        [string]$ConfigPath = $script:AVConfigPath
    )

    $config = Get-AVConfig -Path $ConfigPath
    $existing = Find-ClamAVInstallation -Config $config
    if ($existing) {
        if ((Expand-AVPath ([string]$config.ClamAVPath)) -ne $existing) {
            Set-AVConfig -Path $ConfigPath -Values @{ ClamAVPath = $existing } -Confirm:$false
        }
        Write-AVLog -Message "Vorhandene ClamAV-Installation erkannt: $existing" -Level 'Success' -Event 'Initialize'
        return Get-ClamAVStatus -ConfigPath $ConfigPath
    }

    $target = if ($InstallPath) { Expand-AVPath $InstallPath } else { Expand-AVPath ([string]$config.ClamAVPath) }
    if (-not $Install) {
        $caption = 'ClamAV fehlt'
        $question = "ClamAV wurde nicht gefunden. Soll die offizielle portable Windows-Version nach '$target' geladen und eingerichtet werden?"
        if (-not $PSCmdlet.ShouldContinue($question, $caption)) {
            Write-AVLog -Message 'ClamAV-Einrichtung vom Benutzer abgebrochen.' -Level 'Warning' -Event 'Initialize'
            return Get-ClamAVStatus -ConfigPath $ConfigPath
        }
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Offizielle portable ClamAV-Version herunterladen und installieren')) {
        return Get-ClamAVStatus -ConfigPath $ConfigPath
    }

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-' + [guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $temporaryRoot 'clamav.zip'
    $extractPath = Join-Path $temporaryRoot 'extract'
    try {
        New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop | Out-Null
        $asset = Resolve-ClamAVReleaseAsset -DownloadUri $(if ($DownloadUri) { $DownloadUri } else { [string]$config.DownloadUri })
        Write-AVLog -Message "ClamAV-Download gestartet: $($asset.Uri)" -Event 'Initialize'
        Write-Progress -Activity 'ClamAV-Einrichtung' -Status 'Offizielles Paket wird heruntergeladen' -PercentComplete 15
        Invoke-WebRequest -Uri $asset.Uri -OutFile $archivePath -UseBasicParsing -ErrorAction Stop

        if ($asset.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actualHash -ne $Matches[1]) { throw 'Die SHA-256-Pruefung des ClamAV-Pakets ist fehlgeschlagen. Installation wurde abgebrochen.' }
        }
        Write-Progress -Activity 'ClamAV-Einrichtung' -Status 'Paket wird entpackt' -PercentComplete 45
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force -ErrorAction Stop
        $clamScan = Get-ChildItem -LiteralPath $extractPath -Filter 'clamscan.exe' -File -Recurse -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $clamScan) { throw 'Das heruntergeladene Paket enthaelt keine clamscan.exe.' }
        $sourceRoot = Split-Path -Parent $clamScan.FullName

        if (Test-Path -LiteralPath $target) {
            if (-not $Force) { throw "Zielordner '$target' existiert bereits. Fuer bewusstes Ersetzen -Force angeben." }
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        }
        New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $target -Recurse -Force -ErrorAction Stop
        $databasePath = if ($InstallPath) { Join-Path $target 'database' } else { Expand-AVPath ([string]$config.DatabasePath) }
        New-Item -ItemType Directory -Path $databasePath -Force -ErrorAction Stop | Out-Null
        [void](New-FreshClamConfiguration -ClamAVPath $target -DatabasePath $databasePath)
        $storedClamAVPath = ConvertTo-AVPortableConfigPath -Path $target
        $storedDatabasePath = ConvertTo-AVPortableConfigPath -Path $databasePath
        Set-AVConfig -Path $ConfigPath -Values @{ ClamAVPath = $storedClamAVPath; DatabasePath = $storedDatabasePath } -Confirm:$false
        Write-Progress -Activity 'ClamAV-Einrichtung' -Status 'Installation wurde eingerichtet' -PercentComplete 75
        Write-AVLog -Message "ClamAV wurde unter '$target' eingerichtet." -Level 'Success' -Event 'Initialize'

        if (-not $SkipSignatureUpdate) {
            [void](Update-ClamAVSignature -ConfigPath $ConfigPath)
        }
        Write-Progress -Activity 'ClamAV-Einrichtung' -Status 'Fertig' -PercentComplete 100
        return Get-ClamAVStatus -ConfigPath $ConfigPath
    }
    catch {
        Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'Initialize'
        throw
    }
    finally {
        Write-Progress -Activity 'ClamAV-Einrichtung' -Completed
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
