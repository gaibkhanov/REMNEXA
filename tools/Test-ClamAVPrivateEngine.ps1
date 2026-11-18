#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [switch]$TestStartupCancellation,
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/private-engine-native-tests.json')
)
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-NativeTest-'+[guid]::NewGuid().ToString('N'))
$database=Join-Path $workspace 'database';$data=Join-Path $workspace 'data';$temp=Join-Path $workspace 'extract'
foreach($directory in @($database,$data,$temp)){[void][IO.Directory]::CreateDirectory($directory)}
$client=$null;$batch=$null
try{
    if(-not('Remnexa.Worker.Client' -as [type])){Add-Type -Path (Join-Path $ProjectRoot 'Antivirus/Private/WorkerTransport.cs')}
    $bytes=[Text.Encoding]::UTF8.GetBytes('REMNEXA harmless custom hash-signature fixture. No malware or EICAR.')
    $hash=[Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
    # Custom HDB is confined to this fixture. No production signature changes.
    [IO.File]::WriteAllText((Join-Path $database 'fixture.hdb'),("{0}:{1}:REMNEXA.BenignFixture" -f $hash,$bytes.Length)+"`n")
    $match=Join-Path $data 'match.dat';[IO.File]::WriteAllBytes($match,$bytes)
    $clean=Join-Path $data 'clean-ü.dat';[IO.File]::WriteAllText($clean,'Ordinary different benign content.')
    $empty=Join-Path $data 'empty.dat';[IO.File]::WriteAllBytes($empty,[byte[]]::new(0))
    $archive=Join-Path $data 'archive.zip'
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry('match.dat');$stream=$entry.Open();try{$stream.Write($bytes)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
    $list=Join-Path $workspace 'list.txt';[IO.File]::WriteAllLines($list,[string[]]@($match,$clean,$empty,$archive),[Text.UTF8Encoding]::new($false))
    $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='init';$frame.Threads=2;$frame.MaxBytes=1MB;$frame.IdleSeconds=15
    $frame.EnginePath=Join-Path $ProjectRoot 'ClamAV/libclamav.dll';$frame.DatabasePath=$database;$frame.TempPath=$temp
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $client=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $ProjectRoot 'Antivirus/Workers/NativeScan.ps1'),$frame,2GB,5000)
    if(-not $client.Ready.Wait(30000)){throw 'Native engine fixture initialization timed out.'}
    $ready=$client.Ready.GetAwaiter().GetResult();$initialization=$watch.Elapsed.TotalSeconds
    if($ready.Version -ne '1.5.4' -or $ready.SignatureCount -lt 1 -or $client.TokenMode -ne 'restricted'){throw 'Native ABI/token test failed.'}
    $workerId=$client.ProcessId
    $passes=[Collections.Generic.List[object]]::new()
    foreach($iteration in 1..2){
        $batch=$client.BeginBatch($list,2);$replies=[Collections.Generic.List[object]]::new();$watch.Restart()
        while(-not $batch.Completed -or $batch.QueuedResults){
            if($watch.Elapsed.TotalSeconds -gt 30){throw 'Native fixture scan timed out.'}
            $reply=$batch.Take(50);if($reply){$replies.Add($reply);$batch.Acknowledge($reply.Id)}
        }
        if($batch.Error){throw $batch.Error}
        if($replies.Count -ne 4 -or @($replies|Where-Object Code -eq 1).Count -ne 2 -or @($replies|Where-Object Code -eq 0).Count -ne 2){throw 'Native clean/detection/archive results differ from expected.'}
        if(@($replies|Select-Object -ExpandProperty Id -Unique).Count -ne 4){throw 'Native result duplicated.'}
        $passes.Add([pscustomobject]@{Iteration=$iteration;Seconds=$watch.Elapsed.TotalSeconds;Files=$replies.Count;Detections=2;Clean=2;SameProcess=($client.ProcessId -eq $workerId)})
        $batch.Dispose();$batch=$null
    }
    if(@(Get-NetTCPConnection -ErrorAction Stop|Where-Object OwningProcess -eq $workerId).Count){throw 'Unexpected private-worker TCP socket.'}
    $worker=Get-Process -Id $workerId
    try{$idleExited=$worker.WaitForExit(20000)}finally{$worker.Dispose()}
    if(-not $idleExited){throw 'Native worker idle shutdown failed.'}
    $startupCancelled=$false;$privateAcl=$null
    if($TestStartupCancellation){
        $client.Dispose();$client=$null
        Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
        $module=Get-Module Antivirus;$source=[Threading.CancellationTokenSource]::new()
        try{
            $config=Get-AVConfig;$config.ClamAVPath=Join-Path $ProjectRoot 'ClamAV';$config.DatabasePath=Join-Path $ProjectRoot 'ClamAV/database'
            $config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine';$config.ExcludedPaths=@();$config.ScanBackend='PrivateWorker';$config.AutoCheckUpdates=$false
            $configPath=Join-Path $workspace 'config.json';$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
            & $module {
                param($ConfigPath,$Source)
                $script:AVConfigPath=$ConfigPath;Set-RemnexaProgressRendering $false
                $script:CancelOriginal=(Get-Command Start-AVPrivateWorker).ScriptBlock
                $script:CancelSource=$Source;$script:ObservedWorkerIds=[Collections.Generic.List[int]]::new();$script:AclEvidence=[pscustomobject]@{Valid=$false}
                function script:Start-AVPrivateWorker {
                    param($Config,$Status,$Profile,$MaxBytes,$IncludePUA,$OnHeartbeat,$CancellationToken)
                    $ids=$script:ObservedWorkerIds;$source=$script:CancelSource;$root=Join-Path $Config.LogPath 'ScanWorkers';$evidence=$script:AclEvidence
                    $callback={param($Event)
                        if($ids.Count -eq 0){
                            $ids.Add($Event.ProcessId)
                            $directory=Get-ChildItem -LiteralPath $root -Directory|Select-Object -First 1
                            $acl=Get-Acl -LiteralPath $directory.FullName
                            $allowed=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18')
                            $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
                            $evidence.Valid=$acl.AreAccessRulesProtected -and $rules.Count -eq 2 -and @($rules|Where-Object{$_.IdentityReference.Value -notin $allowed}).Count -eq 0
                            $source.CancelAfter(500)
                        }
                        if($OnHeartbeat){& $OnHeartbeat $Event}
                    }.GetNewClosure()
                    & $script:CancelOriginal -Config $Config -Status $Status -Profile $Profile -MaxBytes $MaxBytes -IncludePUA $IncludePUA -OnHeartbeat $callback -CancellationToken $CancellationToken
                }
            } $configPath $source
            $cancelResult=@(Invoke-ClamAVScan -Path $clean -ConfigPath $configPath -CancellationToken $source.Token)
            $ids=@(& $module {$script:ObservedWorkerIds.ToArray()})
            $privateAcl=& $module {$script:AclEvidence.Valid}
            if(-not $privateAcl){throw 'Private temporary ACL was not verified.'}
            if($ids.Count -ne 1 -or @($cancelResult|Where-Object Status -eq 'Cancelled').Count -ne 1 -or @($cancelResult|Where-Object CoverageComplete).Count){throw 'Public startup cancellation was not observed.'}
            foreach($workerId in $ids){if(Get-Process -Id $workerId -ErrorAction SilentlyContinue){throw 'Public cancellation left an owned process.'}}
            if(@(Get-ChildItem -LiteralPath (Join-Path $config.LogPath 'ScanWorkers') -Directory -ErrorAction SilentlyContinue).Count){throw 'Cancelled startup retained its temporary directory.'}
            $startupCancelled=$true
        }finally{$source.Dispose();Remove-Module Antivirus -ErrorAction SilentlyContinue}
    }
    $report=[pscustomobject]@{Passed=$true;Engine=$ready.Version;TokenMode='restricted';Threads=$ready.Threads;Signatures=$ready.SignatureCount;InitializationSeconds=$initialization;IdleExitObserved=$idleExited;TcpConnections=0;PublicStartupCancellationObserved=$startupCancelled;PrivateTemporaryAclVerified=$privateAcl;Dataset='Isolated harmless custom HDB, matching file and ZIP, clean Unicode file, empty file';Passes=$passes.ToArray()}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $OutputPath -Encoding utf8
    $report
}finally{
    try{if($batch){$batch.Dispose()}}finally{if($client){$client.Dispose()}}
    if((Split-Path -Leaf $workspace) -match '^REMNEXA-NativeTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($workspace,$true)}
}
