#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SessionDirectory)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot '../Antivirus.psd1') -PassThru
& $module {$script:AVUseLocalBackground=$true}
$rpc=$null
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
    $lastRequest=[DateTimeOffset]::UtcNow;$scan=$null;$showAll=$false;$reportName='results.json'
    $language=[string]$owner.Language
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
        & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory 'status.json') $view
    }
    try{$Host.UI.RawUI.WindowTitle='REMNEXA Antivirus'}catch{}
    while(-not $release) {
        $request=$rpc.Take()
        if($request) {
            try {
                $command=$request.Command;$lastRequest=[DateTimeOffset]::UtcNow
                switch($command.Action) {
                    'Start' {
                        if($command.ScanType -notin @('Quick','Full','Custom') -or $command.Language -notin @('de','en','es','fr','ru','tr') -or -not [IO.Path]::IsPathFullyQualified($command.ConfigPath)){throw 'Invalid scan parameters.'}
                        [void](Start-ClamAVBackgroundScan -ScanType $command.ScanType -Path @($command.Paths) -ConfigPath $command.ConfigPath -Language $command.Language)
                        $parentId=[int]$request.ClientProcessId
                        $parent=Get-Process -Id $parentId
                        try{$parentTicks=$parent.StartTime.ToUniversalTime().Ticks}finally{$parent.Dispose()}
                        $detached=$false;$finishedAt=$null;$reportWritten=$false
                        $reportName='results-'+$command.Id+'.json'
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
        if($scan -and -not $active -and -not $reportWritten){
            & $module {param($Path,$Data)Write-AVSessionJson $Path $Data} (Join-Path $SessionDirectory $reportName) @($scan.Results)
            $reportWritten=$true;$finishedAt=[DateTimeOffset]::UtcNow
        }
        if($scan -and ([DateTimeOffset]::UtcNow-$lastWrite).TotalMilliseconds -ge 500) {
            Save-HostSnapshot $scan
            $lastWrite=[DateTimeOffset]::UtcNow
        }
        $interactive=$false
        try{$interactive=-not[Console]::IsInputRedirected -and -not[Console]::IsOutputRedirected}catch{}
        if($interactive -and $scan) {
            if(([DateTimeOffset]::UtcNow-$lastDraw).TotalSeconds -ge 1) {
                if(-not $showAll){try{Clear-Host}catch{}}
                Write-Host (Text 'AVSessionWindowTitle') -ForegroundColor Cyan
                Write-Host (Text 'AVSessionWindowHint') -ForegroundColor Yellow
                $total=if($scan.Total -lt 0){'?'}else{$scan.Total};$percent=if($scan.Total -gt 0){'{0}%' -f [Math]::Floor(100*$scan.Files/$scan.Total)}else{'?'}
                Write-Host (Text 'AVSessionSummary' @((Text ('AVBackgroundState'+$scan.State)),$scan.Files,$total,$percent,$scan.Findings))
                foreach($line in @($scan.Evidence|Select-Object -Last 20)){Write-Host ([regex]::Replace($line,'[\p{Cc}\p{Cf}]',' ')) -ForegroundColor Yellow}
                if($scan.Error){Write-Host ([regex]::Replace($scan.Error,'[\p{Cc}\p{Cf}]',' ')) -ForegroundColor Red}
                Write-Host ('[P] '+(Text 'AVBackgroundPause')+'  [R] '+(Text 'AVBackgroundResume')+'  [C] '+(Text 'AVBackgroundCancel'))
                if(-not $active){Write-Host (Text 'AVSessionReportSaved' @((Join-Path $SessionDirectory $reportName))) -ForegroundColor Green}
                $lastDraw=[DateTimeOffset]::UtcNow
            }
            if([Console]::KeyAvailable){
                switch([Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()){'P'{Set-ClamAVBackgroundScan Pause};'R'{Set-ClamAVBackgroundScan Resume};'C'{Set-ClamAVBackgroundScan Cancel}}
            }
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
    try{Stop-ClamAVBackgroundScan}finally{if($rpc){$rpc.Dispose()};Remove-Module Antivirus -ErrorAction SilentlyContinue}
}
