function Stop-ClamAVUpdateCheck {
    [CmdletBinding()]
    param()
    if($null -eq $script:AVUpdateWorker) { return }
    try {
        if(-not $script:AVUpdateWorker.Process.HasExited) {
            $script:AVUpdateWorker.Process.Kill($true)
            if(-not $script:AVUpdateWorker.Process.WaitForExit(2000)) { throw 'Update worker did not stop.' }
        }
    }
    finally { $script:AVUpdateWorker.Process.Dispose();$script:AVUpdateWorker=$null }
}

function Start-ClamAVUpdateCheck {
    [CmdletBinding()]
    param([string]$ConfigPath=$script:AVConfigPath,[string]$StatePath,[switch]$Force)
    $config=Get-AVConfig -Path $ConfigPath
    $options=Get-AVUpdateOptions $config
    if(-not $options.AutoCheckUpdates -and -not $Force) { return $false }
    if(-not(Find-ClamAVInstallation -Config $config)) { return $false }
    $stateFile=Get-AVUpdateStatePath $StatePath
    if($script:AVUpdateWorker) {
        if(-not $script:AVUpdateWorker.Process.HasExited -and -not $Force) { return $true }
        Stop-ClamAVUpdateCheck
    }
    $state=Read-AVUpdateState -Path $stateFile -Context (Get-AVUpdateContext $config)
    if(-not(Test-AVUpdateDue $state $options -Force:$Force)) { return $false }
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $PSHOME 'pwsh.exe';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',(Join-Path $script:AVModuleRoot 'Workers/UpdateCheck.ps1'),'-ConfigPath',(Expand-AVPath $ConfigPath),'-StatePath',$stateFile)) { $info.ArgumentList.Add($arg) }
    if($Force) { $info.ArgumentList.Add('-Force') }
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try {
        $started=[DateTimeOffset]::UtcNow
        if(-not $process.Start()) { throw 'Could not start metadata worker.' }
        $script:AVUpdateWorker=[pscustomobject]@{Process=$process;Output=$process.StandardOutput.ReadToEndAsync();Error=$process.StandardError.ReadToEndAsync();Started=$started;DeadlineSeconds=(($options.UpdateNetworkTimeoutSeconds+8)*($options.UpdateRetryCount+1)+$options.UpdateRetryBackoffSeconds*7+5)}
        return $true
    }
    catch { $process.Dispose();throw }
}

function Get-ClamAVUpdateState {
    [CmdletBinding()]
    param([string]$ConfigPath=$script:AVConfigPath,[string]$StatePath)
    $config=Get-AVConfig -Path $ConfigPath
    $options=Get-AVUpdateOptions $config
    $state=Read-AVUpdateState -Path (Get-AVUpdateStatePath $StatePath) -Context (Get-AVUpdateContext $config)
    $running=$false
    $failed=$false
    if($script:AVUpdateWorker) {
        if($script:AVUpdateWorker.Process.HasExited) {
            # Read after exit: the worker may have committed between our first
            # cache read and HasExited. Never overwrite that success as failure.
            $state=Read-AVUpdateState -Path (Get-AVUpdateStatePath $StatePath) -Context (Get-AVUpdateContext $config)
            $failed=($script:AVUpdateWorker.Process.ExitCode -ne 0 -or -not $state.lastAttemptUtc -or [DateTimeOffset]::Parse($state.lastAttemptUtc) -lt $script:AVUpdateWorker.Started)
            Stop-ClamAVUpdateCheck
        }
        elseif(([DateTimeOffset]::UtcNow-$script:AVUpdateWorker.Started).TotalSeconds -gt $script:AVUpdateWorker.DeadlineSeconds) { Stop-ClamAVUpdateCheck;$failed=$true }
        else { $running=$true }
    }
    if($failed) {
        $state.status='check_failed';$state.lastAttemptUtc=[DateTimeOffset]::UtcNow.ToString('o')
        $state.failureCount=[Math]::Min(10,$state.failureCount+1);$state.nextRetryUtc=[DateTimeOffset]::UtcNow.AddMinutes(1).ToString('o')
        try { Save-AVUpdateState $state (Get-AVUpdateStatePath $StatePath) } catch { Write-Verbose 'Could not persist metadata-worker failure.' }
    }
    $root=Find-ClamAVInstallation -Config $config
    if(-not $root) { $state.status='not_installed';$state.engine.status='not_installed';$state.signatures.status='not_installed' }
    $state.signatures.canUpdate=($null -ne $root -and (Test-Path -LiteralPath (Join-Path $root 'freshclam.exe') -PathType Leaf))
    $stale=(-not $state.lastSuccessfulCheckUtc -or [DateTimeOffset]::Parse($state.lastSuccessfulCheckUtc).AddHours($options.UpdateCheckIntervalHours) -le [DateTimeOffset]::UtcNow -or $state.status -in @('offline','check_failed'))
    $state|Add-Member -NotePropertyName isStale -NotePropertyValue $stale -Force
    $state|Add-Member -NotePropertyName isChecking -NotePropertyValue $running -Force
    foreach($component in @($state.engine,$state.signatures)) {
        $componentStale=(-not $component.checkedUtc -or [DateTimeOffset]::Parse($component.checkedUtc).AddHours($options.UpdateCheckIntervalHours) -le [DateTimeOffset]::UtcNow -or $component.status -notin @('current','update_available'))
        $component|Add-Member -NotePropertyName isStale -NotePropertyValue $componentStale -Force
    }
    return $state
}

function Invoke-ClamAVUpdateCheck {
    [CmdletBinding()]
    param([string]$ConfigPath=$script:AVConfigPath,[string]$StatePath,[switch]$Force)
    $progress=New-RemnexaProgress -Activity (Get-RemnexaProgressText 'AVUpdateCheck')
    try {
        $started=Start-ClamAVUpdateCheck -ConfigPath $ConfigPath -StatePath $StatePath -Force:$Force
        if($started) {
            do {
                $state=Get-ClamAVUpdateState -ConfigPath $ConfigPath -StatePath $StatePath
                if($state.isChecking) { Update-RemnexaProgress $progress;Start-Sleep -Milliseconds 100 }
            }while($state.isChecking)
        }
        else { $state=Get-ClamAVUpdateState -ConfigPath $ConfigPath -StatePath $StatePath }
        Complete-RemnexaProgress $progress -Outcome $(if($state.status -in @('offline','check_failed','unknown') -or $state.isStale){'Warning'}else{'Completed'})
        return $state
    }
    catch { Complete-RemnexaProgress $progress -Outcome Failed;throw }
}

function Invoke-ClamAVManagedUpdate {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([ValidateSet('Engine','Signatures','Both')][string]$Component='Signatures',[string]$ConfigPath=$script:AVConfigPath,[string]$StatePath)
    if(-not $PSCmdlet.ShouldProcess($Component,'Update ClamAV')) { return }
    Stop-ClamAVUpdateCheck
    $path=Get-AVUpdateStatePath $StatePath
    $lease=Enter-AVUpdateLease $path
    $scanLease=$null
    try {
    $config=Get-AVConfig -Path $ConfigPath
    $scanLease=Enter-AVScanLease $config
    $state=Read-AVUpdateState -Path $path -Context (Get-AVUpdateContext $config)
    $checked=$state.lastSuccessfulCheckUtc
    $verifiedEnginePackage=$state.engine.canUpdate
    $available=@{}
    foreach($db in $state.signatures.databases) { if($null -ne $db.availableVersion) { $available[$db.name]=$db.availableVersion } }
    # Invalidate before writes: an interrupted update cannot leave a fresh claim.
    $state.lastSuccessfulCheckUtc=$null;$state.status='unknown'
    Save-AVUpdateState $state $path
    try {
        if($Component -in @('Engine','Both')) { [void](Update-ClamAVEngine -ConfigPath $ConfigPath -Confirm:$false) }
        if($Component -in @('Signatures','Both')) {
            $status=Update-ClamAVSignature -ConfigPath $ConfigPath
            if(-not $status.Ready) { throw 'Signature update did not produce a usable database.' }
            $state.signatures.lastSuccessfulUpdateUtc=[DateTimeOffset]::UtcNow.ToString('o')
        }
        $local=Get-ClamAVStatus -ConfigPath $ConfigPath
        if(-not $local.Installed -or -not $local.Ready) { throw 'The updated installation is not ready.' }
        $state.engine.installedVersion=$local.Version
        $state.engine.status='unknown';$state.engine.updateAvailable=$false;$state.engine.canUpdate=$false
        if($state.engine.availableVersion) {
            $newer=(ConvertTo-AVSemanticVersion $state.engine.availableVersion).CompareTo((ConvertTo-AVSemanticVersion $local.Version)) -gt 0
            $state.engine.updateAvailable=$newer;$state.engine.status=if($newer){'update_available'}else{'current'}
            $state.engine.canUpdate=($newer -and $verifiedEnginePackage)
        }
        $state.signatures.databases=@(Get-AVLocalDatabaseVersions $config)
        $state.signatures.status='unknown';$state.signatures.recommended=$true
        if($available.Count -eq 3) { Set-AVSignatureUpdateComparison $state $available }
        $state.lastSuccessfulCheckUtc=$checked;$state.nextRetryUtc=$null;$state.failureCount=0
        if($checked) {
            $state.status=if($state.engine.updateAvailable -or $state.signatures.status -eq 'update_available'){'update_available'}elseif($state.engine.status -eq 'current' -and $state.signatures.status -eq 'current'){'current'}else{'unknown'}
        }
        Save-AVUpdateState $state $path
        return $local
    }
    catch { $state.status='check_failed';Save-AVUpdateState $state $path;throw }
    }
    finally { if($scanLease){$scanLease.ReleaseMutex();$scanLease.Dispose()};$lease.Dispose() }
}
