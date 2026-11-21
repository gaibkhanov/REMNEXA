function Initialize-AVWorkerTransport {
    if(-not ('Remnexa.Worker.Client' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WorkerTransport.cs') -ErrorAction Stop }
}

function Get-AVWorkerPolicy {
    param($Profile)
    $cores=[Math]::Max(1,[int]$Profile.LogicalCores)
    $memory=[long]$Profile.AvailableMemoryBytes
    $threads=if($Profile.Mode -eq 'Eco' -or $Profile.ResourceConstrained -or $memory -lt 4GB){1}elseif($Profile.Mode -eq 'Fast' -and $memory -ge 6GB){[Math]::Min(4,$cores)}else{[Math]::Min(2,$cores)}
    $budget=[Math]::Min([long]3GB,[Math]::Max([long]1536MB,($memory-1GB)))
    [pscustomobject]@{Threads=$threads;MemoryLimit=[long]$budget;CpuRate=$(if($Profile.Mode -eq 'Eco'){2500}elseif($Profile.Mode -eq 'Fast'){8000}else{5000})}
}

function Get-AVEngineFingerprint {
    param($Config,[string]$Dll,[long]$MaxBytes,[bool]$IncludePUA,[string]$Mode)
    $database=Expand-AVPath ([string]$Config.DatabasePath)
    if(-not (Get-RemnexaPathSafety $database).IsSafe -or -not (Get-RemnexaPathSafety $Dll).IsSafe){throw 'Unsafe private-engine path.'}
    $parts=[Collections.Generic.List[string]]::new()
    $parts.Add((Get-AVUpdateContext $Config));$parts.Add("$MaxBytes|$IncludePUA|$Mode")
    $entries=@(Get-ChildItem -LiteralPath $database -Force -ErrorAction Stop)
    if(@($entries|Where-Object PSIsContainer).Count){throw 'The private engine requires a flat database directory.'}
    $files=@($entries|Sort-Object Name)
    if($files.Count -gt 2048){throw 'Too many private-engine database files.'}
    foreach($file in @((Get-Item -LiteralPath $Dll))+$files) {
        if(-not (Get-RemnexaPathSafety $file.FullName).IsSafe){throw 'Unsafe private-engine database entry.'}
        $parts.Add($file.Name+':'+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash)
    }
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($parts -join '|'))))
}

function Remove-AVWorkerTemporaryDirectory {
    param([string]$Path,[string]$Root)
    if(-not $Path -or -not(Test-Path -LiteralPath $Path)){return}
    $full=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $full) -notmatch '^worker-[a-f0-9]{32}$' -or -not (Get-RemnexaPathSafety $full).IsSafe){throw 'Unsafe worker cleanup path.'}
    # .NET Windows recursive deletion removes reparse entries without following
    # their targets. Never pass an unchecked or caller-selected root here.
    [IO.Directory]::Delete($full,$true)
}

function Test-AVWarmWorkerMemory {
    param($Profile)
    return ($script:AVPrivateWorker -and $script:AVPrivateWorker.Client.Alive -and $Profile.AvailableMemoryBytes -ge 512MB)
}

function Start-AVPrivateWorker {
    param($Config,$Status,$Profile,[long]$MaxBytes,[bool]$IncludePUA,[scriptblock]$OnHeartbeat,[Threading.CancellationToken]$CancellationToken,$PauseControl=$null)
    $dll=Join-Path (Split-Path -Parent $Status.ClamScanPath) 'libclamav.dll'
    $key=Get-AVEngineFingerprint -Config $Config -Dll $dll -MaxBytes $MaxBytes -IncludePUA $IncludePUA -Mode $Profile.Mode
    if($script:AVPrivateWorker -and $script:AVPrivateWorker.Key -eq $key -and $script:AVPrivateWorker.Client.Alive) {
        $script:AVPrivateWorker.Reused=$true
        Write-Host (Get-RemnexaProgressText 'AVWorkerReuse') -ForegroundColor DarkCyan
        return $script:AVPrivateWorker
    }
    if($Config.ScanBackend -eq 'Auto' -and $script:AVPrivateFailure -and $script:AVPrivateFailure.Key -eq $key -and $script:AVPrivateFailure.Until -gt [DateTimeOffset]::UtcNow){throw 'Private engine startup is cooling down after a failure.'}
    Stop-ClamAVScanEngine
    Initialize-AVWorkerTransport
    # Re-evaluate after releasing an old cached engine's memory.
    $fresh=Get-ClamAVScanPerformance -Mode $Profile.Mode
    if(-not $fresh.CanStart){throw (Get-RemnexaProgressText 'AVScanMemoryLow')}
    $policy=Get-AVWorkerPolicy $fresh
    $root=Join-Path (Expand-AVPath ([string]$Config.LogPath)) 'ScanWorkers'
    [void][IO.Directory]::CreateDirectory($root)
    if(-not (Get-RemnexaPathSafety $root).IsSafe){throw 'Unsafe worker temporary root.'}
    $temp=Join-Path $root ('worker-'+[guid]::NewGuid().ToString('N'))
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($owner)
    foreach($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    }
    [void][IO.FileSystemAclExtensions]::CreateDirectory($acl,$temp)
    $client=$null
    try {
        Write-Host (Get-RemnexaProgressText 'AVWorkerLoading') -ForegroundColor Cyan
        $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='init';$frame.EnginePath=$dll;$frame.DatabasePath=Expand-AVPath ([string]$Config.DatabasePath);$frame.TempPath=$temp;$frame.MaxBytes=$MaxBytes;$frame.IncludePUA=$IncludePUA;$frame.Threads=$policy.Threads;$frame.IdleSeconds=[int]$Config.ScanEngineIdleSeconds
        $executable=Join-Path $PSHOME 'pwsh.exe'
        $client=[Remnexa.Worker.Client]::new($executable,(Join-Path $script:AVModuleRoot 'Workers/NativeScan.ps1'),$frame,$policy.MemoryLimit,$policy.CpuRate)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $pauseBaseline=if($PauseControl){$PauseControl.PausedSeconds}else{0}
        while(-not $client.Ready.IsCompleted) {
            $CancellationToken.ThrowIfCancellationRequested()
            if($OnHeartbeat){& $OnHeartbeat ([pscustomobject]@{ElapsedSeconds=$watch.Elapsed.TotalSeconds;ProcessId=$client.ProcessId})|Out-Null}
            $paused=if($PauseControl){$PauseControl.PausedSeconds-$pauseBaseline}else{0}
            if(($watch.Elapsed.TotalSeconds-$paused) -gt [int]$Config.ScanEngineStartupSeconds){throw 'Private engine startup timed out.'}
            [Threading.Thread]::Sleep(100)
        }
        try{$ready=$client.Ready.GetAwaiter().GetResult()}catch{throw ('Private engine startup failed: '+$client.Diagnostics)}
        if((Get-AVEngineFingerprint -Config $Config -Dll $dll -MaxBytes $MaxBytes -IncludePUA $IncludePUA -Mode $Profile.Mode) -cne $key){throw 'Database changed while the private engine was loading.'}
        $script:AVPrivateWorker=[pscustomobject]@{Client=$client;Key=$key;Temp=$temp;Root=$root;Reused=$false;Version=$ready.Version;Threads=$ready.Threads;LoadedUtc=[DateTimeOffset]::UtcNow;MemoryLimit=$policy.MemoryLimit}
        $script:AVPrivateFailure=$null
        return $script:AVPrivateWorker
    }
    catch {
        if(-not $CancellationToken.IsCancellationRequested){$script:AVPrivateFailure=[pscustomobject]@{Key=$key;Until=[DateTimeOffset]::UtcNow.AddMinutes(5)}}
        if($client){$client.Dispose()}
        Remove-AVWorkerTemporaryDirectory -Path $temp -Root $root
        throw
    }
}

function Invoke-AVPrivateScan {
    param($Config,$Status,$Profile,[string]$FileList,[string]$MaxFileSize,[bool]$IncludePUA,[int]$TimeoutSeconds,[scriptblock]$OnOutput,[scriptblock]$OnHeartbeat,[scriptblock]$CaptureFilter,[Threading.CancellationToken]$CancellationToken,$PauseControl=$null)
    try {
    $match=[regex]::Match($MaxFileSize.ToUpperInvariant(),'^(\d+(?:\.\d+)?)([KMG]?)$')
    if(-not $match.Success){throw 'Invalid private-engine file limit.'}
    $factor=switch($match.Groups[2].Value){'K'{1KB};'M'{1MB};'G'{1GB};default{1}}
    $max=[long]([double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)*$factor)
    if($max -lt 1 -or $max -gt 128MB){throw 'The private engine supports configured file limits from 1 byte through 128 MiB. Use ClamScan for larger or unlimited limits.'}
    $engine=Start-AVPrivateWorker -Config $Config -Status $Status -Profile $Profile -MaxBytes $max -IncludePUA $IncludePUA -OnHeartbeat $OnHeartbeat -CancellationToken $CancellationToken -PauseControl $PauseControl
    }catch{if(-not $CancellationToken.IsCancellationRequested){$_.Exception.Data['AVWorkerStartupFailed']=$true};throw}
    $policy=Get-AVWorkerPolicy $Profile
    $threads=[Math]::Min($engine.Threads,$policy.Threads)
    $engine.Client.SetPriority($Profile.ProcessPriority)
    $watch=[Diagnostics.Stopwatch]::StartNew();$batch=$null
    $pauseBaseline=if($PauseControl){$PauseControl.PausedSeconds}else{0}
    $pending=[Collections.Generic.SortedDictionary[int,object]]::new();$next=1;$exitCode=0
    $evidence=[Text.StringBuilder]::new()
    try {
        $batch=$engine.Client.BeginBatch($FileList,$threads)
        while(-not $batch.Completed -or $batch.QueuedResults -gt 0) {
            $CancellationToken.ThrowIfCancellationRequested()
            $paused=if($PauseControl){$PauseControl.PausedSeconds-$pauseBaseline}else{0}
            if(($watch.Elapsed.TotalSeconds-$paused) -gt $TimeoutSeconds){throw 'Private scan exceeded its timeout.'}
            $reply=$batch.Take(50)
            if($reply){$pending.Add($reply.Id,$reply)}
            while($pending.ContainsKey($next)) {
                $row=$pending[$next];[void]$pending.Remove($next)
                $text=if($row.Code -eq 1){$row.Signature+' FOUND'}elseif($row.Code -eq 2){$row.Message+' ERROR'}else{'OK'}
                $line=$row.Path+': '+$text
                if($OnOutput){& $OnOutput $line Stdout|Out-Null}
                if(-not $CaptureFilter -or (& $CaptureFilter $line Stdout)){[void]$evidence.AppendLine($line)}
                if($evidence.Length -gt 16MB){throw 'Private scan output exceeded its capture limit.'}
                if($row.Code -gt $exitCode){$exitCode=$row.Code}
                $batch.Acknowledge($next);$next++
            }
            if($OnHeartbeat){& $OnHeartbeat ([pscustomobject]@{ElapsedSeconds=$watch.Elapsed.TotalSeconds;ProcessId=$engine.Client.ProcessId})|Out-Null}
        }
        if($batch.Error){throw $batch.Error}
        if($pending.Count -or $next-1 -ne $batch.Submitted){throw 'Private scan lost file replies.'}
        [pscustomobject]@{ExitCode=$exitCode;StandardOutput=$evidence.ToString();StandardError='';Backend='libclamav-private';EngineProcessId=$engine.Client.ProcessId;EngineReused=$engine.Reused;ScanThreads=$threads}
    }
    catch {Stop-ClamAVScanEngine;throw}
    finally {if($batch){$batch.Dispose()}}
}
