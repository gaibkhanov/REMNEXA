# SPDX-License-Identifier: MIT
function Show-ComponentUpdateNotification {
    if(-not (Get-Variable ComponentUpdatesAvailable -Scope Script -ErrorAction SilentlyContinue)){return}
    try{
        $state=Get-RemnexaComponentUpdates -ApplicationRoot $script:ComponentApplicationRoot
        if(-not $state.Task){return}
        $token=$state.Task.Id+':'+$state.Task.Status
        $last=Get-Variable ComponentNotice -Scope Script -ErrorAction SilentlyContinue
        if($last -and $last.Value -eq $token){return}
        $script:ComponentNotice=$token
        if($state.Task.Component -eq 'Check'){
            $available=@($state.Components|Where-Object Status -eq 'update_available')
            if($state.Task.Status -eq 'Completed' -and $available.Count){Write-Status (T 'CUAvailable' @((@($available|ForEach-Object{Get-ComponentDisplayName $_.Name}) -join ', '))) 'Info'}
            return
        }
        $component=Get-ComponentDisplayName $state.Task.Component
        if($state.Task.Status -eq 'Completed'){Write-Status (T 'CUCompleted' @($component,$state.Task.Version)) 'Success'}
        elseif($state.Task.Status -eq 'Ready'){
            if($state.Task.Component -eq 'PowerShell'){Write-Status (T 'CUPSReady' @($state.Task.Version,$PSVersionTable.PSVersion.ToString())) 'Info'}
            elseif($state.Task.Component -eq 'Application'){Write-Status (T 'CUAppReady' @($state.Task.Version)) 'Success'}
        }
        elseif($state.Task.Status -eq 'Failed'){Write-Status (T 'CUFailed') 'Warning'}
        elseif($state.Task.Status -eq 'Cancelled'){Write-Status (T 'CUCancelled') 'Info'}
    }catch{Write-Verbose 'Component notification unavailable.'}
}

function Get-ComponentDisplayName {
    param([string]$Name)
    if($Name -eq 'Check'){return T 'CUCheck'}
    T ('CUName'+$Name)
}

function Show-ComponentDashboard {
    Write-Host (T 'CUDashboard') -ForegroundColor White
    Write-Host ('  REMNEXA '+$script:CleanerVersion+'  |  PowerShell '+$PSVersionTable.PSVersion) -ForegroundColor Cyan
    try{
        $state=Get-RemnexaComponentUpdates -ApplicationRoot $script:ComponentApplicationRoot
        $local=Get-RemnexaLocalTools -ApplicationRoot $script:ComponentApplicationRoot -ApplicationVersion $script:CleanerVersion -PowerShellVersion $PSVersionTable.PSVersion.ToString() -MetadataOnly
        $engine=$state.Components|Where-Object Name -eq 'Antivirus';$db=$state.Components|Where-Object Name -eq 'Signatures'
        $version=[string]$local.Antivirus
        if(-not $version -and (Test-Path -LiteralPath (Join-Path $script:ComponentApplicationRoot 'package-manifest.json'))){$manifest=Get-Content (Join-Path $script:ComponentApplicationRoot 'package-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json;$version=[string]$manifest.Components.ClamAV.Version}
        if(-not $version){$version=T 'CUUnknown'}
        $databaseVersion=if($local.Signatures){$local.Signatures}else{T 'CUUnknown'}
        Write-Host (T 'CUToolsLine' @($version,$databaseVersion)) -ForegroundColor DarkCyan
        if($state.Prepared.PowerShell -and $state.Prepared.PowerShell -ne $PSVersionTable.PSVersion.ToString()){Write-Host (T 'CUPSReady' @($state.Prepared.PowerShell,$PSVersionTable.PSVersion.ToString())) -ForegroundColor Green}
        $updates=@($state.Components|Where-Object Status -eq 'update_available')
        if($updates.Count){Write-Host (T 'CUAvailable' @((@($updates|ForEach-Object{Get-ComponentDisplayName $_.Name}) -join ', '))) -ForegroundColor Yellow}
        if($state.Task -and $state.Task.Status -notin @('Completed','Ready','Failed','Cancelled')){Write-Host (T 'CURunning' @((Get-ComponentDisplayName $state.Task.Component),(T ('CUPhase'+$state.Task.Status)))) -ForegroundColor Cyan}
        Show-ComponentActivities -UpdateState $state
    }catch{Write-Verbose 'Dashboard component snapshot unavailable.'}
    Write-Host ''
}

function Show-ComponentActivities {
    param($UpdateState)
    $activities=[Collections.Generic.List[object]]::new()
    foreach($row in @($UpdateState.History|Select-Object -First 4)){
        if($row.Component -notin @('PowerShell','Antivirus','Signatures','Both','Application') -or $row.Outcome -notin @('Completed','Ready','Failed','Cancelled')){continue}
        $activities.Add([pscustomobject]@{Timestamp=$row.Timestamp;Text=(T 'CUActivityUpdate' @((Get-ComponentDisplayName $row.Component),(T ('CUPhase'+$row.Outcome))))})
    }
    if(Get-Command Get-ClamAVScanHistory -ErrorAction SilentlyContinue){foreach($row in @(Get-ClamAVScanHistory -First 3)){$activities.Add([pscustomobject]@{Timestamp=$row.RecordedAtUtc;Text=((T ('AVBackgroundState'+$row.State))+': '+(T 'CUActivityScan' @($row.Files,$row.Findings)))})}}
    foreach($row in @(Get-RemovalHistory|Select-Object -First 3)){$activities.Add([pscustomobject]@{Timestamp=$row.Timestamp;Text=(T 'CUActivityRemoval' @($row.ProgramName))})}
    foreach($row in @(Get-StartupHistory|Select-Object -First 3)){$activities.Add([pscustomobject]@{Timestamp=$row.Timestamp;Text=(T 'CUActivityStartup')})}
    Write-Host (T 'CUActivities') -ForegroundColor White
    if(-not $activities.Count){Write-Host ('  '+(T 'CUActivitiesNone')) -ForegroundColor DarkGray}
    else{foreach($row in @($activities|Sort-Object Timestamp -Descending|Select-Object -First 4)){$safe=[regex]::Replace([string]$row.Text,'[\x00-\x1f\x7f-\x9f]',' ');if($safe.Length -gt 160){$safe=$safe.Substring(0,157)+'...'};Write-Host ('  '+(Format-HistoryTimestamp $row.Timestamp)+'  '+$safe) -ForegroundColor DarkGray}}
}

function Start-ComponentUpdateFromConsole {
    param([ValidateSet('PowerShell','Antivirus','Signatures','Both','Application')][string]$Component,[string]$AfterScanType='',[string[]]$AfterScanPath=@())
    Stop-ClamAVScanEngine
    $started=Start-RemnexaComponentTask -ApplicationRoot $script:ComponentApplicationRoot -ApplicationVersion $script:CleanerVersion -Component $Component -AfterScanType $AfterScanType -AfterScanPath $AfterScanPath -Language $script:Language
    Write-Status (T $(if($started){'CUStarted'}else{'CUBusy'})) $(if($started){'Info'}else{'Warning'})
    return $started
}

function Show-ComponentUpdateCenter {
    while($true){
        Clear-RemnexaScreen;Show-BrandHeader
        Write-Host (T 'CUTitle') -ForegroundColor White
        Write-Host (T 'CUDescription') -ForegroundColor DarkGray
        $state=Get-RemnexaComponentUpdates -ApplicationRoot $script:ComponentApplicationRoot
        foreach($row in $state.Components){
            $installed=if($row.Name -eq 'PowerShell'){$PSVersionTable.PSVersion.ToString()}elseif($row.Name -eq 'Application'){$script:CleanerVersion}elseif($row.InstalledVersion){$row.InstalledVersion}else{T 'CUUnknown'}
            $available=if($row.AvailableVersion){$row.AvailableVersion}else{T 'CUUnknown'}
            $status=if($row.Status -in @('current','update_available','offline','not_installed','unknown','check_failed')){Get-AVUpdateStatusText $row.Status}else{T 'CUUnknown'}
            Write-Host (T 'CUVersionLine' @((Get-ComponentDisplayName $row.Name),$installed,$available,$status)) -ForegroundColor $(if($row.Status -eq 'update_available'){'Yellow'}else{'Gray'})
        }
        if($state.Prepared.ApplicationVersion){Write-Host (T 'CUAppReady' @($state.Prepared.ApplicationVersion)) -ForegroundColor Green;Write-Host $state.Prepared.ApplicationPath}
        if($state.Prepared.PowerShell -and $state.Prepared.PowerShell -ne $PSVersionTable.PSVersion.ToString()){Write-Host (T 'CUPSReady' @($state.Prepared.PowerShell,$PSVersionTable.PSVersion.ToString())) -ForegroundColor Green}
        $actions=@{}
        $busy=$state.Task -and $state.Task.Status -notin @('Completed','Ready','Failed','Cancelled')
        if($state.Task){
            Write-Host (T 'CURunning' @((Get-ComponentDisplayName $state.Task.Component),(T ('CUPhase'+$state.Task.Status)))) -ForegroundColor $(if($state.Task.Status -eq 'Failed'){'Yellow'}elseif($busy){'Cyan'}else{'Green'})
            if($state.Task.Total -gt 0 -and $state.Task.Completed -ge 0){Write-Host (T 'CUBytes' @([Math]::Floor(100*$state.Task.Completed/$state.Task.Total),(Format-ByteSize $state.Task.Completed),(Format-ByteSize $state.Task.Total))) -ForegroundColor Cyan}
            if($state.Task.Reason){$reason=if($state.Task.Reason -in @('external_installation','antivirus_not_installed','scan_still_running','database_changed_retry')){'CUReason_'+$state.Task.Reason}else{'CUFailed'};Write-Host (T $reason) -ForegroundColor Yellow}
        }
        Write-Host (T 'CURefreshHint') -ForegroundColor DarkGray
        if(-not $busy){
            Write-Host ('  [U] '+(T 'CUCheck'))
            foreach($pair in @(@('1','PowerShell'),@('2','Antivirus'),@('3','Signatures'),@('4','Application'))){
                $row=$state.Components|Where-Object Name -eq $pair[1]
                if(($pair[1] -eq 'Signatures' -and $row.CanInstall) -or ($row.Status -eq 'update_available' -and $row.CanInstall)){$actions[$pair[0]]=$pair[1];Write-Host ('  ['+$pair[0]+'] '+(T 'CUInstall' @((Get-ComponentDisplayName $pair[1]))))}
            }
            $app=$state.Components|Where-Object Name -eq 'Application'
            if($app.Status -eq 'update_available' -and -not $app.CanInstall){Write-Host (T 'CUAppPackageUnavailable') -ForegroundColor Yellow}
        }elseif($state.Task.Status -ne 'Installing'){Write-Host ('  [C] '+(T 'CUCancel'))}
        Write-Host ('  [0] '+(T 'BackMain'))
        $answer=(Read-RemnexaInput (T 'SelectPrompt') -ComponentManagerContext).Trim().ToUpperInvariant()
        if($answer -eq '0'){return}
        if(-not $answer){continue}
        if($answer -eq 'U' -and -not $busy){[void](Start-RemnexaComponentTask -ApplicationRoot $script:ComponentApplicationRoot -ApplicationVersion $script:CleanerVersion -Component Check -Force);continue}
        if($answer -eq 'C' -and $busy){[void](Stop-RemnexaComponentTask -ApplicationRoot $script:ComponentApplicationRoot);continue}
        if($actions.ContainsKey($answer)){
            Write-Host (T 'CUConsent' @((Get-ComponentDisplayName $actions[$answer]))) -ForegroundColor Yellow
            Write-Host ('  [J/Y] '+(T 'CUConfirm'));Write-Host ('  [0] '+(T 'BackPreviousMenu'))
            $consent=(Read-RemnexaInput (T 'SelectPrompt') -ComponentManagerContext).Trim().ToUpperInvariant()
            if($consent -in @('J','Y')){[void](Start-ComponentUpdateFromConsole $actions[$answer])}
        }
    }
}
