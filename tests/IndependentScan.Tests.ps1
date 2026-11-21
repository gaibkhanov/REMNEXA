Describe 'Independent antivirus process lifetime and secure controls' {
    BeforeEach {
        $script:independentRoot=Split-Path -Parent $PSScriptRoot
        $script:independentTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-IndependentTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:independentTemp)
        foreach($folder in @('Antivirus','Core','locales')){Copy-Item -LiteralPath (Join-Path $script:independentRoot $folder) -Destination $script:independentTemp -Recurse}
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/BackgroundOverrides.ps1') -Destination (Join-Path $script:independentTemp 'Antivirus/Public/ZZ-Fixture.ps1')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/BackgroundScanner.ps1') -Destination $script:independentTemp
        foreach($folder in @('data','logs','engine','database')){[void][IO.Directory]::CreateDirectory((Join-Path $script:independentTemp $folder))}
        foreach($index in 1..30){[IO.File]::WriteAllText((Join-Path $script:independentTemp ('data/'+$index+'.txt')),'benign fixture')}
        Import-Module (Join-Path $script:independentRoot 'Antivirus/Antivirus.psd1') -Force
        $config=Get-AVConfig
        $config.ClamAVPath=Join-Path $script:independentTemp 'engine';$config.DatabasePath=Join-Path $script:independentTemp 'database';$config.LogPath=Join-Path $script:independentTemp 'logs';$config.QuarantinePath=Join-Path $script:independentTemp 'quarantine';$config.ScanBackend='ClamScan';$config.ExcludedPaths=@()
        $script:independentConfig=Join-Path $script:independentTemp 'config.json'
        $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $script:independentConfig -Encoding utf8
        $script:independentModule=Get-Module Antivirus
        & $script:independentModule {param($Root,$Config)$script:AVConfigPath=$Config;$script:AVModuleRoot=Join-Path $Root 'Antivirus';$script:AVScanHostWindowStyle='Hidden'} $script:independentTemp $script:independentConfig
        function Wait-Independent {
            param([scriptblock]$Predicate,[int]$Seconds=25)
            $watch=[Diagnostics.Stopwatch]::StartNew()
            do{$scan=Get-ClamAVBackgroundScan -IncludeResults;if(& $Predicate $scan){return $scan};Start-Sleep -Milliseconds 100}while($watch.Elapsed.TotalSeconds -lt $Seconds)
            throw ('Independent state timeout: '+($scan|ConvertTo-Json -Depth 5 -Compress))
        }
        function Start-FixtureCreator {
            param([string]$Mode)
            $ready=Join-Path $script:independentTemp 'creator.json'
            $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'));$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            foreach($arg in @('-NoProfile','-File',(Join-Path $PSScriptRoot 'fixtures/IndependentScanParent.ps1'),'-ModuleRoot',$script:independentTemp,'-ConfigPath',$script:independentConfig,'-DataPath',(Join-Path $script:independentTemp 'data'),'-ReadyPath',$ready,'-Mode',$Mode)){$start.ArgumentList.Add($arg)}
            $process=[Diagnostics.Process]::Start($start)
            try {
                $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
                if(-not $process.WaitForExit(40000)){throw 'Creator did not exit independently.'}
                if($process.ExitCode -ne 0){throw ('Creator failed: '+$out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult())}
            }finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
            [IO.File]::ReadAllText($ready)|ConvertFrom-Json
        }
    }
    AfterEach {
        $session=& $script:independentModule {Find-AVIndependentSession}
        try{Stop-ClamAVBackgroundScan}catch{}
        if($session){
            $owned=Get-Process -Id ([int]$session.Descriptor.ProcessId) -ErrorAction SilentlyContinue
            if($owned){try{if(-not $owned.WaitForExit(5000) -and $owned.StartTime.ToUniversalTime().Ticks -eq [long]$session.Descriptor.StartTicks){$owned.Kill($true);[void]$owned.WaitForExit(5000)}}finally{$owned.Dispose()}}
        }
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        $full=[IO.Path]::GetFullPath($script:independentTemp)
        if($full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -match '^REMNEXA-IndependentTest-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
    }
    It 'resumes a paused scan, survives explicit creator exit, and persists complete results' {
        $creator=Start-FixtureCreator Detach
        if(Get-Process -Id $creator.CreatorId -ErrorAction SilentlyContinue){throw 'Creator is still running.'}
        if(-not (Get-Process -Id $creator.HostId -ErrorAction SilentlyContinue)){throw 'Independent host died with creator.'}
        $active=Get-ClamAVBackgroundScan
        if($active.State -notin @('Running','Starting','Pausing') -or -not $active.Detached){throw 'Detached paused scan did not resume independently.'}
        $end=Wait-Independent {param($s)$s -and $s.State -eq 'Warning'}
        if($end.Files -ne 30 -or $end.Findings -ne 1 -or @($end.Results|Where-Object { $_.Status -eq 'Infected' -and $_.CoverageComplete }).Count -ne 1 -or -not (Test-Path -LiteralPath $end.ReportPath)){throw 'Detached completion lost coverage or results.'}
    }
    It 'continues after an unannounced creator process exit without silently cancelling the scan' {
        [void](Start-FixtureCreator Implicit)
        $end=Wait-Independent {param($s)$s -and $s.State -eq 'Warning'}
        if($end.Files -ne 30 -or $end.Findings -ne 1){throw 'Unannounced exit cancelled the scan.'}
    }
    It 'cancels only when requested and persists incomplete evidence before creator exit' {
        $creator=Start-FixtureCreator Cancel
        $end=Get-ClamAVBackgroundScan -IncludeResults
        if($creator.State -ne 'Cancelled' -or $end.Findings -ne 1 -or @($end.Results|Where-Object Status -eq 'Cancelled').Count -ne 1 -or @($end.Results|Where-Object CoverageComplete).Count){throw 'Explicit exit cancellation lost its incomplete outcome.'}
    }
    It 'rejects untyped RPC and a spoofed server PID while supporting live remote pause and cancel' {
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:independentTemp 'data') -ConfigPath $script:independentConfig)
        [void](Wait-Independent {param($s)$s -and $s.Findings -eq 1})
        $session=& $script:independentModule {Find-AVIndependentSession;Initialize-AVSessionRpc}
        $bad=[ordered]@{Id=[guid]::NewGuid().ToString('N');Action='Execute';Shell='anything'}|ConvertTo-Json -Compress
        $reply=[Remnexa.ScanSession.Rpc]::Send($session.Descriptor.PipeName,$session.Descriptor.ProcessId,$bad,3000)|ConvertFrom-Json
        if($reply.ok){throw 'Untyped control request accepted.'}
        $rejected=$false;try{[void][Remnexa.ScanSession.Rpc]::Send($session.Descriptor.PipeName,([int]$session.Descriptor.ProcessId+1),$bad,3000)}catch{$rejected=$true}
        if(-not $rejected){throw 'Unexpected server PID accepted.'}
        Set-ClamAVBackgroundScan Pause
        $paused=Wait-Independent {param($s)$s.State -eq 'Paused'}
        Start-Sleep -Milliseconds 700
        if((Get-ClamAVBackgroundScan).Files -ne $paused.Files){throw 'Remote pause did not stop work.'}
        Set-ClamAVBackgroundScan Resume
        [void](Wait-Independent {param($s)$s.Files -gt $paused.Files})
        Stop-ClamAVBackgroundScan
        if((Get-ClamAVBackgroundScan).State -ne 'Cancelled'){throw 'Remote cancellation was lost.'}
    }
    It 'kills only its owned CLI scanner if the scan host itself is forcibly closed' {
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:independentTemp 'data') -ConfigPath $script:independentConfig)
        $scan=Wait-Independent {param($s)$s -and $s.Findings -eq 1 -and $s.ScannerProcessId -gt 0}
        $session=& $script:independentModule {Find-AVIndependentSession}
        $hostProcess=Get-Process -Id ([int]$session.Descriptor.ProcessId)
        $scanner=Get-Process -Id $scan.ScannerProcessId
        try {
            if($hostProcess.StartTime.ToUniversalTime().Ticks -ne [long]$session.Descriptor.StartTicks){throw 'Unexpected test host identity.'}
            $hostProcess.Kill();[void]$hostProcess.WaitForExit(5000)
            if(-not $scanner.WaitForExit(5000)){throw 'CLI scanner survived the death of its owning scan host.'}
        }finally{$hostProcess.Dispose();$scanner.Dispose()}
        $failed=Get-ClamAVBackgroundScan
        if($failed.State -ne 'Failed' -or $failed.Findings -ne 1){throw 'Host loss was reported as success or discarded saved findings.'}
    }
}
