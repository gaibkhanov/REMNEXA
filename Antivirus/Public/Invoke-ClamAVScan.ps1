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

    $progress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskScan') -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
    $inventoryProgress = $null
    $targetListPath = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-targets-' + [guid]::NewGuid().ToString('N') + '.txt')
    $started = [DateTimeOffset]::Now
    $script:AVDiscoveryProgress = $progress
    $script:AVDiscoverySkipped = 0
    try {
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'ProgressTaskPrepare') -Force
        $config = Get-AVConfig -Path $ConfigPath
        $status = Get-ClamAVStatus -ConfigPath $ConfigPath
        if (-not $status.Installed) { throw "ClamAV nicht gefunden unter '$($status.ClamScanPath)'." }
        if (-not $status.Ready) { throw "Keine ClamAV-Signaturdatenbank unter '$($status.DatabasePath)' gefunden." }
        if ($status.SignaturesOutdated) {
            Add-RemnexaProgressNotice -Level Warning
            Write-Warning "Die ClamAV-Signaturen sind aelter als $($config.SignatureMaxAgeDays) Tage."
        }
        $effectiveMaxFileSize = if ($MaxFileSize) { $MaxFileSize } else { [string]$config.MaxFileSize }
        Test-AVMaxFileSize $effectiveMaxFileSize
        $effectiveTimeout = if ($Timeout -gt 0) { $Timeout } else { [int]$config.DefaultTimeoutSeconds }
        $effectivePUA = [bool]$IncludePUA -or [bool]$config.IncludePUA
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'ProgressTaskDiscovery') -Force
        $targets = @(Resolve-AVScanTargets -ScanType $ScanType -Path @($Path) -Config $config)
        if ($targets.Count -eq 0) { throw 'Keine vorhandenen, erlaubten Scan-Ziele gefunden.' }
        if (-not (Test-AVAdministrator)) {
            if (Test-AVSystemScanRequiresElevation -Path $targets) { throw 'Mindestens ein Systempfad soll gescannt werden. Bitte PowerShell als Administrator starten und den Scan erneut ausfuehren.' }
            Write-Warning 'Der Scan laeuft ohne Administratorrechte; geschuetzte Dateien koennen uebersprungen werden.'
        }

        $inventoryProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskDiscovery') -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
        $inventory = New-AVScanFileList -Targets $targets -Config $config -ListPath $targetListPath -Progress $inventoryProgress
        $inventory.Skipped += $script:AVDiscoverySkipped
        Complete-RemnexaProgress $inventoryProgress -Outcome $(if ($inventory.Skipped) { 'Warning' } else { 'Completed' })
        $inventoryProgress = $null
        Update-RemnexaProgress $progress -Total $inventory.Files -Status (Get-RemnexaProgressText 'ProgressTaskLoadEngine') -CurrentItem '' -Force

        $metrics = [PSCustomObject]@{ Reported=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); Errors=0; Unexpected=0 }
        $run = [PSCustomObject]@{ ExitCode=0; StandardOutput=''; StandardError='' }
        if ($inventory.Files -gt 0) {
            $arguments = [Collections.Generic.List[string]]::new()
            foreach ($argument in @('--verbose','--no-summary','--stdout','--follow-dir-symlinks=0','--follow-file-symlinks=0',('--database=' + $status.DatabasePath),('--max-filesize=' + $effectiveMaxFileSize),('--file-list=' + $targetListPath))) { $arguments.Add($argument) }
            if ($effectivePUA) { $arguments.Add('--detect-pua') }
            foreach ($excludeArgument in @(Get-AVExcludeArguments -Config $config)) { $arguments.Add($excludeArgument) }
            $updateProgressCommand = Get-Command Update-RemnexaProgress
            $progressTextCommand = Get-Command Get-RemnexaProgressText
            $onOutput = {
                param($Line, $Stream)
                if ($Line.StartsWith('Scanning ', [StringComparison]::Ordinal)) {
                    & $updateProgressCommand $progress -Status (& $progressTextCommand 'ProgressTaskScanFiles') -CurrentItem $Line.Substring(9)
                }
                elseif ($Line -match '^(?<File>.+):\s+(?<Result>OK|Empty file|.+\s+FOUND|.+\s+ERROR)\s*$') {
                    $file = [string]$Matches.File
                    $message = [string]$Matches.Result
                    if ($metrics.Reported.Add($file)) {
                        if ($message -match '\sERROR$') { $metrics.Errors++ }
                        if ($metrics.Reported.Count -gt $inventory.Files) { $metrics.Unexpected++ }
                        & $updateProgressCommand $progress -Completed ([Math]::Min($metrics.Reported.Count, $inventory.Files)) -CurrentItem $file -Status (& $progressTextCommand 'ProgressTaskScanFiles')
                    }
                }
            }.GetNewClosure()
            $heartbeat = { param($Event) & $updateProgressCommand $progress }.GetNewClosure()
            $filter = { param($Line, $Stream) return ($Stream -eq 'Stderr' -or $Line -match '\s(?:FOUND|ERROR)\s*$') }
            Write-AVLog -Message "ClamAV-$ScanType-Scan gestartet; Dateien: $($inventory.Files)." -Event 'Scan'
            $run = Invoke-AVNativeProcess -FilePath $status.ClamScanPath -ArgumentList $arguments.ToArray() -TimeoutSeconds $effectiveTimeout -WorkingDirectory (Split-Path -Parent $status.ClamScanPath) -OnOutput $onOutput -OnHeartbeat $heartbeat -CaptureFilter $filter
        }
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'ProgressTaskEvaluate') -CurrentItem '' -Force
        if ($run.ExitCode -notin @(0,1,2)) { throw "Unbekannter clamscan Exit-Code $($run.ExitCode)." }
        $results = @(Get-ClamAVScanResult -InputObject @($run.StandardOutput,$run.StandardError) -ExitCode $run.ExitCode -ScanType $ScanType)
        if ($run.ExitCode -eq 2) { throw ("ClamAV konnte den Scan nicht abschliessen (Exit-Code 2): " + $run.StandardError + ' ' + $run.StandardOutput) }
        if ($run.ExitCode -eq 1 -and @($results | Where-Object Status -eq 'Infected').Count -eq 0) { throw 'ClamAV meldete einen Fund, aber die Ausgabe konnte nicht sicher zugeordnet werden.' }
        if ($Quarantine) {
            $infected = @($results | Where-Object Status -eq 'Infected')
            $quarantineProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskQuarantine') -Total $infected.Count -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
            try {
                $done = 0
                foreach ($result in $infected) {
                    if (-not (Test-Path -LiteralPath $result.Path -PathType Leaf)) {
                        $result.Message += ' | Nicht als einzelne Datei in Quarantaene verschiebbar.'
                        Add-RemnexaProgressNotice -Level Warning
                    }
                    else {
                        $manifest = Move-ToClamAVQuarantine -Path $result.Path -Signature $result.Signature -QuarantinePath (Expand-AVPath ([string]$config.QuarantinePath))
                        $result.Quarantined=$true; $result.QuarantineId=$manifest.QuarantineId; $result.Status='Quarantined'
                    }
                    $done++
                    Update-RemnexaProgress $quarantineProgress -Completed $done -CurrentItem $result.Path
                }
                Complete-RemnexaProgress $quarantineProgress
            }
            catch { Complete-RemnexaProgress $quarantineProgress -Outcome Failed; throw }
        }
        $unconfirmed = [Math]::Max(0, $inventory.Files - $metrics.Reported.Count)
        $findings = @($results | Where-Object Severity -in @('Malware','PotentiallyUnwanted')).Count
        $partial = $unconfirmed -gt 0 -or $inventory.Skipped -gt 0 -or $metrics.Errors -gt 0 -or $metrics.Unexpected -gt 0 -or $inventory.Files -eq 0
        $coverage = (Get-RemnexaProgressText 'ProgressScanCoverage') -f $metrics.Reported.Count,$metrics.Errors,$unconfirmed,$inventory.Skipped
        if ($results.Count -eq 0) {
            $results = @([PSCustomObject]@{ Path=($targets -join '; '); Signature=$null; Severity=$(if($partial){'Warning'}else{'None'}); Status=$(if($partial){'Partial'}else{'Clean'}); ExitCode=0; ScanType=$ScanType; Quarantined=$false; QuarantineId=$null; Message=$coverage })
        }
        foreach ($result in $results) {
            foreach ($entry in @{ StartedAt=$started; CompletedAt=[DateTimeOffset]::Now; DurationSeconds=[Math]::Round(([DateTimeOffset]::Now-$started).TotalSeconds,2); FilesTotal=$inventory.Files; FilesReported=$metrics.Reported.Count; FilesUnconfirmed=$unconfirmed; InventorySkipped=$inventory.Skipped; CoverageComplete=(-not $partial) }.GetEnumerator()) { $result | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value -Force }
        }
        Update-RemnexaProgress $progress -Completed ([Math]::Min($metrics.Reported.Count, $inventory.Files)) -Status $coverage -CurrentItem '' -Force
        Complete-RemnexaProgress $progress -Outcome $(if($partial -or $findings){'Warning'}else{'Completed'})
        Write-AVLog -Message "ClamAV-$ScanType-Scan beendet; Funde: $findings. $coverage" -Level $(if($partial -or $findings){'Warning'}else{'Success'}) -Event 'Scan' -Data $results
        return $results
    }
    catch {
        if ($inventoryProgress -and $inventoryProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $inventoryProgress -Outcome Failed }
        if ($progress.Outcome -eq 'Running') { Complete-RemnexaProgress $progress -Outcome Failed -Status $_.Exception.Message }
        Write-AVLog -Message $_.Exception.Message -Level Error -Event Scan
        throw
    }
    finally {
        $script:AVDiscoveryProgress = $null
        if (Test-Path -LiteralPath $targetListPath) { Remove-Item -LiteralPath $targetListPath -Force -ErrorAction SilentlyContinue }
    }
}
