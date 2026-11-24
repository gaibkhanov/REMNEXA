Describe 'ClamAV bounded scan performance and cancellation' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:performanceModule=Get-Module Antivirus
        $script:performanceTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ScanTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:performanceTemp 'data'))
        foreach($name in @('one','two','three')){[IO.File]::WriteAllText((Join-Path $script:performanceTemp ('data/'+$name+'.txt')),'benign fixture')}
        $config=Get-AVConfig
        $config.ClamAVPath=Join-Path $script:performanceTemp 'engine';$config.DatabasePath=Join-Path $script:performanceTemp 'database'
        $config.LogPath=Join-Path $script:performanceTemp 'logs';$config.QuarantinePath=Join-Path $script:performanceTemp 'quarantine';$config.ExcludedPaths=@()
        $configPath=Join-Path $script:performanceTemp 'config.json'
        $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
        & $script:performanceModule {
            param($ConfigPath)
            $script:AVConfigPath=$ConfigPath;$script:PerformanceCase='Clean';$script:ScanCalls=0;$script:ScanArguments=@();$script:MemoryKiB=8GB/1KB;$script:Load=20
            Set-RemnexaProgressRendering $false
            function script:Write-AVLog {param($Message,$Level,$Event,$Data)}
            function script:Test-AVAdministrator {return $true}
            function script:Get-AVScanResources {[pscustomobject]@{AvailableMemoryBytes=($script:MemoryKiB*1KB);CpuLoadPercent=$script:Load}}
            function script:Get-ClamAVStatus {
                param($ConfigPath,[switch]$ForScan)
                $config=Get-AVConfig
                [pscustomobject]@{Installed=($script:PerformanceCase -ne 'Missing');Ready=($script:PerformanceCase -ne 'NoDatabase');SignaturesOutdated=$false;ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$config.DatabasePath}
            }
            function script:Invoke-AVNativeProcess {
                param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter,$ProcessPriority,$CancellationToken)
                $script:ScanCalls++;$script:ScanArguments=$ArgumentList
                $list=($ArgumentList|Where-Object{$_ -like '--file-list=*'}).Substring(12)
                $files=@([IO.File]::ReadAllLines($list));$script:ScannedFiles=$files
                $lines=[Collections.Generic.List[string]]::new();$index=0
                foreach($file in $files){
                    $index++
                    if($script:PerformanceCase -eq 'Partial' -and $index -eq 2){continue}
                    $line=$file+': OK'
                    if($script:PerformanceCase -eq 'Limit'){$line=$file+': Heuristics.Limits.Exceeded.MaxFileSize FOUND'}
                    if($script:PerformanceCase -eq 'Cancel'){$line=$file+': Fixture.HarmlessDetection FOUND'}
                    & $OnOutput $line Stdout
                    if($script:PerformanceCase -eq 'Duplicate'){& $OnOutput $line Stdout}
                    if(& $CaptureFilter $line Stdout){$lines.Add($line)}
                    if($script:PerformanceCase -eq 'Cancel'){$script:AVCancellation.Source.Cancel();$CancellationToken.ThrowIfCancellationRequested()}
                    & $OnHeartbeat ([pscustomobject]@{ElapsedSeconds=$index;ProcessId=0})
                }
                $exit=if($script:PerformanceCase -eq 'Limit'){1}elseif($script:PerformanceCase -eq 'Error'){2}elseif($script:PerformanceCase -eq 'UnknownExit'){17}else{0}
                [pscustomobject]@{ExitCode=$exit;StandardOutput=($lines -join "`n");StandardError=''}
            }
        } $configPath
    }
    AfterEach {
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        $path=[IO.Path]::GetFullPath($script:performanceTemp)
        if($path.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $path) -like 'REMNEXA-ScanTest-*'){Remove-Item -LiteralPath $path -Recurse -Force}
    }
    It 'uses one database-loading process and preserves all explicit files across overlapping targets' {
        $data=Join-Path $script:performanceTemp 'data'
        $result=Invoke-ClamAVScan -Path @($data,(Join-Path $data 'one.txt'),$data) -ScanType Custom
        if($result.FilesTotal -ne 3 -or $result.FilesReported -ne 3 -or -not $result.CoverageComplete){throw 'Coverage was lost or duplicated.'}
        & $script:performanceModule {if($script:ScanCalls -ne 1 -or $script:ScanArguments -contains '--verbose' -or $script:ScanArguments -notcontains '--alert-exceeds-max=yes'){throw 'Scan batching or limit visibility regressed.'}}
    }
    It 'ignores duplicate acknowledgements without inflating completion' {
        & $script:performanceModule {$script:PerformanceCase='Duplicate'}
        $result=Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data')
        if($result.FilesReported -ne 3 -or -not $result.CoverageComplete){throw 'Duplicate acknowledgements corrupted coverage.'}
    }
    It 'starts a fresh batched scan after database changes rather than reusing cached clean-file results' {
        $data=Join-Path $script:performanceTemp 'data'
        [void](Invoke-ClamAVScan -Path $data)
        $db=Join-Path $script:performanceTemp 'database';[void][IO.Directory]::CreateDirectory($db)
        [IO.File]::WriteAllText((Join-Path $db 'daily.cld'),'benign simulated updated database metadata')
        [void](Invoke-ClamAVScan -Path $data)
        & $script:performanceModule {if($script:ScanCalls -ne 2 -or $script:ScannedFiles.Count -ne 3){throw 'An updated scan skipped fresh file jobs.'}}
    }
    It 'keeps missing acknowledgements incomplete while submitting every file' {
        & $script:performanceModule {$script:PerformanceCase='Partial'}
        $result=Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data')
        if($result.FilesReported -ne 2 -or $result.FilesUnconfirmed -ne 1 -or $result.CoverageComplete){throw 'Missing acknowledgement became a clean scan.'}
        & $script:performanceModule {if($script:ScannedFiles.Count -ne 3){throw 'A requested scan job disappeared.'}}
    }
    It 'exposes configured size limits as incomplete warnings without quarantining benign files' {
        & $script:performanceModule {$script:PerformanceCase='Limit'}
        $results=@(Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data') -Quarantine)
        if($results.Count -ne 3 -or @($results|Where-Object{ $_.Status -ne 'LimitExceeded' -or $_.Quarantined -or $_.CoverageComplete }).Count){throw 'Size limits were hidden or treated as malware.'}
        foreach($result in $results){if(-not(Test-Path -LiteralPath $result.Path)){throw 'A benign limited file was moved.'}}
    }
    It 'returns an incomplete cancellation before starting any native scanner' {
        $source=[Threading.CancellationTokenSource]::new();$source.Cancel()
        try{$result=Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data') -CancellationToken $source.Token
            if($result.Status -ne 'Cancelled' -or $result.CoverageComplete){throw 'Cancellation was reported as success.'}
            & $script:performanceModule {if($script:ScanCalls){throw 'Pre-cancelled scan started a process.'}}
        }finally{$source.Dispose()}
    }
    It 'retains prior findings on cancellation without automatic quarantine' {
        & $script:performanceModule {$script:PerformanceCase='Cancel'}
        $results=@(Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data') -Quarantine)
        if(@($results|Where-Object Status -eq 'Infected').Count -ne 1 -or @($results|Where-Object Status -eq 'Cancelled').Count -ne 1){throw 'Partial detections or cancellation were lost.'}
        foreach($result in $results){if($result.CoverageComplete -or $result.Quarantined){throw 'Cancelled scan was complete or quarantined.'}}
        if(@(Get-ChildItem (Join-Path $script:performanceTemp 'data') -File).Count -ne 3){throw 'Cancellation changed fixture files.'}
        & $script:performanceModule {if(Get-RemnexaActiveProgress){throw 'Cancelled scan left progress active.'}}
    }
    It 'maps modes to bounded process priorities and reduces priority under memory or CPU pressure' {
        foreach($pair in @(@('Eco','Idle'),@('Balanced','BelowNormal'),@('Fast','Normal'))){
            $profile=Get-ClamAVScanPerformance -Mode $pair[0]
            if($profile.ProcessPriority -ne $pair[1] -or $profile.MaxConcurrentScans -ne 1){throw 'Invalid resource policy.'}
        }
        & $script:performanceModule {$script:MemoryKiB=1GB/1KB}
        if((Get-ClamAVScanPerformance -Mode Fast).ProcessPriority -ne 'Idle'){throw 'Memory pressure was ignored.'}
        $rejected=$false;try{Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data')|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'A second signature database could exhaust scarce memory.'}
        & $script:performanceModule {$script:MemoryKiB=8GB/1KB;$script:Load=95}
        if((Get-ClamAVScanPerformance -Mode Fast).ProcessPriority -ne 'Idle'){throw 'CPU pressure was ignored.'}
    }
    It 'persists valid performance settings atomically and rejects invalid modes' {
        Set-AVConfig -Values @{ScanPerformanceMode='Eco'} -Confirm:$false
        if((Get-AVConfig).ScanPerformanceMode -ne 'Eco'){throw 'Mode was not persisted.'}
        $rejected=$false;try{Set-AVConfig -Values @{ScanPerformanceMode='Unlimited'} -Confirm:$false}catch{$rejected=$true}
        if(-not $rejected -or (Get-AVConfig).ScanPerformanceMode -ne 'Eco'){throw 'Invalid mode was saved.'}
    }
    It 'fails safely for missing engines databases and error return codes' {
        foreach($case in @('Missing','NoDatabase','Error','UnknownExit')){
            & $script:performanceModule {param($Case)$script:PerformanceCase=$Case} $case
            $rejected=$false;try{Invoke-ClamAVScan -Path (Join-Path $script:performanceTemp 'data')|Out-Null}catch{$rejected=$true}
            if(-not $rejected){throw ('Unsafe scan state accepted: '+$case)}
        }
    }
    It 'streams a large flat directory without losing files or following a junction' {
        $data=Join-Path $script:performanceTemp 'data'
        for($i=0;$i -lt 2000;$i++){[IO.File]::WriteAllText((Join-Path $data ($i.ToString()+'.bin')),'benign')}
        $outside=Join-Path $script:performanceTemp 'outside';[void][IO.Directory]::CreateDirectory($outside)
        [IO.File]::WriteAllText((Join-Path $outside 'excluded.txt'),'benign')
        New-Item -ItemType Junction -Path (Join-Path $data 'link') -Target $outside|Out-Null
        $result=Invoke-ClamAVScan -Path $data
        if($result.FilesTotal -ne 2003 -or $result.FilesReported -ne 2003 -or $result.InventorySkipped -ne 1 -or $result.CoverageComplete){throw 'Streaming enumeration lost jobs or followed a link.'}
    }
    It 'blocks another process from scanning or updating the same configured installation' {
        & $script:performanceModule {
            $config=Get-AVConfig;$lease=Enter-AVScanLease $config
            try{
                $name='Global\REMNEXA.ClamAV.Scan.'+(Get-AVUpdateContext $config)
                $code='$mutex=[Threading.Mutex]::new($false,'+"'"+$name+"');"+'try{if($mutex.WaitOne(0)){$mutex.ReleaseMutex();exit 9};exit 0}finally{$mutex.Dispose()}'
                $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
                $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'));$info.UseShellExecute=$false;$info.CreateNoWindow=$true
                foreach($arg in @('-NoProfile','-EncodedCommand',$encoded)){$info.ArgumentList.Add($arg)}
                $process=[Diagnostics.Process]::Start($info)
                try{if(-not $process.WaitForExit(15000) -or $process.ExitCode -ne 0){throw 'Concurrent process acquired an active installation.'}}finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
            }finally{$lease.ReleaseMutex();$lease.Dispose()}
        }
    }
    It 'has translated performance and cancellation messages with matching placeholders in every language' {
        $root=Split-Path -Parent $PSScriptRoot
        $de=Get-Content (Join-Path $root 'locales/de.json') -Raw|ConvertFrom-Json -AsHashtable
        foreach($code in @('de','en','es','fr','ru','tr')){
            $text=Get-Content (Join-Path $root ('locales/'+$code+'.json')) -Raw|ConvertFrom-Json -AsHashtable
            foreach($key in @($de.Keys|Where-Object{$_ -like 'AVPerformance*' -or $_ -like 'AVScan*'})){
                if(-not $text.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($text[$key])){throw 'Missing translation.'}
                if((([regex]::Matches($text[$key],'\{\d+\}').Value|Sort-Object)-join ',') -ne (([regex]::Matches($de[$key],'\{\d+\}').Value|Sort-Object)-join ',')){throw 'Different translated placeholders.'}
            }
        }
    }
}

Describe 'Observed native scanner cancellation' {
    It 'cancels a live owned process and confirms process termination' {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Core/NativeProcess.psd1') -Force
        $pidPath=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-Cancel-'+[guid]::NewGuid().ToString('N')+'.txt')
        $source=[Threading.CancellationTokenSource]::new()
        $code='[IO.File]::WriteAllText(' + "'"+$pidPath+"',"+'$PID.ToString());Start-Sleep 60'
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code));$cancelled=$false
        try{
            # Wait for the harmless child to publish readiness. A cold Windows
            # runtime can legitimately take more than 2.5 seconds under disk load;
            # cancelling before startup never exercised live-process cleanup.
            $whenReady={param($Event)if([IO.File]::Exists($pidPath)){$source.Cancel()}}.GetNewClosure()
            try{Invoke-RemnexaNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -CancellationToken $source.Token -OnHeartbeat $whenReady -TimeoutSeconds 15|Out-Null}catch [OperationCanceledException]{$cancelled=$true}
            if(-not $cancelled -or -not(Test-Path $pidPath)){throw 'Live cancellation was not exercised.'}
            $child=Get-Process -Id ([int][IO.File]::ReadAllText($pidPath)) -ErrorAction SilentlyContinue
            if($child){try{if(-not $child.WaitForExit(3000)){throw 'Cancelled child survived.'}}finally{$child.Dispose()}}
        }finally{$source.Dispose();if(Test-Path $pidPath){Remove-Item -LiteralPath $pidPath -Force};Remove-Module NativeProcess -ErrorAction SilentlyContinue}
    }
}
