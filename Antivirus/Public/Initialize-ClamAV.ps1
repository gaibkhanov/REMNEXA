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

    .PARAMETER ExpectedSha256
    Erwarteter SHA-256-Pruefwert fuer eine direkte ZIP-Adresse, bei der keine
    Release-Metadaten mit Digest vorliegen.

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
        [string]$ExpectedSha256,
        [switch]$Force,
        [switch]$SkipSignatureUpdate,
        [string]$ConfigPath = $script:AVConfigPath
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskInstall')
    try {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'ExpectedSha256 muss aus genau 64 hexadezimalen Zeichen bestehen.'
        }

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
                Complete-RemnexaProgress $remnexaWorkProgress -Outcome Cancelled
                Write-AVLog -Message 'ClamAV-Einrichtung vom Benutzer abgebrochen.' -Level 'Warning' -Event 'Initialize'
                return Get-ClamAVStatus -ConfigPath $ConfigPath
            }
        }
        if (-not $PSCmdlet.ShouldProcess($target, 'Offizielle portable ClamAV-Version herunterladen und installieren')) {
            Complete-RemnexaProgress $remnexaWorkProgress -Outcome Cancelled
            return Get-ClamAVStatus -ConfigPath $ConfigPath
        }

        $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-' + [guid]::NewGuid().ToString('N'))
        $archivePath = Join-Path $temporaryRoot 'clamav.zip'
        $extractPath = Join-Path $temporaryRoot 'extract'
        try {
            New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop | Out-Null
            $asset = Resolve-ClamAVReleaseAsset -DownloadUri $(if ($DownloadUri) { $DownloadUri } else { [string]$config.DownloadUri })
            $asset = Assert-ClamAVReleaseAsset -Asset $asset -ExpectedSha256 $ExpectedSha256
            $downloadUri = [uri]$asset.Uri
            Write-AVLog -Message "ClamAV-Download gestartet: $($asset.Uri)" -Event 'Initialize'
            Update-RemnexaProgress $remnexaWorkProgress -Status (Get-RemnexaProgressText 'ProgressTaskDownload') -Force
            Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath -UseBasicParsing -ErrorAction Stop

            [void](Assert-ClamAVArchiveDigest -Digest ([string]$asset.Digest) -ArchivePath $archivePath)
            Update-RemnexaProgress $remnexaWorkProgress -Status (Get-RemnexaProgressText 'ProgressTaskExtract') -Force
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force -ErrorAction Stop
            $clamScan = Get-ChildItem -LiteralPath $extractPath -Filter 'clamscan.exe' -File -Recurse -ErrorAction Stop | Select-Object -First 1
            if ($null -eq $clamScan) { throw 'Das heruntergeladene Paket enthaelt keine clamscan.exe.' }
            $sourceRoot = Split-Path -Parent $clamScan.FullName
            $databasePath = if ($InstallPath) { Join-Path $target 'database' } else { Expand-AVPath ([string]$config.DatabasePath) }
            $commitConfiguration = {
                param($installedTarget, $installedDatabase)
                $storedClamAVPath = ConvertTo-AVPortableConfigPath -Path $installedTarget
                $storedDatabasePath = ConvertTo-AVPortableConfigPath -Path $installedDatabase
                Set-AVConfig -Path $ConfigPath -Values @{ ClamAVPath = $storedClamAVPath; DatabasePath = $storedDatabasePath } -Confirm:$false
            }
            $installResult = Install-ClamAVPayload -SourceRoot $sourceRoot -TargetPath $target -DatabasePath $databasePath -CommitAction $commitConfiguration -Force:$Force
            $target = $installResult.Path
            $databasePath = $installResult.DatabasePath
            Update-RemnexaProgress $remnexaWorkProgress -Status (Get-RemnexaProgressText 'ProgressTaskInstall') -Force
            Write-AVLog -Message "ClamAV wurde unter '$target' eingerichtet." -Level 'Success' -Event 'Initialize'

            if (-not $SkipSignatureUpdate) {
                [void](Update-ClamAVSignature -ConfigPath $ConfigPath)
            }
            Update-RemnexaProgress $remnexaWorkProgress -Status (Get-RemnexaProgressText 'ProgressTaskFinalize') -Force
            return Get-ClamAVStatus -ConfigPath $ConfigPath
        }
        catch {
            Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'Initialize'
            throw
        }
        finally {

            if (Test-Path -LiteralPath $temporaryRoot) {
                Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}
