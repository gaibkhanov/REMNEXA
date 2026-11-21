function Receive-AVBackgroundScan {
    if($script:AVBackgroundScan -and $script:AVBackgroundScan.Handle.IsCompleted -and -not $script:AVBackgroundScan.Received) {
        $job=$script:AVBackgroundScan
        try { $job.Results=@($job.PowerShell.EndInvoke($job.Handle)) }
        catch { $job.Control.Finish('Failed',$_.Exception.Message) }
        finally { $job.PowerShell.Dispose();$job.Runspace.Dispose();$job.Handle.AsyncWaitHandle.Dispose();$job.Received=$true }
    }
}

function Get-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([switch]$IncludeResults)
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
    Receive-AVBackgroundScan
    if($script:AVBackgroundScan -and -not $script:AVBackgroundScan.Received){throw (Get-RemnexaProgressText 'AVScanBusy')}
    if($ScanType -eq 'Custom' -and -not $Path.Count){throw 'Custom scan requires a path.'}
    if($script:AVBackgroundScan){$script:AVBackgroundScan.Control.Dispose();$script:AVBackgroundScan=$null}
    Initialize-AVBackgroundSupport
    # Release the foreground cache before a new runspace loads a signature DB.
    Stop-ClamAVScanEngine
    $control=[Remnexa.Scan.BackgroundControl]::new()
    $runspace=[runspacefactory]::CreateRunspace();$runspace.Open()
    $powershell=[powershell]::Create();$powershell.Runspace=$runspace
    $worker={
        param($ModulePath,$Config,$Type,$Targets,$LanguageCode,$Control)
        $ErrorActionPreference='Stop'
        try {
            $module=Import-Module $ModulePath -PassThru -ErrorAction Stop
            & $module {param($ConfigPath,$Locale)$script:AVConfigPath=$ConfigPath;Set-RemnexaProgressLanguage $Locale;Set-RemnexaProgressRendering $false} $Config $LanguageCode
            $rows=@(Invoke-ClamAVScan -ScanType $Type -Path $Targets -ConfigPath $Config -BackgroundControl $Control -CancellationToken $Control.Cancellation.Token)
            $outcome=if(@($rows|Where-Object Status -eq 'Cancelled').Count){'Cancelled'}elseif(@($rows|Where-Object { -not $_.CoverageComplete -or $_.Severity -ne 'None' }).Count){'Warning'}else{'Completed'}
            $Control.Finish($outcome,'')
            $rows
        } catch {$Control.Finish('Failed',$_.Exception.Message)}
        finally {if(Get-Command Stop-ClamAVScanEngine -ErrorAction SilentlyContinue){Stop-ClamAVScanEngine}}
    }
    try {
        [void]$powershell.AddScript($worker.ToString()).AddArgument((Join-Path $script:AVModuleRoot 'Antivirus.psd1')).AddArgument([IO.Path]::GetFullPath($ConfigPath)).AddArgument($ScanType).AddArgument([string[]]$Path).AddArgument($Language).AddArgument($control)
        $handle=$powershell.BeginInvoke()
        $script:AVBackgroundScan=[pscustomobject]@{Control=$control;PowerShell=$powershell;Runspace=$runspace;Handle=$handle;Received=$false;Results=@()}
    }catch{$powershell.Dispose();$runspace.Dispose();$control.Dispose();throw}
    Get-ClamAVBackgroundScan
}

function Set-ClamAVBackgroundScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Pause','Resume','Cancel')][string]$Action)
    Receive-AVBackgroundScan
    if(-not $script:AVBackgroundScan -or $script:AVBackgroundScan.Received){return}
    switch($Action){'Pause'{$script:AVBackgroundScan.Control.Pause()};'Resume'{$script:AVBackgroundScan.Control.Resume()};'Cancel'{$script:AVBackgroundScan.Control.Cancel()}}
}

function Stop-ClamAVBackgroundScan {
    [CmdletBinding()]
    param()
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
}
