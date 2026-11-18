Describe 'Private scan engine framing and resource policy' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:privateModule=Get-Module Antivirus
        & $script:privateModule {Initialize-AVWorkerTransport}
        $script:privateTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-PrivateTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:privateTemp)
    }
    AfterEach {
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        if($script:privateTemp -and (Split-Path -Leaf $script:privateTemp) -match '^REMNEXA-PrivateTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($script:privateTemp,$true)}
    }
    It 'round trips bounded frames and rejects oversized, truncated and unknown input' {
        $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='file';$frame.Id=7;$frame.Name='Unicode-ü.dat'
        $stream=[IO.MemoryStream]::new()
        try{[Remnexa.Worker.Wire]::Write($stream,$frame);$stream.Position=0;$actual=[Remnexa.Worker.Wire]::Read($stream)
            if($actual.Id -ne 7 -or $actual.Name -cne $frame.Name){throw 'Frame changed.'}
        }finally{$stream.Dispose()}
        foreach($bytes in @([BitConverter]::GetBytes(32769),[byte[]](10,0,0,0,123),([BitConverter]::GetBytes(13)+[Text.Encoding]::UTF8.GetBytes('{"Extra":123}')))){
            $stream=[IO.MemoryStream]::new([byte[]]$bytes);$rejected=$false
            try{try{[Remnexa.Worker.Wire]::Read($stream)|Out-Null}catch{$rejected=$true}}finally{$stream.Dispose()}
            if(-not $rejected){throw 'Untrusted frame accepted.'}
        }
    }
    It 'caps thread counts and resource budgets without starting multiple database processes' {
        & $script:privateModule {
            foreach($entry in @(@('Eco',8GB,1,2500),@('Balanced',8GB,2,5000),@('Fast',8GB,4,8000),@('Fast',3GB,1,8000))){
                $policy=Get-AVWorkerPolicy ([pscustomobject]@{Mode=$entry[0];AvailableMemoryBytes=$entry[1];LogicalCores=8;ResourceConstrained=$false})
                if($policy.Threads -ne $entry[2] -or $policy.CpuRate -ne $entry[3] -or $policy.MemoryLimit -gt 3GB){throw 'Policy exceeded bounds.'}
            }
            $policy=Get-AVWorkerPolicy ([pscustomobject]@{Mode='Fast';AvailableMemoryBytes=8GB;LogicalCores=1;ResourceConstrained=$true})
            if($policy.Threads -ne 1){throw 'Load pressure ignored.'}
        }
    }
    It 'hashes database content including auxiliary signatures despite unchanged length and timestamps' {
        & $script:privateModule {
            param($Temp)
            $db=Join-Path $Temp 'db';[void][IO.Directory]::CreateDirectory($db)
            $dll=Join-Path $Temp 'libclamav.dll';[IO.File]::WriteAllText($dll,'fake library')
            $file=Join-Path $db 'custom.ndb';[IO.File]::WriteAllText($file,'AAAA');$date=[IO.File]::GetLastWriteTimeUtc($file)
            $config=[pscustomobject]@{ClamAVPath=$Temp;DatabasePath=$db}
            $before=Get-AVEngineFingerprint $config $dll 1MB $false Balanced
            [IO.File]::WriteAllText($file,'BBBB');[IO.File]::SetLastWriteTimeUtc($file,$date)
            $after=Get-AVEngineFingerprint $config $dll 1MB $false Balanced
            if($before -ceq $after){throw 'Changed signatures reused a stale engine.'}
        } $script:privateTemp
    }
    It 'limits cleanup to its owned tree and never traverses a junction target' {
        & $script:privateModule {
            param($Temp)
            $worker=Join-Path $Temp ('worker-'+[guid]::NewGuid().ToString('N'))
            $outside=Join-Path $Temp 'outside';[void][IO.Directory]::CreateDirectory($worker);[void][IO.Directory]::CreateDirectory($outside)
            $sentinel=Join-Path $outside 'keep.txt';[IO.File]::WriteAllText($sentinel,'keep')
            $link=Join-Path $worker 'link'
            [void](New-Item -ItemType Junction -Path $link -Target $outside)
            # Windows may refuse a read-only reparse entry. Retention is safer
            # than changing its target's permissions to force cleanup.
            try{Remove-AVWorkerTemporaryDirectory $worker $Temp}catch{Write-Verbose $_.Exception.Message}
            if(-not(Test-Path -LiteralPath $sentinel)){throw 'Cleanup followed the junction.'}
            if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link -Force}
            $blocked=$false;try{Remove-AVWorkerTemporaryDirectory $outside $Temp}catch{$blocked=$true}
            if(-not $blocked){throw 'Caller-selected cleanup root accepted.'}
        } $script:privateTemp
    }
    It 'keeps all engine lifecycle exports and translations available' {
        foreach($command in @('Get-ClamAVScanEngineState','Stop-ClamAVScanEngine')){if(-not(Get-Command $command -ErrorAction SilentlyContinue)){throw 'Missing lifecycle export.'}}
        foreach($language in @('de','en','es','fr','ru','tr')){
            $texts=Get-Content -LiteralPath (Join-Path $root "locales/$language.json") -Raw -Encoding utf8|ConvertFrom-Json
            foreach($key in @('AVWorkerLoading','AVWorkerReuse','AVWorkerFallback')){if([string]::IsNullOrWhiteSpace($texts.$key)){throw 'Missing worker translation.'}}
        }
    }
    It 'orders native replies for the public coverage cursor and emits one result object' {
        & $script:privateModule {
            param($Temp,$Root)
            $script:PeerScript=Join-Path $Root 'tests/fixtures/PrivateWorker.ps1'
            function script:Start-AVPrivateWorker {
                param($Config,$Status,$Profile,$MaxBytes,$IncludePUA,$OnHeartbeat,$CancellationToken)
                $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='init';$frame.Threads=2;$frame.MaxBytes=$MaxBytes;$frame.IdleSeconds=15;$frame.Version='reverse'
                $client=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:PeerScript,$frame,2GB,5000)
                $script:AVPrivateWorker=[pscustomobject]@{Client=$client;Threads=2;Reused=$false;Temp=$null;Root=$null}
                if(-not $client.Ready.Wait(20000)){throw 'Fixture startup timed out.'}
                return $script:AVPrivateWorker
            }
            $paths=@(foreach($i in 1..4){$file=Join-Path $Temp ("file$i.dat");[IO.File]::WriteAllText($file,'benign');$file})
            $list=Join-Path $Temp 'list.txt';[IO.File]::WriteAllLines($list,[string[]]$paths)
            $seen=[Collections.Generic.List[string]]::new()
            $callback={param($Line,$Stream)$seen.Add($Line)}.GetNewClosure()
            $profile=[pscustomobject]@{Mode='Balanced';ProcessPriority='BelowNormal';AvailableMemoryBytes=8GB;LogicalCores=8;ResourceConstrained=$false}
            $result=Invoke-AVPrivateScan -Config ([pscustomobject]@{}) -Status $null -Profile $profile -FileList $list -MaxFileSize 1M -IncludePUA $false -TimeoutSeconds 20 -OnOutput $callback -CaptureFilter {$false} -CancellationToken ([Threading.CancellationToken]::None)
            if($result -is [array] -or $result.ExitCode -ne 0 -or $seen.Count -ne 4){throw 'Scan pipeline leaked values or lost results.'}
            foreach($i in 0..3){if($seen[$i] -cne ($paths[$i]+': OK')){throw 'Coverage cursor received out-of-order paths.'}}
            Stop-ClamAVScanEngine
        } $script:privateTemp $root
    }
}

Describe 'Private scan backend routing without production files' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:routingModule=Get-Module Antivirus
        $script:routingTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-RoutingTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:routingTemp 'engine'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:routingTemp 'data'))
        [IO.File]::WriteAllText((Join-Path $script:routingTemp 'engine/libclamav.dll'),'not an executable library; routing fixture only')
        [IO.File]::WriteAllText((Join-Path $script:routingTemp 'data/one.txt'),'benign')
        $config=Get-AVConfig;$config.ClamAVPath=Join-Path $script:routingTemp 'engine';$config.DatabasePath=Join-Path $script:routingTemp 'db'
        $config.LogPath=Join-Path $script:routingTemp 'logs';$config.QuarantinePath=Join-Path $script:routingTemp 'quarantine';$config.ExcludedPaths=@()
        $script:routingConfig=Join-Path $script:routingTemp 'config.json';$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $script:routingConfig -Encoding utf8
        & $script:routingModule {
            param($Config)
            $script:AVConfigPath=$Config;$script:RouteCase='Startup';$script:CliCalls=0
            Set-RemnexaProgressRendering $false
            function script:Write-AVLog {param($Message,$Level,$Event,$Data)}
            function script:Test-AVAdministrator {return $true}
            function script:Get-AVScanResources {[pscustomobject]@{AvailableMemoryBytes=8GB;CpuLoadPercent=10}}
            function script:Get-ClamAVStatus {
                param($ConfigPath,[switch]$ForScan)
                $config=Get-AVConfig
                [pscustomobject]@{Installed=$true;Ready=$true;SignaturesOutdated=$false;ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$config.DatabasePath}
            }
            function script:Invoke-AVPrivateScan {
                param($Config,$Status,$Profile,$FileList,$MaxFileSize,$IncludePUA,$TimeoutSeconds,$OnOutput,$OnHeartbeat,$CaptureFilter,$CancellationToken)
                if($script:RouteCase -eq 'Success'){
                    foreach($path in [IO.File]::ReadLines($FileList)){& $OnOutput ($path+': OK') Stdout}
                    return [pscustomobject]@{ExitCode=0;StandardOutput='';StandardError='';Backend='libclamav-private';EngineProcessId=42;EngineReused=$true;ScanThreads=2}
                }
                $failure=[IO.IOException]::new('Simulated private engine failure')
                if($script:RouteCase -eq 'Startup'){$failure.Data['AVWorkerStartupFailed']=$true}
                throw $failure
            }
            function script:Invoke-AVNativeProcess {
                param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter,$ProcessPriority,$CancellationToken)
                $script:CliCalls++
                $list=($ArgumentList|Where-Object{$_ -like '--file-list=*'}).Substring(12)
                foreach($path in [IO.File]::ReadLines($list)){& $OnOutput ($path+': OK') Stdout}
                [pscustomobject]@{ExitCode=0;StandardOutput='';StandardError=''}
            }
        } $script:routingConfig
    }
    AfterEach {
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        if((Split-Path -Leaf $script:routingTemp) -match '^REMNEXA-RoutingTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($script:routingTemp,$true)}
    }
    It 'falls back once in Auto only when startup fails before scanning' {
        $result=Invoke-ClamAVScan -Path (Join-Path $script:routingTemp 'data')
        if(-not $result.CoverageComplete -or $result.ScanBackend -ne 'clamscan'){throw 'Safe startup fallback failed.'}
        & $script:routingModule {if($script:CliCalls -ne 1){throw 'Unexpected fallback count.'}}
    }
    It 'reports mid-scan errors without silently starting another scan' {
        & $script:routingModule {$script:RouteCase='MidScan'}
        $rejected=$false;try{Invoke-ClamAVScan -Path (Join-Path $script:routingTemp 'data')|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Worker failure became success.'}
        & $script:routingModule {if($script:CliCalls){throw 'Mid-scan fallback ran.'}}
    }
    It 'does not fall back when PrivateWorker was explicitly required' {
        Set-AVConfig -Values @{ScanBackend='PrivateWorker'} -Path $script:routingConfig
        $rejected=$false;try{Invoke-ClamAVScan -Path (Join-Path $script:routingTemp 'data')|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Required backend silently changed.'}
        & $script:routingModule {if($script:CliCalls){throw 'Forced private scan fell back.'}}
    }
    It 'preserves complete coverage and actual backend metadata after a private scan' {
        & $script:routingModule {$script:RouteCase='Success'}
        $result=Invoke-ClamAVScan -Path (Join-Path $script:routingTemp 'data')
        if(-not $result.CoverageComplete -or $result.ScanBackend -ne 'libclamav-private' -or -not $result.EngineReused -or $result.ScanThreads -ne 2){throw 'Private scan evidence was lost.'}
        & $script:routingModule {if($script:CliCalls){throw 'Private success started a second scanner.'}}
    }
    It 'validates backend names and bounded idle/startup settings' {
        foreach($values in @(@{ScanBackend='Tcp'},@{ScanEngineIdleSeconds=1},@{ScanEngineStartupSeconds=999},@{ScanEngineIdleSeconds='60'})){
            $rejected=$false;try{Set-AVConfig -Values $values -Path $script:routingConfig}catch{$rejected=$true}
            if(-not $rejected){throw 'Invalid backend configuration persisted.'}
        }
    }
}

Describe 'Observed private worker lifecycle and bounded transport' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        if(-not('Remnexa.Worker.Client' -as [type])){Add-Type -Path (Join-Path $root 'Antivirus/Private/WorkerTransport.cs')}
        $script:wireTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-WireTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:wireTemp)
        $script:wireClient=$null;$script:wireBatch=$null
        $script:wireConfig=[Remnexa.Worker.Frame]::new();$script:wireConfig.Kind='init';$script:wireConfig.Threads=2;$script:wireConfig.MaxBytes=1MB;$script:wireConfig.IdleSeconds=15
        $script:wireScript=Join-Path $root 'tests/fixtures/PrivateWorker.ps1'
        $script:wireList=Join-Path $script:wireTemp 'list.txt'
        $paths=@(foreach($i in 1..4){$file=Join-Path $script:wireTemp ("file$i.dat");[IO.File]::WriteAllText($file,'benign');$file})
        [IO.File]::WriteAllLines($script:wireList,[string[]]$paths,[Text.UTF8Encoding]::new($false))
    }
    AfterEach {
        try{if($script:wireBatch){$script:wireBatch.Dispose()}}finally{if($script:wireClient){$script:wireClient.Dispose()}}
        if($script:wireTemp -and (Split-Path -Leaf $script:wireTemp) -match '^REMNEXA-WireTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($script:wireTemp,$true)}
    }
    It 'reuses the same restricted process for successive batches and confirms termination' {
        $script:wireClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:wireScript,$script:wireConfig,2GB,5000)
        if(-not $script:wireClient.Ready.Wait(20000)){throw 'Fixture did not start.'}
        $workerId=$script:wireClient.ProcessId
        if($script:wireClient.TokenMode -ne 'restricted'){throw 'Restricted token not exercised.'}
        foreach($iteration in 1..2){
            $script:wireBatch=$script:wireClient.BeginBatch($script:wireList,2);$count=0;$watch=[Diagnostics.Stopwatch]::StartNew()
            while(-not $script:wireBatch.Completed -or $script:wireBatch.QueuedResults){
                if($watch.Elapsed.TotalSeconds -gt 15){throw 'Fixture batch stalled.'}
                $reply=$script:wireBatch.Take(50);if($reply){$count++;$script:wireBatch.Acknowledge($reply.Id)}
            }
            if($script:wireBatch.Error -or $count -ne 4 -or $script:wireClient.ProcessId -ne $workerId){throw 'Batch results lost or process replaced.'}
            $script:wireBatch.Dispose();$script:wireBatch=$null
        }
        $script:wireClient.Dispose()
        if(Get-Process -Id $workerId -ErrorAction SilentlyContinue){throw 'Owned worker survived cleanup.'}
    }
    It 'bounds out-of-order results and rejects a simultaneous second batch' {
        $script:wireConfig.Version='reverse'
        $script:wireClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:wireScript,$script:wireConfig,2GB,5000)
        [void]$script:wireClient.Ready.Wait(20000)
        $script:wireBatch=$script:wireClient.BeginBatch($script:wireList,2)
        $blocked=$false;try{$script:wireClient.BeginBatch($script:wireList,2)|Out-Null}catch{$blocked=$true}
        if(-not $blocked){throw 'Concurrent batch accepted.'}
        $first=$script:wireBatch.Take(10000);$second=$script:wireBatch.Take(10000)
        if($first.Id -ne 2 -or $second.Id -ne 1){throw 'Out-of-order fixture not exercised.'}
        Start-Sleep -Milliseconds 200
        if($script:wireBatch.Submitted -ne 2){throw 'Reordering queue grew without bounds.'}
        $script:wireBatch.Acknowledge(1);$script:wireBatch.Acknowledge(2)
        foreach($i in 1..2){$reply=$script:wireBatch.Take(10000);if(-not $reply){throw 'Reply lost.'};$script:wireBatch.Acknowledge($reply.Id)}
        $watch=[Diagnostics.Stopwatch]::StartNew();while(-not $script:wireBatch.Completed -and $watch.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 20}
        if(-not $script:wireBatch.Completed -or $script:wireBatch.Error){throw 'Reordered batch failed.'}
    }
    It 'surfaces size limits and unreadable files rather than silently skipping them' {
        $script:wireConfig.MaxBytes=2
        [IO.File]::WriteAllLines($script:wireList,[string[]]@((Join-Path $script:wireTemp 'file1.dat'),(Join-Path $script:wireTemp 'missing.dat')))
        $script:wireClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:wireScript,$script:wireConfig,2GB,5000)
        [void]$script:wireClient.Ready.Wait(20000);$script:wireBatch=$script:wireClient.BeginBatch($script:wireList,2)
        $rows=@(foreach($i in 1..2){$reply=$script:wireBatch.Take(10000);if(-not $reply){throw 'Local warning lost.'};$script:wireBatch.Acknowledge($reply.Id);$reply})
        if(@($rows|Where-Object Code -eq 1).Count -ne 1 -or @($rows|Where-Object Code -eq 2).Count -ne 1){throw 'Limit or read failure hidden.'}
    }
    It 'rejects duplicate native replies and terminates a broken peer' {
        $script:wireConfig.Version='duplicate'
        $script:wireClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:wireScript,$script:wireConfig,2GB,5000)
        [void]$script:wireClient.Ready.Wait(20000);$script:wireBatch=$script:wireClient.BeginBatch($script:wireList,2)
        $watch=[Diagnostics.Stopwatch]::StartNew();while(-not $script:wireBatch.Error -and $watch.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 50}
        if(-not $script:wireBatch.Error){throw 'Duplicate acknowledgement accepted.'}
    }
    It 'aborts a live stalled peer and confirms its job is gone' {
        $script:wireConfig.Version='stall'
        $script:wireClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),$script:wireScript,$script:wireConfig,2GB,5000)
        [void]$script:wireClient.Ready.Wait(20000);$workerId=$script:wireClient.ProcessId
        $script:wireBatch=$script:wireClient.BeginBatch($script:wireList,2)
        Start-Sleep -Milliseconds 200;$script:wireClient.Dispose()
        if(Get-Process -Id $workerId -ErrorAction SilentlyContinue){throw 'Cancelled worker survived.'}
    }
    It 'kills the owned job when its parent terminates abruptly' {
        $pidFile=Join-Path $script:wireTemp 'worker-id.txt'
        $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        foreach($argument in @('-NoProfile','-File',(Join-Path $root 'tests/fixtures/PrivateWorkerOwner.ps1'),'-PidFile',$pidFile)){$start.ArgumentList.Add($argument)}
        $owner=[Diagnostics.Process]::Start($start)
        try{
            $watch=[Diagnostics.Stopwatch]::StartNew()
            while(-not(Test-Path -LiteralPath $pidFile) -and -not $owner.HasExited -and $watch.Elapsed.TotalSeconds -lt 25){Start-Sleep -Milliseconds 100}
            if(-not(Test-Path -LiteralPath $pidFile)){throw 'Owner did not launch the restricted peer.'}
            $workerId=[int][IO.File]::ReadAllText($pidFile)
            # No Kill(entireProcessTree): job-handle closure must do the work.
            $owner.Kill();[void]$owner.WaitForExit(5000)
            $peer=Get-Process -Id $workerId -ErrorAction SilentlyContinue
            if($peer){try{if(-not $peer.WaitForExit(5000)){throw 'Worker survived owner death.'}}finally{$peer.Dispose()}}
        }finally{if(-not $owner.HasExited){$owner.Kill();[void]$owner.WaitForExit(5000)};$owner.Dispose()}
    }
}
