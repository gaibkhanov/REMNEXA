function Update-ClamAVSignature {
    <#
    .SYNOPSIS
    Aktualisiert die ClamAV-Signaturdatenbanken mit freshclam.exe.

    .DESCRIPTION
    Erstellt bei Bedarf eine minimale freshclam.conf, ruft FreshClam mit einem
    Argument-Array auf und warnt, wenn die juengste Signatur aelter als sieben
    Tage beziehungsweise als SignatureMaxAgeDays ist.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .PARAMETER Timeout
    Maximale Laufzeit von FreshClam in Sekunden.

    .EXAMPLE
    Update-ClamAVSignature

    .EXAMPLE
    Update-ClamAVSignature -Timeout 900
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:AVConfigPath,
        [ValidateRange(30, 86400)][int]$Timeout = 1800
    )

    $config = Get-AVConfig -Path $ConfigPath
    $root = Find-ClamAVInstallation -Config $config
    if (-not $root) {
        throw "ClamAV nicht gefunden unter '$([Environment]::ExpandEnvironmentVariables([string]$config.ClamAVPath))'. Bitte Initialize-ClamAV ausfuehren oder ClamAVPath in antivirus.json setzen."
    }
    $freshClam = Join-Path $root 'freshclam.exe'
    if (-not (Test-Path -LiteralPath $freshClam -PathType Leaf)) { throw "freshclam.exe nicht gefunden unter '$freshClam'." }
    $databasePath = Expand-AVPath ([string]$config.DatabasePath)
    New-Item -ItemType Directory -Path $databasePath -Force -ErrorAction Stop | Out-Null
    $configFile = Join-Path $root 'freshclam.conf'
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        $configFile = New-FreshClamConfiguration -ClamAVPath $root -DatabasePath $databasePath
    }

    Write-AVLog -Message 'ClamAV-Signaturaktualisierung gestartet.' -Event 'SignatureUpdate'
    Write-Progress -Activity 'ClamAV-Signaturen' -Status 'Signaturen werden aktualisiert' -PercentComplete 20
    try {
        $run = Invoke-AVNativeProcess -FilePath $freshClam -ArgumentList @(
            ('--config-file=' + $configFile),
            ('--datadir=' + $databasePath),
            '--stdout'
        ) -TimeoutSeconds $Timeout -WorkingDirectory $root
        if ($run.ExitCode -ne 0) {
            $detail = ($run.StandardError + "`n" + $run.StandardOutput).Trim()
            throw "FreshClam meldete Exit-Code $($run.ExitCode): $detail"
        }
        Write-Progress -Activity 'ClamAV-Signaturen' -Status 'Status wird geprueft' -PercentComplete 90
        $status = Get-ClamAVStatus -ConfigPath $ConfigPath
        if ($status.SignaturesOutdated) {
            Write-Warning "Die ClamAV-Signaturen fehlen oder sind aelter als $($config.SignatureMaxAgeDays) Tage."
            Write-AVLog -Message 'Signaturen fehlen oder sind veraltet.' -Level 'Warning' -Event 'SignatureUpdate' -Data $status
        }
        else {
            Write-AVLog -Message "ClamAV-Signaturen aktualisiert; Stand: $($status.SignatureDate)." -Level 'Success' -Event 'SignatureUpdate' -Data $status
        }
        return $status
    }
    catch {
        Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'SignatureUpdate'
        throw
    }
    finally {
        Write-Progress -Activity 'ClamAV-Signaturen' -Completed
    }
}
