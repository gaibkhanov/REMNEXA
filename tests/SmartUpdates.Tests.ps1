Describe 'ClamAV smart-update metadata and lifecycle' {
    BeforeEach {
        $script:smartRoot=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:smartRoot 'Core/Progress.psd1') -Force
        Set-RemnexaProgressRendering -Enabled $false
        Import-Module (Join-Path $script:smartRoot 'Antivirus/Antivirus.psd1') -Force
        $script:smartModule=Get-Module Antivirus
        $script:smartFixture=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-SmartUpdate-'+[guid]::NewGuid().ToString('N'))
        $script:smartState=Join-Path $script:smartFixture 'state.json'
        $script:smartConfig=Join-Path $script:smartFixture 'config.json'
        $engine=Join-Path $script:smartFixture 'engine'
        $db=Join-Path $script:smartFixture 'database'
        New-Item -ItemType Directory -Path $engine,$db -Force|Out-Null
        foreach($name in @('clamscan.exe','freshclam.exe')){[IO.File]::WriteAllText((Join-Path $engine $name),'not an executable; isolated fixture')}
        foreach($name in @('main','daily','bytecode')){[IO.File]::WriteAllText((Join-Path $db ($name+'.cvd')),('ClamAV-VDB:fixture:10:1:1:hash:signature:builder:0').PadRight(512,' '))}
        $config=[IO.File]::ReadAllText((Join-Path $script:smartRoot 'config/antivirus.json'))|ConvertFrom-Json
        $config.ClamAVPath=$engine;$config.DatabasePath=$db;$config.LogPath=Join-Path $script:smartFixture 'logs';$config.QuarantinePath=Join-Path $script:smartFixture 'quarantine'
        $config|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $script:smartConfig -Encoding utf8
        & $script:smartModule {
            param($Root,$Engine,$Database)
            $script:TestRoot=$Root;$script:TestEngine=$Engine;$script:TestDatabase=$Database
            $script:TestMode='Current';$script:TestVersion='1.5.4';$script:TestLatest='1.5.4'
            $script:EngineQueries=0;$script:DatabaseQueries=0;$script:Backoffs=0;$script:EngineWrites=0;$script:DatabaseWrites=0
            function script:Find-ClamAVInstallation { param($Config) if($script:TestMode -eq 'NotInstalled'){return $null};return $script:TestEngine }
            function script:Invoke-AVNativeProcess { param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory) [pscustomobject]@{ExitCode=0;StandardOutput=('ClamAV '+$script:TestVersion+'/fixture');StandardError=''} }
            function script:Resolve-ClamAVReleaseAsset {
                param($DownloadUri,$TimeoutSeconds)
                $script:EngineQueries++
                if($script:TestMode -eq 'Offline'){throw 'network offline'}
                if($script:TestMode -eq 'Timeout'){throw [TimeoutException]::new('network timeout')}
                if($script:TestMode -eq 'EngineOffline'){throw 'network offline'}
                $version=if($script:TestMode -in @('Engine','Both','MissingHash','WrongSource')){'1.6.0'}elseif($script:TestMode -eq 'Corrupt'){'bad.version'}else{$script:TestLatest}
                $digest=if($script:TestMode -eq 'MissingHash'){''}else{'sha256:'+('a'*64)}
                $uri=if($script:TestMode -eq 'WrongSource'){'https://untrusted.invalid/clamav.zip'}else{'https://github.com/Cisco-Talos/clamav/releases/download/clamav-'+$version+'/clamav-'+$version+'.win.x64.zip'}
                [pscustomobject]@{Version=$version;Digest=$digest;Uri=$uri;Name='clamav.win.x64.zip'}
            }
            function script:Get-AVRemoteDatabaseVersions {
                param($TimeoutSeconds)
                $script:DatabaseQueries++
                if($script:TestMode -eq 'Offline'){throw 'network offline'}
                if($script:TestMode -eq 'Timeout'){throw [TimeoutException]::new('DNS timeout')}
                if($script:TestMode -eq 'CorruptDns'){return @{main=10;daily='bad';bytecode=10}}
                @{main=10;daily=$(if($script:TestMode -in @('Signatures','Both','EngineOffline')){11}else{10});bytecode=10}
            }
            function script:Start-Sleep { param($Milliseconds) $script:Backoffs++ }
            function script:Write-AVLog { param($Message,$Level,$Event,$Data) }
            function script:Get-ClamAVStatus { param($ConfigPath) [pscustomobject]@{Installed=$true;Ready=$true;Version=$script:TestVersion} }
            function script:Update-ClamAVSignature {
                param($ConfigPath)
                $script:DatabaseWrites++
                if($script:TestMode -eq 'UpdateFailure'){throw 'fixture update failure'}
                [IO.File]::WriteAllText((Join-Path $script:TestDatabase 'daily.cvd'),('ClamAV-VDB:fixture:11:1:1:hash:signature:builder:0').PadRight(512,' '))
                Get-ClamAVStatus
            }
        } $script:smartFixture $engine $db
    }

    AfterEach {
        Stop-ClamAVUpdateCheck
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        $full=[IO.Path]::GetFullPath($script:smartFixture)
        if(-not $full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $full) -notlike 'REMNEXA-SmartUpdate-*'){throw 'Unsafe test cleanup.'}
        if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
    }

    It 'does not contact update services when ClamAV is absent' {
        & $script:smartModule {$script:TestMode='NotInstalled'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.status -ne 'not_installed'){throw 'Missing engine was misreported.'}
        & $script:smartModule {if($script:EngineQueries -or $script:DatabaseQueries){throw 'Absent engine caused network calls.'}}
        if(Start-ClamAVUpdateCheck -ConfigPath $script:smartConfig -StatePath $script:smartState){throw 'An unnecessary worker started.'}
    }

    It 'handles offline checks quietly without changing the installed database' {
        $before=(Get-FileHash (Join-Path $script:smartFixture 'database/daily.cvd')).Hash
        & $script:smartModule {$script:TestMode='Offline'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.status -ne 'offline' -or $state.lastSuccessfulCheckUtc){throw 'Offline was reported as fresh.'}
        if((Get-FileHash (Join-Path $script:smartFixture 'database/daily.cvd')).Hash -ne $before){throw 'A check changed signature data.'}
    }

    It 'records genuinely current engine and all three database versions' {
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.status -ne 'current' -or -not $state.lastSuccessfulCheckUtc -or $state.signatures.databases.Count -ne 3){throw 'Current state was not persisted.'}
        $view=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if($view.isStale -or $view.engine.isStale -or $view.signatures.isStale){throw 'Fresh component timestamps were lost.'}
    }

    It 'does not claim a precise local version from conflicting database headers' {
        [IO.File]::WriteAllText((Join-Path $script:smartFixture 'database/daily.cld'),('ClamAV-VDB:fixture:9:1:1:hash:signature:builder:0').PadRight(512,' '))
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        $daily=@($state.signatures.databases|Where-Object name -eq 'daily')[0]
        if($null -ne $daily.installedVersion -or $daily.status -ne 'unknown' -or $state.signatures.status -eq 'current'){throw 'Conflicting database versions were guessed.'}
    }

    It 'detects newer signatures independently of the engine' {
        & $script:smartModule {$script:TestMode='Signatures'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.signatures.status -ne 'update_available' -or $state.engine.updateAvailable){throw 'Signature and engine updates were conflated.'}
    }

    It 'detects a newer official engine without inventing a signature update' {
        & $script:smartModule {$script:TestMode='Engine'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if(-not $state.engine.updateAvailable -or -not $state.engine.canUpdate -or $state.signatures.status -ne 'current'){throw 'Engine availability was incorrect.'}
    }

    It 'records both available updates without installing either' {
        & $script:smartModule {$script:TestMode='Both'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if(-not $state.engine.updateAvailable -or $state.signatures.status -ne 'update_available'){throw 'Both updates were not represented.'}
        & $script:smartModule {if($script:EngineWrites -or $script:DatabaseWrites){throw 'A metadata check installed updates.'}}
    }

    It 'bounds timeout retries and persists an exponential retry deadline' {
        & $script:smartModule {$script:TestMode='Timeout'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.status -ne 'check_failed' -or -not $state.nextRetryUtc){throw 'Timeout did not leave a bounded failure state.'}
        & $script:smartModule {if($script:EngineQueries -ne 2 -or $script:DatabaseQueries -ne 2 -or $script:Backoffs -ne 1){throw 'Retries exceeded the configured bound.'}}
    }

    It 'rejects corrupt online versions rather than claiming a usable update' {
        & $script:smartModule {$script:TestMode='Corrupt'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if($state.status -ne 'check_failed' -or $state.engine.canUpdate){throw 'Corrupt release metadata was accepted.'}
    }

    It 'blocks missing hashes and nonofficial engine package sources' {
        foreach($mode in @('MissingHash','WrongSource')){
            & $script:smartModule {param($Mode)$script:TestMode=$Mode} $mode
            $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S -Force} $script:smartConfig $script:smartState
            if(-not $state.engine.updateAvailable -or $state.engine.canUpdate){throw 'An unverifiable update became installable.'}
        }
    }

    It 'uses semantic prerelease ordering and does not offer downgrades' {
        & $script:smartModule {$script:TestVersion='1.6.0-rc.1';$script:TestLatest='1.6.0'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S} $script:smartConfig $script:smartState
        if(-not $state.engine.updateAvailable){throw 'Stable release was not newer than its prerelease.'}
        & $script:smartModule {$script:TestVersion='2.0.0';$script:TestLatest='1.5.4'}
        $state=& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S -Force} $script:smartConfig $script:smartState
        if($state.engine.updateAvailable -or $state.engine.canUpdate){throw 'An automatic downgrade was offered.'}
        $rejected=$false
        try{Update-ClamAVEngine -ConfigPath $script:smartConfig -Confirm:$false|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'The actual engine updater accepted a downgrade.'}
    }

    It 'reuses the interval cache and lets a forced check bypass it' {
        & $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null;Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null;if($script:EngineQueries -ne 1 -or $script:DatabaseQueries -ne 1){throw 'Fresh metadata was queried twice.'};Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S -Force|Out-Null;if($script:EngineQueries -ne 2){throw 'Force did not bypass the interval.'}} $script:smartConfig $script:smartState
    }

    It 'reuses the retry cooldown after a failed background check' {
        & $script:smartModule {param($C,$S)$script:TestMode='Offline';Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null;Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null;if($script:EngineQueries -ne 2){throw 'A cooldown caused another network attempt.'}} $script:smartConfig $script:smartState
    }

    It 'retries an expired failure cooldown even when an older successful cache is still young' {
        & $script:smartModule {
            param($C,$S)
            $state=Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S
            $state.status='check_failed';$state.nextRetryUtc=[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('o')
            $options=Get-AVUpdateOptions (Get-AVConfig -Path $C)
            if(-not(Test-AVUpdateDue $state $options)){throw 'A failed forced check suppressed its retry for a whole day.'}
        } $script:smartConfig $script:smartState
    }

    It 'does not start a managed write while another metadata lease is held' {
        $lease=& $script:smartModule {param($S)Enter-AVUpdateLease $S} $script:smartState
        $rejected=$false
        try{Invoke-ClamAVManagedUpdate -Component Signatures -ConfigPath $script:smartConfig -StatePath $script:smartState -Confirm:$false|Out-Null}catch{$rejected=$true}finally{$lease.Dispose()}
        if(-not $rejected){throw 'A concurrent metadata transaction was ignored.'}
        & $script:smartModule {if($script:DatabaseWrites){throw 'A signature write ran without the exclusive lease.'}}
    }

    It 'treats corrupt saved metadata as unknown and ages valid states out' {
        [IO.File]::WriteAllText($script:smartState,'{malformed')
        $state=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if(-not $state.isStale -or $state.status -ne 'unknown'){throw 'Corrupt cache was trusted.'}
        & $script:smartModule {param($C,$S)$state=Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S;$old=[DateTimeOffset]::UtcNow.AddHours(-25).ToString('o');$state.lastSuccessfulCheckUtc=$old;$state.engine.checkedUtc=$old;$state.signatures.checkedUtc=$old;Save-AVUpdateState $state $S} $script:smartConfig $script:smartState
        $state=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if(-not $state.isStale -or -not $state.engine.isStale -or -not $state.signatures.isStale){throw 'Old cache remained current.'}
    }

    It 'keeps the previous state intact when atomic replacement is blocked' {
        & $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null} $script:smartConfig $script:smartState
        $before=[IO.File]::ReadAllText($script:smartState)
        $lock=[IO.File]::Open($script:smartState,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $rejected=$false
        try{& $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S -Force|Out-Null} $script:smartConfig $script:smartState}catch{$rejected=$true}finally{$lock.Dispose()}
        if(-not $rejected -or [IO.File]::ReadAllText($script:smartState) -cne $before){throw 'Failed atomic replacement damaged the cache.'}
        if(@(Get-ChildItem -LiteralPath $script:smartFixture -Filter '.updates-*.tmp').Count){throw 'An abandoned state stage remained.'}
    }

    It 'parses the official TXT layout and rejects stale or malformed DNS data' {
        & $script:smartModule {
            $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $versions=ConvertFrom-AVDnsUpdateInfo ('1.5.4:63:28186:'+ $now +':1:90:999:339')
            if($versions.main -ne 63 -or $versions.daily -ne 28186 -or $versions.bytecode -ne 339){throw 'Official database indices were misread.'}
            foreach($text in @('malformed',('1.5.4:63:28186:'+($now-20000)+':1:90:999:339'))){$rejected=$false;try{ConvertFrom-AVDnsUpdateInfo $text|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'Unreliable DNS data was accepted.'}}
        }
    }

    It 'retains a fresh signature result when the independent engine endpoint fails' {
        & $script:smartModule {param($C,$S)$script:TestMode='EngineOffline';Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null} $script:smartConfig $script:smartState
        $state=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if($state.signatures.status -ne 'update_available' -or $state.signatures.isStale -or -not $state.engine.isStale){throw 'Independent component evidence was discarded.'}
    }

    It 'updates only after explicit managed invocation and records confirmed signature success' {
        & $script:smartModule {param($C,$S)$script:TestMode='Signatures';Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null} $script:smartConfig $script:smartState
        Invoke-ClamAVManagedUpdate -Component Signatures -ConfigPath $script:smartConfig -StatePath $script:smartState -Confirm:$false|Out-Null
        $state=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if(-not $state.signatures.lastSuccessfulUpdateUtc -or $state.signatures.status -ne 'current'){throw 'Successful signature update was not checked or recorded.'}
        & $script:smartModule {if($script:DatabaseWrites -ne 1){throw 'Managed update ran more than once.'}}
    }

    It 'leaves an update failure unknown and does not record signature success' {
        & $script:smartModule {param($C,$S)$script:TestMode='Signatures';Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null;$script:TestMode='UpdateFailure'} $script:smartConfig $script:smartState
        $rejected=$false
        try{Invoke-ClamAVManagedUpdate -Component Signatures -ConfigPath $script:smartConfig -StatePath $script:smartState -Confirm:$false|Out-Null}catch{$rejected=$true}
        $state=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState
        if(-not $rejected -or $state.status -ne 'check_failed' -or $state.signatures.lastSuccessfulUpdateUtc){throw 'A failed update was reported successful.'}
    }

    It 'dispatches a slow owned worker without blocking and closes it on stop' {
        $workerDirectory=Join-Path $script:smartFixture 'Workers'
        New-Item -ItemType Directory -Path $workerDirectory|Out-Null
        [IO.File]::WriteAllText((Join-Path $workerDirectory 'UpdateCheck.ps1'),'param($ConfigPath,$StatePath,[switch]$Force); Start-Sleep -Seconds 60')
        & $script:smartModule {param($Root)$script:AVModuleRoot=$Root} $script:smartFixture
        $watch=[Diagnostics.Stopwatch]::StartNew()
        if(-not(Start-ClamAVUpdateCheck -ConfigPath $script:smartConfig -StatePath $script:smartState -Force)){throw 'No test worker started.'}
        if($watch.Elapsed.TotalSeconds -gt 2){throw 'Dispatch blocked on the worker.'}
        $pidOwned=& $script:smartModule {$script:AVUpdateWorker.Process.Id}
        if(-not(Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState).isChecking){throw 'Slow worker was not running during host work.'}
        Stop-ClamAVUpdateCheck
        if(Get-Process -Id $pidOwned -ErrorAction SilentlyContinue){throw 'Owned worker survived normal shutdown.'}
    }

    It 'honors disabled checks and validates configurable timeout limits' {
        $config=Get-Content -LiteralPath $script:smartConfig -Raw|ConvertFrom-Json
        $config.AutoCheckUpdates=$false;$config|ConvertTo-Json|Set-Content -LiteralPath $script:smartConfig -Encoding utf8
        if(Start-ClamAVUpdateCheck -ConfigPath $script:smartConfig -StatePath $script:smartState){throw 'Disabled checks still spawned a worker.'}
        $config.UpdateNetworkTimeoutSeconds=90;$config|ConvertTo-Json|Set-Content -LiteralPath $script:smartConfig -Encoding utf8
        $rejected=$false;try{Start-ClamAVUpdateCheck -ConfigPath $script:smartConfig -StatePath $script:smartState|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'An unbounded timeout was accepted.'}
    }

    It 'does not present an older successful cache as a successful failed forced worker' {
        & $script:smartModule {param($C,$S)Invoke-AVUpdateMetadataCheck -ConfigPath $C -StatePath $S|Out-Null} $script:smartConfig $script:smartState
        $workerDirectory=Join-Path $script:smartFixture 'Workers'
        New-Item -ItemType Directory -Path $workerDirectory|Out-Null
        [IO.File]::WriteAllText((Join-Path $workerDirectory 'UpdateCheck.ps1'),'param($ConfigPath,$StatePath,[switch]$Force); exit 1')
        & $script:smartModule {param($Root)$script:AVModuleRoot=$Root} $script:smartFixture
        [void](Start-ClamAVUpdateCheck -ConfigPath $script:smartConfig -StatePath $script:smartState -Force)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do{$view=Get-ClamAVUpdateState -ConfigPath $script:smartConfig -StatePath $script:smartState;if($view.isChecking){[Threading.Thread]::Sleep(20)}}while($view.isChecking -and $watch.Elapsed.TotalSeconds -lt 5)
        if($view.isChecking -or $view.status -ne 'check_failed' -or -not $view.isStale){throw 'A crashed forced check reused fresh success from an older run.'}
    }
}
