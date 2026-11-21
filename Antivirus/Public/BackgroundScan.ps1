function Receive-AVBackgroundScan {
    if($script:AVBackgroundScan -and $script:AVBackgroundScan.Handle.IsCompleted -and -not $script:AVBackgroundScan.Received) {
        $job=$script:AVBackgroundScan
        try { $job.Results=@($job.PowerShell.EndInvoke($job.Handle)) }
        catch { $job.Control.Finish('Failed',$_.Exception.Message) }
        finally { $job.PowerShell.Dispose();$job.Handle.AsyncWaitHandle.Dispose();$job.Received=$true }
    }
}

function Get-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([switch]$IncludeResults)
    if(-not $script:AVUseLocalBackground){return Get-AVIndependentScan -IncludeResults:$IncludeResults}
    Receive-AVBackgroundScan
    if(-not $script:AVBackgroundScan){return $null}
    $snapshot=$script:AVBackgroundScan.Control.Snapshot()
    # The worker may publish its outcome just before pipeline/engine cleanup.
    # Do not expose a terminal state until EndInvoke has collected the results.
    if(-not $script:AVBackgroundScan.Received -and $snapshot.State -in @('Completed','Warning','Cancelled','Failed')){$snapshot.State='Running';$snapshot.Phase='Evaluating'}
    if($IncludeResults){$snapshot|Add-Member -NotePropertyName Results -NotePropertyValue @($script:AVBackgroundScan.Results)}
    return $snapshot
}

function Start-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([ValidateSet('Quick','Full','Custom')][string]$ScanType='Quick',[string[]]$Path=@(),
        [string]$ConfigPath=$script:AVConfigPath,[ValidateSet('de','en','es','fr','ru','tr')][string]$Language='de')
    if(-not $script:AVUseLocalBackground){return Start-AVIndependentScan -ScanType $ScanType -Path $Path -ConfigPath $ConfigPath -Language $Language}
    Receive-AVBackgroundScan
    if($script:AVBackgroundScan -and -not $script:AVBackgroundScan.Received){throw (Get-RemnexaProgressText 'AVScanBusy')}
    if($ScanType -eq 'Custom' -and -not $Path.Count){throw 'Custom scan requires a path.'}
    Initialize-AVBackgroundSupport
    # Release the foreground cache before a new runspace loads a signature DB.
    Stop-ClamAVScanEngine
    $runspace=$null
    if($script:AVBackgroundScan){
        if(-not $script:AVBackgroundScan.RunspaceDisposed){$runspace=$script:AVBackgroundScan.Runspace}
        $script:AVBackgroundScan.Control.Dispose();$script:AVBackgroundScan=$null
    }
    $control=[Remnexa.Scan.BackgroundControl]::new()
    if(-not $runspace){$runspace=[runspacefactory]::CreateRunspace();$runspace.Open()}
    $powershell=[powershell]::Create();$powershell.Runspace=$runspace
    $worker={
        param($ModulePath,$Config,$Type,$Targets,$LanguageCode,$Control)
        $ErrorActionPreference='Stop'
        try {
            $module=Import-Module $ModulePath -PassThru -ErrorAction Stop
            & $module {param($ConfigPath,$Locale)$script:AVUseLocalBackground=$true;$script:AVConfigPath=$ConfigPath;Set-RemnexaProgressLanguage $Locale;Set-RemnexaProgressRendering $false} $Config $LanguageCode
            $rows=@(Invoke-ClamAVScan -ScanType $Type -Path $Targets -ConfigPath $Config -BackgroundControl $Control -CancellationToken $Control.Cancellation.Token)
            $outcome=if(@($rows|Where-Object Status -eq 'Cancelled').Count){'Cancelled'}elseif(@($rows|Where-Object { -not $_.CoverageComplete -or $_.Severity -ne 'None' }).Count){'Warning'}else{'Completed'}
            $Control.Finish($outcome,'')
            $rows
        } catch {
            if(Get-Command Stop-ClamAVScanEngine -ErrorAction SilentlyContinue){Stop-ClamAVScanEngine}
            $Control.Finish('Failed',$_.Exception.Message)
        }
    }
    try {
        [void]$powershell.AddScript($worker.ToString()).AddArgument((Join-Path $script:AVModuleRoot 'Antivirus.psd1')).AddArgument([IO.Path]::GetFullPath($ConfigPath)).AddArgument($ScanType).AddArgument([string[]]$Path).AddArgument($Language).AddArgument($control)
        $handle=$powershell.BeginInvoke()
        $script:AVBackgroundScan=[pscustomobject]@{Control=$control;PowerShell=$powershell;Runspace=$runspace;Handle=$handle;Received=$false;RunspaceDisposed=$false;Results=@()}
    }catch{$powershell.Dispose();$runspace.Dispose();$control.Dispose();throw}
    Get-ClamAVBackgroundScan
}

function Set-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Pause','Resume','Cancel')][string]$Action)
    if(-not $script:AVUseLocalBackground){$session=Find-AVIndependentSession;if($session){Send-AVSessionCommand $session $Action};return}
    Receive-AVBackgroundScan
    if(-not $script:AVBackgroundScan -or $script:AVBackgroundScan.Received){return}
    switch($Action){'Pause'{$script:AVBackgroundScan.Control.Pause()};'Resume'{$script:AVBackgroundScan.Control.Resume()};'Cancel'{$script:AVBackgroundScan.Control.Cancel()}}
}

function Stop-ClamAVBackgroundScan {
    [CmdletBinding()]
    param()
    if(-not $script:AVUseLocalBackground){Stop-AVIndependentScan;Stop-AVIndependentIdleEngine;return}
    if(-not $script:AVBackgroundScan){return}
    $job=$script:AVBackgroundScan
    if(-not $job.Received) {
        $job.Control.Cancel()
        if(-not $job.Handle.AsyncWaitHandle.WaitOne(15000)) {
            # Never unload a runspace that still owns a live scanner.
            throw 'Background scan cleanup has not completed; keep REMNEXA open and retry.'
        }
        Receive-AVBackgroundScan
    }
    Stop-AVBackgroundIdleEngine
}

function Stop-AVBackgroundIdleEngine {
    if(-not $script:AVUseLocalBackground){Stop-AVIndependentIdleEngine;return}
    # Keep completed results, but release a cached engine before foreground
    # scans/updates so only one signature database is resident per application.
    Receive-AVBackgroundScan
    $job=$script:AVBackgroundScan
    if(-not $job -or -not $job.Received -or $job.RunspaceDisposed){return}
    $cleanup=[powershell]::Create();$cleanup.Runspace=$job.Runspace
    try {
        [void]$cleanup.AddScript('Stop-ClamAVScanEngine -ErrorAction Stop')
        [void]$cleanup.Invoke()
        if($cleanup.HadErrors){throw $cleanup.Streams.Error[0]}
    }finally{$cleanup.Dispose();$job.Runspace.Dispose();$job.RunspaceDisposed=$true}
}

function Disconnect-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([switch]$Resume,[switch]$OnlyOwned)
    if($script:AVUseLocalBackground){throw 'A local scan runspace cannot be detached from its owning process.'}
    $session=Find-AVIndependentSession
    if($OnlyOwned -and $session -and -not $session.Owned){return}
    if(-not $session -or $session.Detached -or -not(Test-AVSessionAlive $session)){return}
    if($Resume){
        Send-AVSessionCommand $session Resume
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do{
            $scan=Get-AVIndependentScan
            if(-not $scan -or $scan.State -notin @('Pausing','Paused')){break}
            Start-Sleep -Milliseconds 50
        }while($watch.Elapsed.TotalSeconds -lt 5)
        if($scan -and $scan.State -in @('Pausing','Paused')){throw (Get-RemnexaProgressText 'AVSessionCleanupPending')}
    }
    Send-AVSessionCommand $session Detach
    $session.Detached=$true
}
