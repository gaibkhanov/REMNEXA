#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SessionDirectory)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot '../Antivirus.psd1') -PassThru
& $module {$script:AVUseLocalBackground=$true}
$rpc=$null;$consoleView=$null
try {
    & $module {
        param($Directory)
        if((Split-Path -Leaf $Directory) -notmatch '^scan-[a-f0-9]{32}$' -or -not (Get-RemnexaPathSafety $Directory).IsSafe){throw 'Unsafe scan host directory.'}
    } $SessionDirectory
    $owner=& $module {param($Path)Read-AVSessionJson $Path} (Join-Path $SessionDirectory 'owner.json')
    if(-not $owner -or $owner.PipeName -notmatch '^REMNEXA\.Scan\.[a-f0-9]{32}$' -or $owner.Language -notin @('de','en','es','fr','ru','tr')){throw 'Invalid scan host metadata.'}
    & $module {Initialize-AVSessionRpc}
    $rpc=[Remnexa.ScanSession.Rpc]::new([string]$owner.PipeName)
    if(-not $rpc.Ready.Task.Wait(10000)){throw 'Scan control server did not start.'}
    $process=Get-Process -Id $PID
    try{$descriptor=[ordered]@{Protocol=1;ProcessId=$PID;StartTicks=$process.StartTime.ToUniversalTime().Ticks;PipeName=$owner.PipeName;Context=$owner.Context}}finally{$process.Dispose()}
    & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory 'server.json') $descriptor
    $parentId=[int]$owner.ParentId;$parentTicks=[long]$owner.ParentStartTicks
    $detached=$false;$lastWrite=[DateTimeOffset]::MinValue;$lastDraw=[DateTimeOffset]::MinValue;$finishedAt=$null;$reportWritten=$false;$release=$false
    $lastRequest=[DateTimeOffset]::UtcNow;$scan=$null;$reportName='results.json';$lastFallbackState='';$lastFallback=[DateTimeOffset]::MinValue
    $language=[string]$owner.Language
    $scanType='Unknown';$startedAtUtc=$null;$completedAtUtc=$null;$historyId=$null
    $messages=[IO.File]::ReadAllText((Join-Path $PSScriptRoot ('../../locales/'+$language+'.json')))|ConvertFrom-Json -AsHashtable
    function Text {param($Key,[object[]]$Values=@())$text=[string]$messages[$Key];if($Values.Count){$text -f $Values}else{$text}}
    function Save-HostSnapshot {
        param($Snapshot)
        $view=$Snapshot|Select-Object State,Phase,Mode,Error,Files,Total,Findings,Omitted,ElapsedSeconds,ActiveSeconds,Evidence,ScannerProcessId
        $preview=@($view.Evidence|Select-Object -First 100)
        $view.Omitted+=[Math]::Max(0,$view.Evidence.Length-$preview.Count)
        $view.Evidence=@($preview|ForEach-Object{if($_.Length -gt 2048){$_.Substring(0,2048)+'…'}else{$_}})
        $view|Add-Member Detached $detached
        $view|Add-Member ReportFile $reportName
        $view|Add-Member ScanType $scanType
        $view|Add-Member StartedAtUtc $startedAtUtc
        $view|Add-Member CompletedAtUtc $completedAtUtc
        $view|Add-Member RecordedAtUtc ([DateTimeOffset]::UtcNow.ToString('o'))
        $view|Add-Member HistoryId $historyId
        & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory 'status.json') $view
    }
    function Save-CompletedScan {
        param($Snapshot)
        if(-not $Snapshot -or $reportWritten -or $Snapshot.State -notin @('Completed','Warning','Cancelled','Failed')){return}
        & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory $reportName) @($Snapshot.Results)
        $script:completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        $record=[ordered]@{SchemaVersion=1;HistoryId=$historyId;ScanType=$scanType;State=$Snapshot.State;Files=$Snapshot.Files;Total=$Snapshot.Total;Findings=$Snapshot.Findings;ElapsedSeconds=$Snapshot.ElapsedSeconds;StartedAtUtc=$startedAtUtc;CompletedAtUtc=$completedAtUtc;RecordedAtUtc=$completedAtUtc;ReportFile=$reportName}
        & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory ('history-'+$historyId+'.json')) $record
        $script:reportWritten=$true;$script:finishedAt=[DateTimeOffset]::UtcNow
    }
    try{$Host.UI.RawUI.WindowTitle='REMNEXA Antivirus'}catch{}
    $consoleView=& $module {New-AVScanWindow}
    while(-not $release) {
        $request=$rpc.Take()
        if($request) {
            try {
                $command=$request.Command;$lastRequest=[DateTimeOffset]::UtcNow
                switch($command.Action) {
                    'Start' {
                        if($command.ScanType -notin @('Quick','Full','Custom') -or $command.Language -notin @('de','en','es','fr','ru','tr') -or -not [IO.Path]::IsPathFullyQualified($command.ConfigPath)){throw 'Invalid scan parameters.'}
                        Save-CompletedScan (Get-ClamAVBackgroundScan -IncludeResults)
                        [void](Start-ClamAVBackgroundScan -ScanType $command.ScanType -Path @($command.Paths) -ConfigPath $command.ConfigPath -Language $command.Language)
                        $parentId=[int]$request.ClientProcessId
                        $parent=Get-Process -Id $parentId
                        try{$parentTicks=$parent.StartTime.ToUniversalTime().Ticks}finally{$parent.Dispose()}
                        $detached=$false;$finishedAt=$null;$reportWritten=$false
                        $reportName='results-'+$command.Id+'.json'
                        $scanType=$command.ScanType;$startedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');$completedAtUtc=$null;$historyId=$command.Id
                        $language=$command.Language;$messages=[IO.File]::ReadAllText((Join-Path $PSScriptRoot ('../../locales/'+$language+'.json')))|ConvertFrom-Json -AsHashtable
                    }
                    'Pause'{Set-ClamAVBackgroundScan Pause}
                    'Resume'{Set-ClamAVBackgroundScan Resume}
                    'Cancel'{Set-ClamAVBackgroundScan Cancel}
                    'Detach'{$detached=$true}
                    'Release' {
                        $current=Get-ClamAVBackgroundScan
                        if($current -and $current.State -in @('Starting','Running','Pausing','Paused','Cancelling')){throw 'The scan is still active.'}
                        Stop-ClamAVBackgroundScan;$release=$true
                    }
                }
                $current=Get-ClamAVBackgroundScan
                if($current){Save-HostSnapshot $current}
                $request.Complete($true,$null)
            }catch{$request.Complete($false,$_.Exception.Message)}
        }
        if(-not $detached){
            try{$parent=Get-Process -Id $parentId -ErrorAction Stop;try{if($parent.StartTime.ToUniversalTime().Ticks -ne $parentTicks){$detached=$true}}finally{$parent.Dispose()}}catch{$detached=$true}
        }
        $scan=Get-ClamAVBackgroundScan -IncludeResults
        $active=$scan -and $scan.State -in @('Starting','Running','Pausing','Paused','Cancelling')
        if($scan -and -not $active){Save-CompletedScan $scan}
        if($scan -and ([DateTimeOffset]::UtcNow-$lastWrite).TotalMilliseconds -ge 500) {
            Save-HostSnapshot $scan
            $lastWrite=[DateTimeOffset]::UtcNow
        }
        $interactive=$false
        try{$interactive=-not[Console]::IsInputRedirected -and -not[Console]::IsOutputRedirected}catch{}
        if($interactive -and $scan) {
            if(([DateTimeOffset]::UtcNow-$lastDraw).TotalMilliseconds -ge 500) {
                $lines=[Collections.Generic.List[string]]::new();$colors=[Collections.Generic.List[ushort]]::new()
                function Row {param($Value,$Color=7)$lines.Add([string]$Value);$colors.Add([ushort]$Color)}
                Row (Text 'AVSessionWindowTitle') 11
                Row (Text 'AVSessionWindowHint') 14
                $controls=if(-not $active){''}elseif($scan.State -in @('Paused','Pausing')){'[R] '+(Text 'AVBackgroundResume')+'  [C] '+(Text 'AVBackgroundCancel')}elseif($scan.State -eq 'Cancelling'){Text 'AVBackgroundStateCancelling'}else{'[P] '+(Text 'AVBackgroundPause')+'  [C] '+(Text 'AVBackgroundCancel')}
                Row $controls 15
                Row (Text 'AVSessionKeysHint') 8
                $total=if($scan.Total -lt 0){'?'}else{$scan.Total};$percent=if($scan.Total -gt 0){'{0}%' -f [Math]::Floor(100*$scan.Files/$scan.Total)}else{'?'}
                $stateColor=if($scan.State -eq 'Failed'){12}elseif($scan.State -in @('Warning','Cancelled','Paused','Pausing')){14}elseif($scan.State -eq 'Completed'){10}else{11}
                Row (Text 'AVSessionSummary' @((Text ('AVBackgroundState'+$scan.State)),$scan.Files,$total,$percent,$scan.Findings)) $stateColor
                $elapsed=[TimeSpan]::FromSeconds([Math]::Floor($scan.ElapsedSeconds)).ToString('hh\:mm\:ss')
                $rate=if($scan.ActiveSeconds -gt 0){[Math]::Round($scan.Files/$scan.ActiveSeconds,1)}else{0}
                Row (Text 'AVBackgroundDetail' @($scan.Mode,(Text ('AVBackgroundPhase'+$scan.Phase)),$elapsed,$rate))
                if($scan.Error){Row $scan.Error 12}
                if(-not $active){Row (Text 'AVSessionReportSaved' @((Join-Path $SessionDirectory $reportName))) 10}
                Row (Text 'AVBackgroundFindings') 14
                foreach($line in @($scan.Evidence|Select-Object -Last 20)){Row $line 14}
                $drawn=$false
                try{if($consoleView){$drawn=$consoleView.Draw($lines.ToArray(),$colors.ToArray())}}catch{Write-Verbose $_.Exception.Message}
                if(-not $drawn -and ($lastFallbackState -ne $scan.State -or ([DateTimeOffset]::UtcNow-$lastFallback).TotalSeconds -ge 5)){
                    foreach($line in $lines){Write-Host ([regex]::Replace($line,'[\p{Cc}\p{Cf}]',' '))}
                    $lastFallbackState=$scan.State
                    $lastFallback=[DateTimeOffset]::UtcNow
                }
                $lastDraw=[DateTimeOffset]::UtcNow
            }
            try{for($key=0;$key -lt 16 -and [Console]::KeyAvailable;$key++){
                switch([Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()){'P'{if($active){Set-ClamAVBackgroundScan Pause}};'R'{if($active){Set-ClamAVBackgroundScan Resume}};'C'{if($active){Set-ClamAVBackgroundScan Cancel}}}
            }}catch{Write-Verbose ('Console input unavailable: '+$_.Exception.Message)}
        }
        if(-not $active -and $scan -and $detached){Stop-ClamAVBackgroundScan}
        if($finishedAt -and ([DateTimeOffset]::UtcNow-$finishedAt).TotalSeconds -gt $(if($detached){15}else{60})){break}
        if(-not $scan -and ([DateTimeOffset]::UtcNow-$lastRequest).TotalSeconds -gt 20){break}
        Start-Sleep -Milliseconds 50
    }
}catch{
    $failure=[pscustomobject]@{State='Failed';Phase='Evaluating';Mode='';Error=$_.Exception.Message;Files=0;Total=-1;Findings=0;Omitted=0;ElapsedSeconds=0;ActiveSeconds=0;Evidence=@();ScannerProcessId=0}
    if($scan){$failure=$scan|Select-Object State,Phase,Mode,Error,Files,Total,Findings,Omitted,ElapsedSeconds,ActiveSeconds,Evidence,ScannerProcessId;$failure.State='Failed';$failure.Error=$_.Exception.Message}
    try{& $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory 'status.json') $failure}catch{}
    exit 1
}finally{
    if($consoleView){$consoleView.Dispose()}
    try{Stop-ClamAVBackgroundScan}finally{if($rpc){$rpc.Dispose()};Remove-Module Antivirus -ErrorAction SilentlyContinue}
}
