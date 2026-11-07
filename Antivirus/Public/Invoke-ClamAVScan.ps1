function Invoke-ClamAVScan {
    <#
    .SYNOPSIS
    Fuehrt einen lokalen ClamAV-On-Demand-Scan aus.

    .DESCRIPTION
    Quick scannt typische Infektionsorte, Full definierte Windows-Systempfade und
    Custom ausschliesslich die angegebenen Pfade. Exit-Code 0 bedeutet sauber,
    1 bedeutet Fund und 2 bedeutet Scanfehler. Nur -Quarantine verschiebt Funde;
    Dateien werden nie automatisch geloescht.

    .PARAMETER Path
    Datei, Ordner oder Pfadarray. Bei Custom ist mindestens ein Pfad Pflicht.
    Bei Quick und Full werden angegebene Pfade zu den Standardzielen hinzugefuegt.

    .PARAMETER ScanType
    Quick, Full oder Custom.

    .PARAMETER Quarantine
    Verschiebt gefundene Dateien nach ausdruecklicher Angabe dieses Schalters in
    die konfigurierte Quarantaene und legt je Fund ein JSON-Manifest an.

    .PARAMETER IncludePUA
    Aktiviert ClamAVs Erkennung potenziell unerwuenschter Anwendungen.

    .PARAMETER MaxFileSize
    Maximale Dateigroesse, zum Beispiel 100M.

    .PARAMETER Timeout
    Maximale Laufzeit von clamscan.exe in Sekunden.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .EXAMPLE
    Invoke-ClamAVScan -ScanType Quick

    .EXAMPLE
    Invoke-ClamAVScan -Path 'C:\Downloads' -ScanType Custom -IncludePUA -Timeout 1800

    .EXAMPLE
    Invoke-ClamAVScan -Path 'C:\Temp\suspect.exe' -ScanType Custom -Quarantine
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$Path = @(),
        [ValidateSet('Quick', 'Full', 'Custom')][string]$ScanType = 'Custom',
        [switch]$Quarantine,
        [switch]$IncludePUA,
        [string]$MaxFileSize,
        [ValidateRange(1, 86400)][int]$Timeout = 0,
        [string]$ConfigPath = $script:AVConfigPath
    )

    $config = Get-AVConfig -Path $ConfigPath
    $status = Get-ClamAVStatus -ConfigPath $ConfigPath
    if (-not $status.Installed) {
        throw "ClamAV nicht gefunden unter '$($status.ClamScanPath)'. Bitte Initialize-ClamAV ausfuehren oder Pfad in antivirus.json setzen."
    }
    if (-not $status.Ready) {
        throw "Keine ClamAV-Signaturdatenbank unter '$($status.DatabasePath)' gefunden. Bitte Update-ClamAVSignature ausfuehren."
    }
    if ($status.SignaturesOutdated) {
        Write-Warning "Die ClamAV-Signaturen sind aelter als $($config.SignatureMaxAgeDays) Tage."
        Write-AVLog -Message 'Scan mit fehlenden oder veralteten Signaturen gestartet.' -Level 'Warning' -Event 'Scan'
    }

    $effectiveMaxFileSize = if ($MaxFileSize) { $MaxFileSize } else { [string]$config.MaxFileSize }
    Test-AVMaxFileSize $effectiveMaxFileSize
    $effectiveTimeout = if ($Timeout -gt 0) { $Timeout } else { [int]$config.DefaultTimeoutSeconds }
    $effectivePUA = [bool]$IncludePUA -or [bool]$config.IncludePUA
    $targets = @(Resolve-AVScanTargets -ScanType $ScanType -Path @($Path) -Config $config)
    if ($targets.Count -eq 0) { throw 'Keine vorhandenen, erlaubten Scan-Ziele gefunden.' }

    if (-not (Test-AVAdministrator)) {
        if (Test-AVSystemScanRequiresElevation -Path $targets) {
            throw 'Mindestens ein Systempfad soll gescannt werden. Bitte PowerShell als Administrator starten und den Scan erneut ausfuehren.'
        }
        Write-Warning 'Der Scan laeuft ohne Administratorrechte; einzelne geschuetzte Dateien koennen uebersprungen werden.'
    }

    $targetListPath = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-targets-' + [guid]::NewGuid().ToString('N') + '.txt')
    $started = [DateTimeOffset]::Now
    try {
        $targets | Set-Content -LiteralPath $targetListPath -Encoding UTF8 -ErrorAction Stop
        $arguments = New-Object 'System.Collections.Generic.List[string]'
        foreach ($argument in @(
            '--infected',
            '--no-summary',
            '--stdout',
            '--recursive',
            ('--database=' + $status.DatabasePath),
            ('--max-filesize=' + $effectiveMaxFileSize),
            ('--file-list=' + $targetListPath)
        )) { $arguments.Add($argument) }
        if ($effectivePUA) { $arguments.Add('--detect-pua') }
        foreach ($excludeArgument in @(Get-AVExcludeArguments -Config $config)) { $arguments.Add($excludeArgument) }

        Write-AVLog -Message "ClamAV-$ScanType-Scan gestartet; Ziele: $($targets.Count)." -Event 'Scan' -Data $targets
        Write-Progress -Activity 'ClamAV-Scan' -Status "Ziele vorbereitet: $($targets.Count)" -PercentComplete 10
        $run = Invoke-AVNativeProcess -FilePath $status.ClamScanPath -ArgumentList $arguments.ToArray() -TimeoutSeconds $effectiveTimeout -WorkingDirectory (Split-Path -Parent $status.ClamScanPath)
        Write-Progress -Activity 'ClamAV-Scan' -Status 'Ergebnisse werden ausgewertet' -PercentComplete 90

        if ($run.ExitCode -notin @(0, 1, 2)) { throw "Unbekannter clamscan Exit-Code $($run.ExitCode)." }
        $results = @(Get-ClamAVScanResult -InputObject @($run.StandardOutput, $run.StandardError) -ExitCode ([Math]::Min(2, $run.ExitCode)) -ScanType $ScanType)
        if ($run.ExitCode -eq 2) {
            $detail = ($run.StandardError + "`n" + $run.StandardOutput).Trim()
            Write-AVLog -Message "ClamAV-Scanfehler: $detail" -Level 'Error' -Event 'Scan' -Data $results
            throw "ClamAV konnte den Scan nicht abschliessen (Exit-Code 2): $detail"
        }
        if ($run.ExitCode -eq 1 -and @($results | Where-Object { $_.Status -eq 'Infected' }).Count -eq 0) {
            $detail = ($run.StandardError + "`n" + $run.StandardOutput).Trim()
            throw "ClamAV meldete einen Fund (Exit-Code 1), aber die Ausgabe konnte nicht sicher zugeordnet werden: $detail"
        }

        if ($Quarantine -and $results.Count -gt 0) {
            $quarantinePath = Expand-AVPath ([string]$config.QuarantinePath)
            foreach ($result in @($results | Where-Object { $_.Status -eq 'Infected' })) {
                if (-not (Test-Path -LiteralPath $result.Path -PathType Leaf)) {
                    $result.Message = $result.Message + ' | Nicht als einzelne Datei in Quarantaene verschiebbar.'
                    continue
                }
                $manifest = Move-ToClamAVQuarantine -Path $result.Path -Signature $result.Signature -QuarantinePath $quarantinePath
                $result.Quarantined = $true
                $result.QuarantineId = $manifest.QuarantineId
                $result.Status = 'Quarantined'
            }
        }

        $completed = [DateTimeOffset]::Now
        if ($results.Count -eq 0) {
            $results = @([PSCustomObject]@{
                Path          = ($targets -join '; ')
                Signature     = $null
                Severity      = 'None'
                Status        = 'Clean'
                ExitCode      = 0
                ScanType      = $ScanType
                Quarantined   = $false
                QuarantineId  = $null
                Message       = "Keine Funde in $($targets.Count) Scan-Ziel(en)."
            })
        }
        foreach ($result in $results) {
            $result | Add-Member -NotePropertyName StartedAt -NotePropertyValue $started -Force
            $result | Add-Member -NotePropertyName CompletedAt -NotePropertyValue $completed -Force
            $result | Add-Member -NotePropertyName DurationSeconds -NotePropertyValue ([math]::Round(($completed - $started).TotalSeconds, 2)) -Force
        }
        $findings = @($results | Where-Object { $_.Severity -in @('Malware', 'PotentiallyUnwanted') }).Count
        Write-AVLog -Message "ClamAV-$ScanType-Scan abgeschlossen; Funde: $findings." -Level $(if ($findings -gt 0) { 'Warning' } else { 'Success' }) -Event 'Scan' -Data $results
        return $results
    }
    catch {
        Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'Scan'
        throw
    }
    finally {
        Write-Progress -Activity 'ClamAV-Scan' -Completed
        if (Test-Path -LiteralPath $targetListPath) { Remove-Item -LiteralPath $targetListPath -Force -ErrorAction SilentlyContinue }
    }
}
