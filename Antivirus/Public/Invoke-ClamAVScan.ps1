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
        [string]$ConfigPath = $script:AVConfigPath,
        [ValidateSet('Eco','Balanced','Fast')][string]$PerformanceMode,
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [object]$BackgroundControl=$null
    )

    $progress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskScan') -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
    $inventoryProgress = $null
    $targetListPath = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-targets-' + [guid]::NewGuid().ToString('N') + '.txt')
    $started = [DateTimeOffset]::Now
    $scanLease=$null;$cancellation=$null;$acknowledgements=$null;$results=$null
    $scanWatch=[Diagnostics.Stopwatch]::StartNew()
    $phaseTimes=[ordered]@{StatusSeconds=0;DiscoverySeconds=0;InventorySeconds=0;ScannerSeconds=0;FirstFileSeconds=$null;ResultSeconds=0}
    $inventory=[pscustomobject]@{Files=0;Skipped=0}
    $metrics=[pscustomobject]@{Reported=[long]0;Errors=0;Unexpected=0;Findings=0;NextFile=$null;LastFile=$null;Evidence=[Text.StringBuilder]::new()}
    $script:AVDiscoveryProgress = $progress
    $script:AVDiscoverySkipped = 0
    try {
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'ProgressTaskPrepare') -Force
        $config = Get-AVConfig -Path $ConfigPath
        Initialize-AVScanSupport
        $cancellation=[Remnexa.Scan.Cancellation]::new($CancellationToken,($null -eq $BackgroundControl))
        $script:AVCancellation=$cancellation
        $cancellation.Poll()
        $scanLease=Enter-AVScanLease $config
        $mode=if($PerformanceMode){$PerformanceMode}elseif($config.PSObject.Properties['ScanPerformanceMode']){[string]$config.ScanPerformanceMode}else{'Balanced'}
        $profile=Get-ClamAVScanPerformance -Mode $mode
        if($BackgroundControl){$BackgroundControl.Update('Preparing',0,-1,$mode);$BackgroundControl.Checkpoint(0)}
        if(-not $profile.CanStart -and -not(Test-AVWarmWorkerMemory $profile)){throw (Get-RemnexaProgressText 'AVScanMemoryLow')}
        $phase=[Diagnostics.Stopwatch]::StartNew()
        $status = Get-ClamAVStatus -ConfigPath $ConfigPath -ForScan
        $phaseTimes.StatusSeconds=$phase.Elapsed.TotalSeconds
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
        $phase.Restart()
        $targets = @(Resolve-AVScanTargets -ScanType $ScanType -Path @($Path) -Config $config)
        $cancellation.Poll()
        $phaseTimes.DiscoverySeconds=$phase.Elapsed.TotalSeconds
        if ($targets.Count -eq 0) { throw 'Keine vorhandenen, erlaubten Scan-Ziele gefunden.' }
        if (-not (Test-AVAdministrator)) {
            if (Test-AVSystemScanRequiresElevation -Path $targets) { throw 'Mindestens ein Systempfad soll gescannt werden. Bitte PowerShell als Administrator starten und den Scan erneut ausfuehren.' }
            Write-Warning 'Der Scan laeuft ohne Administratorrechte; geschuetzte Dateien koennen uebersprungen werden.'
        }

        $inventoryProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskDiscovery') -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
        $phase.Restart()
        $inventory = New-AVScanFileList -Targets $targets -Config $config -ListPath $targetListPath -Progress $inventoryProgress -CancellationToken $cancellation.Source.Token -CancellationControl $cancellation -BackgroundControl $BackgroundControl
        $phaseTimes.InventorySeconds=$phase.Elapsed.TotalSeconds
        $cancellation.Poll()
        if($inventory.PSObject.Properties['Issues']) { foreach($issue in $inventory.Issues) { Write-AVLog -Message $issue -Level Warning -Event 'Scan/Inventory' } }
        $inventory.Skipped += $script:AVDiscoverySkipped
        Complete-RemnexaProgress $inventoryProgress -Outcome $(if ($inventory.Skipped) { 'Warning' } else { 'Completed' })
        $inventoryProgress = $null
        Update-RemnexaProgress $progress -Total $inventory.Files -Status (Get-RemnexaProgressText 'ProgressTaskLoadEngine') -CurrentItem '' -Force
        if($BackgroundControl){$BackgroundControl.Update('Loading',0,$inventory.Files,$mode)}

        $run = [PSCustomObject]@{ ExitCode=0; StandardOutput=''; StandardError='' }
        if ($inventory.Files -gt 0) {
            $arguments = [Collections.Generic.List[string]]::new()
            foreach ($argument in @('--no-summary','--stdout','--follow-dir-symlinks=0','--follow-file-symlinks=0','--alert-exceeds-max=yes',('--database=' + $status.DatabasePath),('--max-filesize=' + $effectiveMaxFileSize),('--file-list=' + $targetListPath))) { $arguments.Add($argument) }
            if ($effectivePUA) { $arguments.Add('--detect-pua') }
            foreach ($excludeArgument in @(Get-AVExcludeArguments -Config $config)) { $arguments.Add($excludeArgument) }
            $updateProgressCommand = Get-Command Update-RemnexaProgress
            $progressTextCommand = Get-Command Get-RemnexaProgressText
            $acknowledgements=[IO.StreamReader]::new($targetListPath,[Text.Encoding]::UTF8)
            $metrics.NextFile=$acknowledgements.ReadLine()
            $scannerWatch=[Diagnostics.Stopwatch]::StartNew()
            $cancellationCommand=$cancellation
            $liveText=Get-RemnexaProgressText 'AVScanLive'
            $heartbeat = {
                param($Event)
                $cancellationCommand.Poll()
                if($BackgroundControl){$BackgroundControl.ObserveScanner([int]$Event.ProcessId);$BackgroundControl.Checkpoint([int]$Event.ProcessId)}
                $rate=if($null -ne $phaseTimes.FirstFileSeconds -and $scannerWatch.Elapsed.TotalSeconds -gt $phaseTimes.FirstFileSeconds){$metrics.Reported/($scannerWatch.Elapsed.TotalSeconds-$phaseTimes.FirstFileSeconds)}else{0}
                & $updateProgressCommand $progress -Status ($liveText -f $profile.Mode,$metrics.Findings,([Math]::Round($rate,1)))
            }.GetNewClosure()
            $onOutput = {
                param($Line, $Stream)
                if ($Line -match '^(?<File>.+):\s+(?<Result>OK|Empty file|.+\s+FOUND|.+\s+ERROR)\s*$') {
                    $file = [string]$Matches.File
                    $message = [string]$Matches.Result
                    if($null -eq $phaseTimes.FirstFileSeconds){$phaseTimes.FirstFileSeconds=$scannerWatch.Elapsed.TotalSeconds}
                    # clamscan consumes --file-list sequentially. Track its cursor
                    # on disk instead of retaining every acknowledged path in RAM.
                    if($file -eq $metrics.LastFile){return}
                    while($null -ne $metrics.NextFile -and -not $file.Equals($metrics.NextFile,[StringComparison]::OrdinalIgnoreCase)){$metrics.NextFile=$acknowledgements.ReadLine()}
                    if($null -ne $metrics.NextFile) {
                        $metrics.Reported++;$metrics.LastFile=$file;$metrics.NextFile=$acknowledgements.ReadLine()
                        if ($message -match '\sERROR$') { $metrics.Errors++ }
                        if ($message -match '\sFOUND$' -and $message -notlike 'Heuristics.Limits.Exceeded*') { $metrics.Findings++ }
                        if($BackgroundControl){
                            $BackgroundControl.Update('Scanning',$metrics.Reported,$inventory.Files,$profile.Mode)
                            if($message -match '\s(?:FOUND|ERROR)$'){$BackgroundControl.AddEvidence($Line,($message -match '\sFOUND$' -and $message -notlike 'Heuristics.Limits.Exceeded*'))}
                        }
                        & $updateProgressCommand $progress -Completed $metrics.Reported -CurrentItem $file
                    }
                    else{$metrics.Unexpected++}
                    if($message -match '\s(?:FOUND|ERROR)$'){[void]$metrics.Evidence.AppendLine($Line)}
                }
            }.GetNewClosure()
            $filter = { param($Line, $Stream) return ($Stream -eq 'Stderr' -or $Line -match '\s(?:FOUND|ERROR)\s*$') }
            Write-AVLog -Message "ClamAV-$ScanType-Scan gestartet; Dateien: $($inventory.Files)." -Event 'Scan'
            $backend=if($config.PSObject.Properties['ScanBackend']){[string]$config.ScanBackend}else{'ClamScan'}
            $privateDll=Join-Path (Split-Path -Parent $status.ClamScanPath) 'libclamav.dll'
            $usePrivate=$backend -eq 'PrivateWorker' -or ($backend -eq 'Auto' -and (Test-Path -LiteralPath $privateDll -PathType Leaf))
            $run=$null
            if($usePrivate) {
                try {
                    $run=Invoke-AVPrivateScan -Config $config -Status $status -Profile $profile -FileList $targetListPath -MaxFileSize $effectiveMaxFileSize -IncludePUA $effectivePUA -TimeoutSeconds $effectiveTimeout -OnOutput $onOutput -OnHeartbeat $heartbeat -CaptureFilter $filter -CancellationToken $cancellation.Source.Token -PauseControl $BackgroundControl
                }catch{
                    if($backend -ne 'Auto' -or -not $_.Exception.Data.Contains('AVWorkerStartupFailed')){throw}
                    Write-Warning (Get-RemnexaProgressText 'AVWorkerFallback')
                    Write-AVLog -Message $_.Exception.Message -Level Warning -Event 'Scan/Engine'
                }
            }
            if(-not $run) {
                Stop-ClamAVScanEngine
                $run=Invoke-AVNativeProcess -FilePath $status.ClamScanPath -ArgumentList $arguments.ToArray() -TimeoutSeconds $effectiveTimeout -WorkingDirectory (Split-Path -Parent $status.ClamScanPath) -OnOutput $onOutput -OnHeartbeat $heartbeat -CaptureFilter $filter -ProcessPriority $profile.ProcessPriority -CancellationToken $cancellation.Source.Token -PauseControl $BackgroundControl
            }
            $phaseTimes.ScannerSeconds=$scannerWatch.Elapsed.TotalSeconds
        }
        $phase.Restart()
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'ProgressTaskEvaluate') -CurrentItem '' -Force
        if($BackgroundControl){$BackgroundControl.Update('Evaluating',$metrics.Reported,$inventory.Files,$profile.Mode)}
        if ($run.ExitCode -notin @(0,1,2)) { throw "Unbekannter clamscan Exit-Code $($run.ExitCode)." }
        $results = @(Get-ClamAVScanResult -InputObject @($run.StandardOutput,$run.StandardError) -ExitCode $run.ExitCode -ScanType $ScanType)
        if ($run.ExitCode -eq 2) { throw ("ClamAV konnte den Scan nicht abschliessen (Exit-Code 2): " + $run.StandardError + ' ' + $run.StandardOutput) }
        if ($run.ExitCode -eq 1 -and @($results | Where-Object Status -in @('Infected','LimitExceeded')).Count -eq 0) { throw 'ClamAV meldete einen Fund, aber die Ausgabe konnte nicht sicher zugeordnet werden.' }
        if ($Quarantine) {
            $infected = @($results | Where-Object Status -eq 'Infected')
            $quarantineProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskQuarantine') -Total $infected.Count -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
            try {
                $done = 0
                foreach ($result in $infected) {
                    $cancellation.Poll()
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
        $unconfirmed = [Math]::Max(0, $inventory.Files - $metrics.Reported)
        $findings = @($results | Where-Object Severity -in @('Malware','PotentiallyUnwanted')).Count
        $partial = $unconfirmed -gt 0 -or $inventory.Skipped -gt 0 -or $metrics.Errors -gt 0 -or $metrics.Unexpected -gt 0 -or $inventory.Files -eq 0 -or @($results|Where-Object Status -eq 'LimitExceeded').Count -gt 0
        $coverage = (Get-RemnexaProgressText 'ProgressScanCoverage') -f $metrics.Reported,$metrics.Errors,$unconfirmed,$inventory.Skipped
        if ($results.Count -eq 0) {
            $results = @([PSCustomObject]@{ Path=($targets -join '; '); Signature=$null; Severity=$(if($partial){'Warning'}else{'None'}); Status=$(if($partial){'Partial'}else{'Clean'}); ExitCode=0; ScanType=$ScanType; Quarantined=$false; QuarantineId=$null; Message=$coverage })
        }
        foreach ($result in $results) {
            foreach ($entry in @{ StartedAt=$started; CompletedAt=[DateTimeOffset]::Now; DurationSeconds=[Math]::Round($scanWatch.Elapsed.TotalSeconds,2); FilesTotal=$inventory.Files; FilesReported=$metrics.Reported; FilesUnconfirmed=$unconfirmed; InventorySkipped=$inventory.Skipped; CoverageComplete=(-not $partial);PerformanceMode=$profile.Mode;ProcessPriority=$profile.ProcessPriority;ScanBackend=$(if($run.PSObject.Properties['Backend']){$run.Backend}else{'clamscan'});PhaseTimes=$phaseTimes }.GetEnumerator()) { $result | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value -Force }
            foreach($property in @('EngineProcessId','EngineReused','ScanThreads')){if($run.PSObject.Properties[$property]){$result|Add-Member -NotePropertyName $property -NotePropertyValue $run.$property -Force}}
        }
        $phaseTimes.ResultSeconds=$phase.Elapsed.TotalSeconds
        Update-RemnexaProgress $progress -Completed ([Math]::Min($metrics.Reported, $inventory.Files)) -Status $coverage -CurrentItem '' -Force
        Complete-RemnexaProgress $progress -Outcome $(if($partial -or $findings){'Warning'}else{'Completed'})
        Write-AVLog -Message "ClamAV-$ScanType-Scan beendet; Funde: $findings. $coverage" -Level $(if($partial -or $findings){'Warning'}else{'Success'}) -Event 'Scan' -Data $results
        return $results
    }
    catch {
        Stop-ClamAVScanEngine
        if(-not $_.Exception.Data.Contains('NativeCleanupFailed') -and (($cancellation -and $cancellation.Source.IsCancellationRequested) -or $_.Exception -is [OperationCanceledException])) {
            if($inventoryProgress -and $inventoryProgress.Outcome -eq 'Running'){Complete-RemnexaProgress $inventoryProgress -Outcome Cancelled}
            Complete-RemnexaProgress $progress -Outcome Cancelled -Status (Get-RemnexaProgressText 'AVScanCancelled')
            $evidence=@(if($null -ne $results){$results}else{Get-ClamAVScanResult -InputObject $metrics.Evidence.ToString() -ExitCode 0 -ScanType $ScanType})
            if($null -eq $results){foreach($item in $evidence){$item.ExitCode=$null}}
            $evidence+=[pscustomobject]@{Path='';Signature=$null;Severity='Warning';Status='Cancelled';ExitCode=$null;ScanType=$ScanType;Quarantined=$false;QuarantineId=$null;Message=(Get-RemnexaProgressText 'AVScanCancelled')}
            foreach($item in $evidence){$item|Add-Member CoverageComplete $false -Force;$item|Add-Member FilesReported $metrics.Reported -Force;$item|Add-Member FilesTotal $inventory.Files -Force}
            Write-AVLog -Message (Get-RemnexaProgressText 'AVScanCancelled') -Level Warning -Event Scan
            return $evidence
        }
        if ($inventoryProgress -and $inventoryProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $inventoryProgress -Outcome Failed }
        if ($progress.Outcome -eq 'Running') { Complete-RemnexaProgress $progress -Outcome Failed -Status $_.Exception.Message }
        Write-AVLog -Message $_.Exception.Message -Level Error -Event Scan
        throw
    }
    finally {
        if($acknowledgements){$acknowledgements.Dispose()}
        if($cancellation){$cancellation.Dispose()}
        $script:AVCancellation=$null
        if($scanLease){$scanLease.ReleaseMutex();$scanLease.Dispose()}
        $script:AVDiscoveryProgress = $null
        if (Test-Path -LiteralPath $targetListPath) { Remove-Item -LiteralPath $targetListPath -Force -ErrorAction SilentlyContinue }
    }
}
