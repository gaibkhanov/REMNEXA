Describe 'ClamAV nonblocking scan management' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:bgModule=Get-Module Antivirus
        $script:bgTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-BackgroundTest-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:bgTemp)
        foreach($folder in @('Antivirus','Core','locales')){Copy-Item -LiteralPath (Join-Path $root $folder) -Destination $script:bgTemp -Recurse}
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/BackgroundOverrides.ps1') -Destination (Join-Path $script:bgTemp 'Antivirus/Public/ZZ-Fixture.ps1')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/BackgroundScanner.ps1') -Destination $script:bgTemp
        foreach($dir in @('data','logs','engine','database')){[void][IO.Directory]::CreateDirectory((Join-Path $script:bgTemp $dir))}
        foreach($index in 1..20){[IO.File]::WriteAllText((Join-Path $script:bgTemp ('data/'+$index+'.txt')),'benign fixture')}
        $config=Get-AVConfig
        $config.ClamAVPath=Join-Path $script:bgTemp 'engine';$config.DatabasePath=Join-Path $script:bgTemp 'database';$config.LogPath=Join-Path $script:bgTemp 'logs'
        $config.QuarantinePath=Join-Path $script:bgTemp 'quarantine';$config.ScanBackend='ClamScan';$config.ExcludedPaths=@()
        $script:bgConfig=Join-Path $script:bgTemp 'config.json'
        $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $script:bgConfig -Encoding utf8
        # Only this parent module routes to the isolated module copy, never production configuration.
        & $script:bgModule {param($Root)$script:AVUseLocalBackground=$true;$script:AVModuleRoot=Join-Path $Root 'Antivirus'} $script:bgTemp
        function Wait-BackgroundState {
            param([scriptblock]$Predicate,[int]$Seconds=20)
            $timer=[Diagnostics.Stopwatch]::StartNew()
            do{$scan=Get-ClamAVBackgroundScan;if(& $Predicate $scan){return $scan};Start-Sleep -Milliseconds 50}while($timer.Elapsed.TotalSeconds -lt $Seconds)
            throw ('Scan state timeout: '+($scan|ConvertTo-Json -Depth 4 -Compress))
        }
    }
    AfterEach {
        Stop-ClamAVBackgroundScan
        $pidFile=Join-Path $script:bgTemp 'logs/scanner.pid'
        if(Test-Path $pidFile){$scannerPid=[int][IO.File]::ReadAllText($pidFile);if(Get-Process -Id $scannerPid -ErrorAction SilentlyContinue){throw 'Owned fixture process survived cleanup.'}}
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        $full=[IO.Path]::GetFullPath($script:bgTemp)
        if($full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -match '^REMNEXA-BackgroundTest-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
    }
    It 'returns promptly, leaves the caller usable, and exposes findings before completion' {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:bgTemp 'data') -ConfigPath $script:bgConfig)
        if($watch.Elapsed.TotalSeconds -gt 3){throw 'Starting a background scan blocked the caller.'}
        $scan=Wait-BackgroundState {param($s)$s -and $s.Findings -eq 1}
        if($scan.State -notin @('Running','Starting') -or $scan.Files -ge $scan.Total -or $scan.Evidence.Count -ne 1){throw 'No live findings were available.'}
        # A real unrelated operation executes while the scanner is alive.
        Import-Module (Join-Path $script:bgTemp 'Core/MenuChoices.psd1') -Force
        if((ConvertFrom-RemnexaMenuChoice -InputText '2' -Maximum 3) -ne 2){throw 'Caller could not perform unrelated work.'}
    }
    It 'pauses the actual owned process, resumes it, and completes without losing detections' {
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:bgTemp 'data') -ConfigPath $script:bgConfig)
        [void](Wait-BackgroundState {param($s)$s.Findings -eq 1})
        Set-ClamAVBackgroundScan -Action Pause
        $paused=Wait-BackgroundState {param($s)$s.State -eq 'Paused'}
        $scanner=Get-Process -Id ([int][IO.File]::ReadAllText((Join-Path $script:bgTemp 'logs/scanner.pid')))
        $cpu=$scanner.TotalProcessorTime.TotalMilliseconds
        Start-Sleep -Milliseconds 1300
        $scanner.Refresh()
        if((Get-ClamAVBackgroundScan).Files -ne $paused.Files -or ($scanner.TotalProcessorTime.TotalMilliseconds-$cpu) -gt 150){throw 'Paused scanner kept processing.'}
        Set-ClamAVBackgroundScan -Action Resume
        $end=Wait-BackgroundState {param($s)$s.State -in @('Completed','Warning','Cancelled','Failed')}
        $result=Get-ClamAVBackgroundScan -IncludeResults
        if($end.State -ne 'Warning' -or $end.Files -ne 20 -or $end.Findings -ne 1 -or @($result.Results|Where-Object Status -eq 'Infected').Count -ne 1){throw ('Resume lost coverage: '+($result|ConvertTo-Json -Depth 5))}
        & $script:bgModule {param($Config)$lease=Enter-AVScanLease (Get-AVConfig -Path $Config);try{if(-not $script:AVBackgroundScan.RunspaceDisposed){throw 'Foreground work retained the background engine host.'}}finally{$lease.ReleaseMutex();$lease.Dispose()}} $script:bgConfig
        if(@((Get-ClamAVBackgroundScan -IncludeResults).Results|Where-Object Status -eq 'Infected').Count -ne 1){throw 'Releasing the background engine discarded completed results.'}
    }
    It 'cancels a paused scan, retains earlier evidence, and releases its installation lease' {
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:bgTemp 'data') -ConfigPath $script:bgConfig)
        [void](Wait-BackgroundState {param($s)$s.Findings -eq 1})
        Set-ClamAVBackgroundScan -Action Pause
        [void](Wait-BackgroundState {param($s)$s.State -eq 'Paused'})
        Stop-ClamAVBackgroundScan
        $scan=Get-ClamAVBackgroundScan -IncludeResults
        if($scan.State -ne 'Cancelled' -or $scan.Findings -ne 1 -or @($scan.Results|Where-Object Status -eq 'Cancelled').Count -ne 1 -or @($scan.Results|Where-Object CoverageComplete).Count){throw 'Cancellation lost evidence or claimed complete coverage.'}
        & $script:bgModule {param($Config)$lease=Enter-AVScanLease (Get-AVConfig -Path $Config);$lease.ReleaseMutex();$lease.Dispose()} $script:bgConfig
    }
    It 'rejects duplicate background work and blocks scans or updates using the same installation' {
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:bgTemp 'data') -ConfigPath $script:bgConfig)
        [void](Wait-BackgroundState {param($s)$s.Findings -eq 1})
        $rejected=$false;try{Start-ClamAVBackgroundScan -ConfigPath $script:bgConfig|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Duplicate background scan accepted.'}
        & $script:bgModule {param($Config)$blocked=$false;try{$lease=Enter-AVScanLease (Get-AVConfig -Path $Config);$lease.ReleaseMutex();$lease.Dispose()}catch{$blocked=$true};if(-not $blocked){throw 'Active scan did not exclude engine writes or competing scans.'}} $script:bgConfig
    }
    It 'reports scanner failures as incomplete while retaining live detections' {
        [IO.File]::WriteAllText((Join-Path $script:bgTemp 'logs/fail'),'fixture')
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $script:bgTemp 'data') -ConfigPath $script:bgConfig)
        $scan=Wait-BackgroundState {param($s)$s.State -eq 'Failed'}
        if($scan.Findings -ne 1 -or -not $scan.Error){throw 'Failure hid evidence or its error.'}
    }
    It 'uses unknown totals before inventory, bounds live evidence, and translates every new message' {
        & $script:bgModule {Initialize-AVBackgroundSupport}
        $control=[Remnexa.Scan.BackgroundControl]::new()
        try {
            if($control.Snapshot().Total -ne -1){throw 'Preparation invented a total.'}
            foreach($index in 1..1005){$control.AddEvidence('fixture', $true)}
            $snap=$control.Snapshot();if($snap.Findings -ne 1005 -or $snap.Evidence.Count -ne 1000 -or $snap.Omitted -ne 5){throw 'Live evidence was not bounded.'}
        }finally{$control.Dispose()}
        $reference=[IO.File]::ReadAllText((Join-Path $script:bgTemp 'locales/de.json'))|ConvertFrom-Json -AsHashtable
        foreach($code in @('de','en','es','fr','ru','tr')){
            $locale=[IO.File]::ReadAllText((Join-Path $script:bgTemp ('locales/'+$code+'.json')))|ConvertFrom-Json -AsHashtable
            foreach($key in @($reference.Keys|Where-Object{$_ -like 'AVBackground*'})){
                if(-not $locale.Contains($key) -or -not $locale[$key]){throw 'Missing background translation.'}
                if((([regex]::Matches($reference[$key],'\{\d+\}').Value|Sort-Object)-join ',') -ne (([regex]::Matches($locale[$key],'\{\d+\}').Value|Sort-Object)-join ',')){throw 'Background translation placeholders differ.'}
            }
        }
    }
}
