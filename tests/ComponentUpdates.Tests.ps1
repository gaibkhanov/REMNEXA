BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../Antivirus/Antivirus.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '../Core/Updates.psm1') -Force
}
Describe 'Component update security and background lifecycle' {
    It 'starts with an honest unknown state and separates installation caches' {
        $a=Get-RemnexaComponentUpdates -ApplicationRoot (Join-Path $TestDrive 'a') -StateDirectory (Join-Path $TestDrive 'cache')
        $a.Components.Count|Should -Be 4
        @($a.Components|Where-Object Status -ne unknown).Count|Should -Be 0
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            $a=Get-RemnexaUpdatePaths (Join-Path $Root 'a');$b=Get-RemnexaUpdatePaths (Join-Path $Root 'b')
            $a.Context|Should -Not -Be $b.Context
        }
    }
    It 'ignores corrupt or mismatched state rather than offering unverified updates' {
        $cache=Join-Path $TestDrive 'corrupt';[void][IO.Directory]::CreateDirectory($cache)
        [IO.File]::WriteAllText((Join-Path $cache 'state.json'),'{invalid')
        $state=Get-RemnexaComponentUpdates -ApplicationRoot $TestDrive -StateDirectory $cache
        @($state.Components|Where-Object CanInstall).Count|Should -Be 0
    }
    It 'rejects prereleases and metadata from a foreign download source' {
        InModuleScope Updates {
            Mock Invoke-RestMethod {[pscustomobject]@{draft=$false;prerelease=$true;tag_name='v7.8.0-rc.1';assets=@()}}
            {Get-RemnexaOfficialRelease PowerShell}|Should -Throw '*stable*'
            Mock Invoke-RestMethod {[pscustomobject]@{draft=$false;prerelease=$false;tag_name='v7.8.0';assets=@([pscustomobject]@{name='PowerShell-7.8.0-win-x64.zip';browser_download_url='https://example.invalid/runtime.zip';digest=('sha256:'+('a'*64))})}}
            {Get-RemnexaOfficialRelease PowerShell}|Should -Throw '*source*'
        }
    }
    It 'reports the version but blocks an asset without an official SHA256 digest' {
        InModuleScope Updates {
            Mock Invoke-RestMethod {[pscustomobject]@{draft=$false;prerelease=$false;tag_name='v7.8.0';assets=@([pscustomobject]@{name='PowerShell-7.8.0-win-x64.zip';browser_download_url='https://github.com/PowerShell/PowerShell/releases/download/v7.8.0/PowerShell-7.8.0-win-x64.zip';digest=$null})}}
            $result=Get-RemnexaOfficialRelease PowerShell
            $result.Version|Should -Be '7.8.0';$result.CanInstall|Should -BeFalse
        }
    }
    It 'does not mistake a source-only release for an installable Complete app' {
        InModuleScope Updates {
            Mock Invoke-RestMethod {[pscustomobject]@{draft=$false;prerelease=$false;tag_name='v2.3.0';assets=@([pscustomobject]@{name='REMNEXA-2.3.0-source.zip';browser_download_url='https://github.com/gaibkhanov/REMNEXA/releases/download/v2.3.0/REMNEXA-2.3.0-source.zip';digest=('sha256:'+('a'*64))})}}
            (Get-RemnexaOfficialRelease Application).CanInstall|Should -BeFalse
        }
    }
    It 'rejects path traversal before extracting any archive entry' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            $archive=Join-Path $Root 'traversal.zip';$zip=[IO.Compression.ZipFile]::Open($archive,'Create')
            foreach($name in @('safe.txt','../outside.txt')){$writer=[IO.StreamWriter]::new($zip.CreateEntry($name).Open());$writer.Write('harmless');$writer.Dispose()};$zip.Dispose()
            $destination=Join-Path $Root 'extracted'
            {Expand-RemnexaUpdateArchive $archive $destination}|Should -Throw '*Unsafe*'
            Test-Path (Join-Path $destination 'safe.txt')|Should -BeFalse
            Test-Path (Join-Path $Root 'outside.txt')|Should -BeFalse
        }
    }
    It 'preserves a live runtime and pointer when a downloaded archive has the wrong hash' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            $app=Join-Path $Root 'hash-app';$cache=Join-Path $Root 'hash-cache';$stage=Join-Path $Root 'hash-stage'
            [void][IO.Directory]::CreateDirectory((Join-Path $app 'runtime'));[void][IO.Directory]::CreateDirectory($stage)
            [IO.File]::WriteAllText((Join-Path $app 'runtime/pwsh.exe'),'preserved live runtime');[IO.File]::WriteAllText((Join-Path $app 'runtime/active.txt'),'7.7.0')
            $paths=Get-RemnexaUpdatePaths $app $cache;$state=New-RemnexaUpdateState $paths.Context
            $state.Task=@{Id=('a'*32);Status='Preparing';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason=''}
            Mock Get-RemnexaOfficialRelease {@{Version='7.8.0';CanInstall=$true;Digest=('sha256:'+('0'*64));Uri='https://github.com/PowerShell/PowerShell/releases/download/v7.8.0/PowerShell-7.8.0-win-x64.zip'}}
            # Mock transport only; the actual production hash check still runs.
            Mock Receive-AVPackage -ModuleName Antivirus {param($OutFile)[IO.File]::WriteAllText($OutFile,'tampered harmless archive bytes')}
            {Install-RemnexaPowerShellUpdate $paths $state '7.7.0' $stage}|Should -Throw '*checksum*'
            [IO.File]::ReadAllText((Join-Path $app 'runtime/pwsh.exe'))|Should -Be 'preserved live runtime'
            [IO.File]::ReadAllText((Join-Path $app 'runtime/active.txt'))|Should -Be '7.7.0'
        }
    }
    It 'never downloads a PowerShell downgrade' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            Mock Get-RemnexaOfficialRelease {@{Version='7.6.9';CanInstall=$true}}
            Mock Receive-RemnexaUpdateArchive {throw 'A downgrade was downloaded.'}
            $paths=Get-RemnexaUpdatePaths $Root;$state=New-RemnexaUpdateState $paths.Context
            Install-RemnexaPowerShellUpdate $paths $state '7.7.0' $Root|Should -Be Completed
            Should -Invoke Receive-RemnexaUpdateArchive -Times 0
        }
    }
    It 'writes cancellation requests without stopping an installation mid-commit' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            $paths=Get-RemnexaUpdatePaths $Root (Join-Path $Root 'cancel-cache');$state=New-RemnexaUpdateState $paths.Context
            $state.Task=@{Id=('b'*32);Status='Downloading';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=10;Total=100;Reason=''}
            Write-RemnexaUpdateJson $paths.State $state
            Stop-RemnexaComponentTask $Root $paths.Directory|Should -BeTrue
            {Set-RemnexaUpdatePhase $state $paths 'Verifying'}|Should -Throw '*cancelled*'
            $state.Task.Status='Installing'
            {Set-RemnexaUpdatePhase $state $paths 'Installing'}|Should -Not -Throw
        }
    }
    It 'returns promptly while a separate worker is busy and rejects a duplicate task' {
        $app=Join-Path $TestDrive 'background-app';$av=Join-Path $app 'Antivirus';[void][IO.Directory]::CreateDirectory($av)
        [IO.File]::WriteAllText((Join-Path $av 'Antivirus.psd1'),"@{RootModule='Antivirus.psm1';ModuleVersion='1.0.0'}")
        $gateCode=@'
$gate=Join-Path $PSScriptRoot 'release.fixture'
$watch=[Diagnostics.Stopwatch]::StartNew()
while(-not[IO.File]::Exists($gate) -and $watch.Elapsed.TotalSeconds -lt 12){Start-Sleep -Milliseconds 50}
throw 'Isolated fixture: no network or installation.'
'@
        [IO.File]::WriteAllText((Join-Path $av 'Antivirus.psm1'),$gateCode)
        $cache=Join-Path $TestDrive 'background-cache'
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Start-RemnexaComponentTask $app -Component Check -ApplicationVersion '2.2.0' -StateDirectory $cache|Should -BeTrue
        # Gate the worker instead of assuming a fixed Windows process-start time:
        # the foreground must return while the independent task is still blocked.
        Start-RemnexaComponentTask $app -Component Check -ApplicationVersion '2.2.0' -StateDirectory $cache -Force|Should -BeFalse
        $state=Get-RemnexaComponentUpdates $app $cache
        $state.Task.Status|Should -BeIn @('Starting','Checking')
        [IO.File]::WriteAllText((Join-Path $av 'release.fixture'),'release owned fixture')
        $deadline=[Diagnostics.Stopwatch]::StartNew()
        do{Start-Sleep -Milliseconds 100;$state=Get-RemnexaComponentUpdates $app $cache}while($state.Task.Status -ne 'Failed' -and $deadline.Elapsed.TotalSeconds -lt 15)
        $state.Task.Status|Should -Be Failed
        Close-RemnexaComponentSession $app
    }
    It 'reuses a successful 24 hour check and backs off a failed attempt without starting workers' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            $paths=Get-RemnexaUpdatePaths $Root (Join-Path $Root 'interval-state');$state=New-RemnexaUpdateState $paths.Context
            $state.LastCheckUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-RemnexaUpdateJson $paths.State $state
            Start-RemnexaComponentTask $Root -StateDirectory $paths.Directory -ApplicationVersion '2.2.0'|Should -BeFalse
            $state.LastCheckUtc=$null;$state.LastAttemptUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-RemnexaUpdateJson $paths.State $state
            Start-RemnexaComponentTask $Root -StateDirectory $paths.Directory -ApplicationVersion '2.2.0'|Should -BeFalse
        }
    }
    It 'preserves all six translations and matching format placeholders' {
        $root=Split-Path -Parent $PSScriptRoot;$reference=Get-Content (Join-Path $root 'locales/de.json') -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
        foreach($language in @('en','es','fr','ru','tr')){
            $translations=Get-Content (Join-Path $root ('locales/'+$language+'.json')) -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
            foreach($key in @($reference.Keys|Where-Object{$_ -like 'CU*'})){
                $translations[$key]|Should -Not -BeNullOrEmpty
                ([regex]::Matches($translations[$key],'\{\d+\}').Value -join ',')|Should -Be ([regex]::Matches($reference[$key],'\{\d+\}').Value -join ',')
            }
        }
    }
    It 'honors disabled automatic checks without creating a task or making requests' {
        $app=Join-Path $TestDrive 'disabled';[void][IO.Directory]::CreateDirectory((Join-Path $app 'config'))
        [IO.File]::WriteAllText((Join-Path $app 'config/antivirus.json'),'{"AutoCheckUpdates":false}')
        Start-RemnexaComponentTask $app -StateDirectory (Join-Path $app 'cache') -ApplicationVersion '2.2.0'|Should -BeFalse
        Test-Path (Join-Path $app 'cache/state.json')|Should -BeFalse
    }
}
