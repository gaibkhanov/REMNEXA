Describe 'Worker resource thresholds and Windows enforcement' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:resourceModule=Get-Module Antivirus
        & $script:resourceModule {Initialize-AVWorkerTransport}
        $script:resourceClient=$null
    }
    AfterEach {
        try{if($script:resourceClient){$script:resourceClient.Dispose()}}finally{Remove-Module Antivirus -ErrorAction SilentlyContinue}
    }
    It 'refuses cold startup below 2 GiB and selects one thread near the boundary' {
        & $script:resourceModule {
            $script:ObservedMemory=2GB-1
            function script:Get-AVScanResources {[pscustomobject]@{AvailableMemoryBytes=$script:ObservedMemory;CpuLoadPercent=0}}
            if((Get-ClamAVScanPerformance).CanStart){throw 'Cold startup admitted below the threshold.'}
            $script:ObservedMemory=2GB
            $profile=Get-ClamAVScanPerformance
            $policy=Get-AVWorkerPolicy $profile
            if(-not $profile.CanStart -or $policy.Threads -ne 1 -or $policy.MemoryLimit -ne 1536MB){throw 'Low-memory policy is not bounded.'}
            $script:ObservedMemory=4GB-1
            if((Get-AVWorkerPolicy (Get-ClamAVScanPerformance -Mode Fast)).Threads -ne 1){throw 'Parallelism grew under low memory.'}
        }
    }
    It 'requires a live cached engine and at least 512 MiB for warm reuse' {
        & $script:resourceModule {
            $script:AVPrivateWorker=[pscustomobject]@{Client=[pscustomobject]@{Alive=$true}}
            try{
                foreach($entry in @(@((512MB-1),$false),@(512MB,$true),@(1GB,$true))){
                    if((Test-AVWarmWorkerMemory ([pscustomobject]@{AvailableMemoryBytes=$entry[0]})) -ne $entry[1]){throw 'Warm reuse boundary failed.'}
                }
                $script:AVPrivateWorker.Client.Alive=$false
                if(Test-AVWarmWorkerMemory ([pscustomobject]@{AvailableMemoryBytes=8GB})){throw 'Dead worker bypassed memory preflight.'}
            }finally{$script:AVPrivateWorker=$null}
        }
    }
    It 'observes memory CPU and process limits in the actual Windows job without exhausting RAM' {
        foreach($entry in @(@('Eco',2GB),@('Fast',8GB))){
            $profile=[pscustomobject]@{Mode=$entry[0];AvailableMemoryBytes=$entry[1];LogicalCores=8;ResourceConstrained=$false}
            $policy=& $script:resourceModule {param($Profile)Get-AVWorkerPolicy $Profile} $profile
            $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='init';$frame.Version='resources';$frame.Threads=$policy.Threads;$frame.MaxBytes=1MB;$frame.IdleSeconds=15
            $script:resourceClient=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $root 'tests/fixtures/PrivateWorker.ps1'),$frame,$policy.MemoryLimit,$policy.CpuRate)
            if(-not $script:resourceClient.Ready.Wait(20000)){throw 'Resource probe did not start.'}
            $state=$script:resourceClient.Ready.GetAwaiter().GetResult().Message|ConvertFrom-Json
            if($state.MemoryLimit -ne $policy.MemoryLimit -or -not $state.MemoryLimitEnabled -or $state.CpuRate -ne $policy.CpuRate -or -not $state.CpuHardCap -or $state.ActiveProcessLimit -ne 1 -or -not $state.KillOnClose){throw 'Kernel job limits differ from the selected policy.'}
            if($state.ElevatedRole -or -not $state.CurrentUserAllowed -or -not $state.SystemAllowed -or $state.AdministratorsAllowed -or $state.DefaultDaclEntries -ne 2){throw 'Restricted token defaults do not preserve user/SYSTEM access.'}
            $script:resourceClient.Dispose();$script:resourceClient=$null
        }
    }
}
