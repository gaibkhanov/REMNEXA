function Initialize-AVSessionRpc {
    if(-not ('Remnexa.ScanSession.Rpc' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'ScanSessionRpc.cs') -ErrorAction Stop}
}

function New-AVPrivateSessionDirectory {
    param([string]$Path)
    $parent=Split-Path -Parent $Path
    $pending=[Collections.Generic.Stack[string]]::new();$existing=$parent
    while(-not (Test-Path -LiteralPath $existing)){
        $pending.Push($existing);$next=Split-Path -Parent $existing
        if(-not $next -or $next -eq $existing){throw 'Invalid session parent.'};$existing=$next
    }
    if(-not (Get-RemnexaPathSafety $existing).IsSafe){throw 'Unsafe scan session ancestor.'}
    while($pending.Count){$next=$pending.Pop();[void][IO.Directory]::CreateDirectory($next);if(-not (Get-RemnexaPathSafety $next).IsSafe){throw 'Unsafe new session parent.'}}
    if(-not (Get-RemnexaPathSafety $parent).IsSafe){throw 'Unsafe scan session parent.'}
    if((Test-Path -LiteralPath $Path) -and -not (Get-RemnexaPathSafety $Path).IsSafe){throw 'Unsafe existing scan session directory.'}
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User;$acl.SetOwner($owner)
    foreach($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl',('ContainerInherit, ObjectInherit'),'None','Allow'))}
    [void][IO.FileSystemAclExtensions]::CreateDirectory($acl,$Path)
    if(-not (Get-RemnexaPathSafety $Path).IsSafe){throw 'Unsafe scan session directory.'}
}

function Write-AVSessionJson {
    param([string]$Path,$Value)
    $directory=Split-Path -Parent $Path
    if(-not (Get-RemnexaPathSafety $directory).IsSafe -or ((Test-Path -LiteralPath $Path) -and -not (Get-RemnexaPathSafety $Path).IsSafe)){throw 'Unsafe scan session output.'}
    $temp=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $json=ConvertTo-Json -InputObject $Value -Depth 12 -Compress
        $stream=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($bytes);$stream.Flush($true)}finally{$stream.Dispose()}
        for($attempt=0;$attempt -lt 4;$attempt++){
            try{[IO.File]::Move($temp,$Path,$true);break}
            catch [IO.IOException]{if($attempt -eq 3){throw};Start-Sleep -Milliseconds (20*[Math]::Pow(2,$attempt))}
            catch [UnauthorizedAccessException]{if($attempt -eq 3){throw};Start-Sleep -Milliseconds (20*[Math]::Pow(2,$attempt))}
        }
    }finally{if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
}

function Read-AVSessionJson {
    param([string]$Path,[long]$Limit=2MB)
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    if(-not (Get-RemnexaPathSafety $Path).IsSafe){throw 'Unsafe scan session data.'}
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($stream.Length -gt $Limit){throw 'Oversized scan session data.'}
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
        try{$reader.ReadToEnd()|ConvertFrom-Json -Depth 14 -ErrorAction Stop}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}

function Get-AVSessionRoot {
    param([string]$ConfigPath=$script:AVConfigPath)
    Join-Path (Expand-AVPath ([string](Get-AVConfig -Path $ConfigPath).LogPath)) 'ScanSessions'
}

function Test-AVSessionAlive {
    param($Session)
    try {
        $process=Get-Process -Id ([int]$Session.Descriptor.ProcessId) -ErrorAction Stop
        try{return ($process.StartTime.ToUniversalTime().Ticks -eq [long]$Session.Descriptor.StartTicks -and -not $process.HasExited)}finally{$process.Dispose()}
    }catch{return $false}
}

function Find-AVIndependentSession {
    param([string]$ConfigPath=$script:AVConfigPath)
    if($script:AVIndependentSession){return $script:AVIndependentSession}
    $root=Get-AVSessionRoot $ConfigPath
    $pointer=Read-AVSessionJson (Join-Path $root 'current.json')
    if(-not $pointer -or $pointer.Id -notmatch '^scan-[a-f0-9]{32}$'){return $null}
    $directory=Join-Path $root $pointer.Id
    $descriptor=Read-AVSessionJson (Join-Path $directory 'server.json')
    if(-not $descriptor -or $descriptor.Protocol -ne 1 -or $descriptor.Context -ne (Get-AVUpdateContext (Get-AVConfig -Path $ConfigPath))){return $null}
    $script:AVIndependentSession=[pscustomobject]@{Directory=$directory;Descriptor=$descriptor;Detached=$false;Owned=$false}
    return $script:AVIndependentSession
}

function Send-AVSessionCommand {
    param($Session,[ValidateSet('Start','Pause','Resume','Cancel','Detach','Release')][string]$Action,[hashtable]$Parameters=@{})
    if(-not (Test-AVSessionAlive $Session)){throw (Get-RemnexaProgressText 'AVSessionUnavailable')}
    Initialize-AVSessionRpc
    $command=[ordered]@{Id=[guid]::NewGuid().ToString('N');Action=$Action}
    foreach($key in $Parameters.Keys){$command[$key]=$Parameters[$key]}
    $reply=[Remnexa.ScanSession.Rpc]::Send([string]$Session.Descriptor.PipeName,[int]$Session.Descriptor.ProcessId,($command|ConvertTo-Json -Depth 5 -Compress),5000)|ConvertFrom-Json
    if(-not $reply.ok){throw [string]$reply.error}
}

function Get-AVIndependentScan {
    param([switch]$IncludeResults)
    $session=Find-AVIndependentSession
    if(-not $session){return $null}
    $snapshot=Read-AVSessionJson (Join-Path $session.Directory 'status.json')
    if(-not $snapshot){return $null}
    if($snapshot.State -in @('Starting','Running','Pausing','Paused','Cancelling') -and -not (Test-AVSessionAlive $session)){$snapshot.State='Failed';$snapshot.Error=Get-RemnexaProgressText 'AVSessionUnavailable'}
    $reportName=if($snapshot.PSObject.Properties['ReportFile'] -and $snapshot.ReportFile -match '^results-[a-f0-9]{32}\.json$'){[string]$snapshot.ReportFile}else{'results.json'}
    if($IncludeResults){
        $rows=Read-AVSessionJson (Join-Path $session.Directory $reportName) -Limit 128MB
        $snapshot|Add-Member -NotePropertyName Results -NotePropertyValue @($rows|Where-Object{$null -ne $_}) -Force
    }
    $snapshot|Add-Member -NotePropertyName ReportPath -NotePropertyValue (Join-Path $session.Directory $reportName) -Force
    return $snapshot
}

function Start-AVIndependentScan {
    param([string]$ScanType,[string[]]$Path,[string]$ConfigPath,[string]$Language)
    $previous=Get-AVIndependentScan
    if($previous -and $previous.State -in @('Starting','Running','Pausing','Paused','Cancelling')){throw (Get-RemnexaProgressText 'AVScanBusy')}
    Stop-ClamAVScanEngine
    $root=Get-AVSessionRoot $ConfigPath
    $session=$script:AVIndependentSession
    if(-not $session -or (Split-Path -Parent $session.Directory) -ne $root -or -not (Test-AVSessionAlive $session)) {
        New-AVPrivateSessionDirectory $root
        $directory=Join-Path $root ('scan-'+[guid]::NewGuid().ToString('N'))
        New-AVPrivateSessionDirectory $directory
        $pipeName='REMNEXA.Scan.'+[guid]::NewGuid().ToString('N')
        $parent=Get-Process -Id $PID
        try{$owner=[ordered]@{ParentId=$PID;ParentStartTicks=$parent.StartTime.ToUniversalTime().Ticks;PipeName=$pipeName;Context=(Get-AVUpdateContext (Get-AVConfig -Path $ConfigPath));Language=$Language}}finally{$parent.Dispose()}
        Write-AVSessionJson (Join-Path $directory 'owner.json') $owner
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'));$info.UseShellExecute=$true
        $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::$script:AVScanHostWindowStyle
        foreach($arg in @('-NoLogo','-NoProfile','-File',(Join-Path $script:AVModuleRoot 'Workers/ScanHost.ps1'),'-SessionDirectory',$directory)){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($info)
        try {
            $timer=[Diagnostics.Stopwatch]::StartNew();$descriptor=$null
            while(-not $descriptor){
                if($process.HasExited -or $timer.Elapsed.TotalSeconds -gt 15){throw (Get-RemnexaProgressText 'AVSessionUnavailable')}
                $descriptor=Read-AVSessionJson (Join-Path $directory 'server.json');Start-Sleep -Milliseconds 50
            }
            if($descriptor.ProcessId -ne $process.Id -or $descriptor.PipeName -cne $pipeName){throw 'Unexpected scan session owner.'}
        }finally{$process.Dispose()}
        $session=[pscustomobject]@{Directory=$directory;Descriptor=$descriptor;Detached=$false;Owned=$true};$script:AVIndependentSession=$session
        Write-AVSessionJson (Join-Path $root 'current.json') ([ordered]@{Id=(Split-Path -Leaf $directory)})
    }
    Send-AVSessionCommand $session Start @{ConfigPath=[IO.Path]::GetFullPath($ConfigPath);ScanType=$ScanType;Paths=[string[]]$Path;Language=$Language}
    $session.Detached=$false
    $session.Owned=$true
    Get-AVIndependentScan
}

function Stop-AVIndependentScan {
    $session=Find-AVIndependentSession
    if(-not $session){return}
    $scan=Get-AVIndependentScan
    if($scan -and $scan.State -in @('Starting','Running','Pausing','Paused','Cancelling')) {
        Send-AVSessionCommand $session Cancel
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do{$scan=Get-AVIndependentScan;if($scan.State -notin @('Starting','Running','Pausing','Paused','Cancelling')){break};Start-Sleep -Milliseconds 100}while($watch.Elapsed.TotalSeconds -lt 15)
        if($scan.State -in @('Starting','Running','Pausing','Paused','Cancelling')){throw (Get-RemnexaProgressText 'AVSessionCleanupPending')}
    }
}

function Stop-AVIndependentIdleEngine {
    $session=Find-AVIndependentSession
    if(-not $session -or -not (Test-AVSessionAlive $session)){return}
    $scan=Get-AVIndependentScan
    if(-not $scan -or $scan.State -notin @('Starting','Running','Pausing','Paused','Cancelling')){Send-AVSessionCommand $session Release}
}
