BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../Antivirus/Antivirus.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '../Core/Updates.psm1') -Force
}
Describe 'Staged antivirus activation and rollback' {
    BeforeEach {
        $script:fixture=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $app=Join-Path $script:fixture 'app';$clam=Join-Path $app 'ClamAV';$database=Join-Path $clam 'database'
        [void][IO.Directory]::CreateDirectory($database);[void][IO.Directory]::CreateDirectory((Join-Path $app 'config'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:fixture 'stage'))
        [IO.File]::WriteAllText((Join-Path $clam 'clamscan.exe'),'harmless fixture, never executed')
        [IO.File]::WriteAllText((Join-Path $clam 'version.txt'),'1.0.0');[IO.File]::WriteAllText((Join-Path $database 'daily.cld'),'old harmless database')
        $config=Get-AVConfig;$config.ClamAVPath=$clam;$config.DatabasePath=$database
        $config|ConvertTo-Json -Depth 8|Set-Content (Join-Path $app 'config/antivirus.json') -Encoding utf8
    }
    It 'prepares signatures separately and activates them only under the scan lease' {
        InModuleScope Updates -Parameters @{Fixture=$script:fixture} {
            param($Fixture)
            Mock Get-ClamAVStatus {
                param($ConfigPath)
                $config=Get-AVConfig -Path $ConfigPath
                [pscustomobject]@{Ready=$true;Version=([IO.File]::ReadAllText((Join-Path $config.ClamAVPath 'version.txt')))}
            }
            Mock Update-ClamAVSignature {
                param($ConfigPath)
                $config=Get-AVConfig -Path $ConfigPath
                # Updating the staged tree must not change the original files.
                $original=Join-Path (Split-Path -Parent (Split-Path -Parent $ConfigPath)) 'app/ClamAV/database/daily.cld'
                [IO.File]::ReadAllText($original)|Should -Be 'old harmless database'
                [IO.File]::WriteAllText((Join-Path $config.DatabasePath 'daily.cld'),'new harmless database')
                [IO.File]::ReadAllText($original)|Should -Be 'old harmless database'
            }
            Mock Invoke-ClamAVUpdateCheck {}
            Mock Enter-AVScanLease -ModuleName Antivirus {$mutex=[Threading.Mutex]::new();[void]$mutex.WaitOne(0);$mutex}
            $paths=Get-RemnexaUpdatePaths (Join-Path $Fixture 'app') (Join-Path $Fixture 'state')
            $state=New-RemnexaUpdateState $paths.Context;$state.Task=@{Id=('a'*32);Component='Signatures';Status='Preparing';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version=''}
            Install-RemnexaAntivirusUpdate $paths $state (Join-Path $Fixture 'stage')|Should -Be Completed
            [IO.File]::ReadAllText((Join-Path $paths.App 'ClamAV/database/daily.cld'))|Should -Be 'new harmless database'
            Should -Invoke Enter-AVScanLease -ModuleName Antivirus -Times 1
        }
    }
    It 'restores the previous installation when activation verification fails' {
        InModuleScope Updates -Parameters @{Fixture=$script:fixture} {
            param($Fixture)
            Mock Get-ClamAVStatus {
                param($ConfigPath)
                $config=Get-AVConfig -Path $ConfigPath;$version=[IO.File]::ReadAllText((Join-Path $config.ClamAVPath 'version.txt'))
                $activated=$ConfigPath -like '*app*config*antivirus.json' -and $version -eq '1.1.0'
                [pscustomobject]@{Ready=(-not $activated);Version=$version}
            }
            Mock Update-ClamAVEngine {param($ConfigPath)[IO.File]::WriteAllText((Join-Path (Get-AVConfig -Path $ConfigPath).ClamAVPath 'version.txt'),'1.1.0')}
            Mock Enter-AVScanLease -ModuleName Antivirus {$mutex=[Threading.Mutex]::new();[void]$mutex.WaitOne(0);$mutex}
            $paths=Get-RemnexaUpdatePaths (Join-Path $Fixture 'app') (Join-Path $Fixture 'state')
            $state=New-RemnexaUpdateState $paths.Context;$state.Task=@{Id=('b'*32);Component='Antivirus';Status='Preparing';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version=''}
            {Install-RemnexaAntivirusUpdate $paths $state (Join-Path $Fixture 'stage')}|Should -Throw '*verification failed*'
            [IO.File]::ReadAllText((Join-Path $paths.App 'ClamAV/version.txt'))|Should -Be '1.0.0'
            [IO.File]::ReadAllText((Join-Path $paths.App 'ClamAV/database/daily.cld'))|Should -Be 'old harmless database'
        }
    }
    It 'preserves a newer database changed during staging rather than overwriting it' {
        InModuleScope Updates -Parameters @{Fixture=$script:fixture} {
            param($Fixture)
            $paths=Get-RemnexaUpdatePaths (Join-Path $Fixture 'app') (Join-Path $Fixture 'state')
            Mock Get-ClamAVStatus {[pscustomobject]@{Ready=$true;Version='1.0.0'}}
            Mock Update-ClamAVSignature {}
            Mock Enter-AVScanLease -ModuleName Antivirus {$mutex=[Threading.Mutex]::new();[void]$mutex.WaitOne(0);$mutex}
            Mock Get-RemnexaDatabaseFingerprint {if(Test-Path -LiteralPath (Join-Path $paths.App 'changed.flag')){'changed'}else{[IO.File]::WriteAllText((Join-Path $paths.App 'changed.flag'),'fixture');'original'}}
            $state=New-RemnexaUpdateState $paths.Context;$state.Task=@{Id=('c'*32);Component='Signatures';Status='Preparing';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version=''}
            {Install-RemnexaAntivirusUpdate $paths $state (Join-Path $Fixture 'stage')}|Should -Throw '*database_changed_retry*'
            [IO.File]::ReadAllText((Join-Path $paths.App 'ClamAV/database/daily.cld'))|Should -Be 'old harmless database'
        }
    }
}

Describe 'Scan continuation after a background update' {
    It 'records explicit cancellation without a contradictory failure notice or queued scan' {
        InModuleScope Updates -Parameters @{Root=$TestDrive} {
            param($Root)
            Mock Import-Module {}
            Mock Install-RemnexaAntivirusUpdate {throw [OperationCanceledException]::new('owned fixture cancellation')}
            Mock Start-ClamAVBackgroundScan {}
            $app=Join-Path $Root ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($app)
            $paths=Get-RemnexaUpdatePaths $app (Join-Path $app 'cache');$state=New-RemnexaUpdateState $paths.Context
            $id=[guid]::NewGuid().ToString('N')
            $state.Task=@{Id=$id;Component='Signatures';Status='Starting';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version='';PreparedPath='';AfterScanType='Quick';AfterScanPath=@('private fixture path');Language='de';ScanStarted=$false}
            Write-RemnexaUpdateJson $paths.State $state
            Invoke-RemnexaComponentWorker $app $paths.Directory $id '2.2.0' '7.7.0'
            $result=Get-RemnexaComponentUpdates $app $paths.Directory
            $result.Task.Status|Should -Be Cancelled;$result.Task.Reason|Should -Be ''
            @($result.Task.AfterScanPath).Count|Should -Be 0
            Test-Path (Join-Path $paths.Directory ('failure-'+$id+'.txt'))|Should -BeFalse
            Should -Invoke Start-ClamAVBackgroundScan -Times 0
        }
    }
    It 'preserves successful updates when queued scan startup fails <FailScan>' -TestCases @(@{FailScan=$false},@{FailScan=$true}) {
        param($FailScan)
        InModuleScope Updates -Parameters @{Root=$TestDrive;FailScan=$FailScan} {
            param($Root,$FailScan)
            Mock Import-Module {}
            Mock Install-RemnexaAntivirusUpdate {param($Paths,$State,$Stage)$State.Task.Version='1.5.5';'Completed'}
            Mock Get-RemnexaLocalTools {@{PowerShell='7.7.0';Antivirus='1.5.5';Signatures='main:63';Application='2.2.0'}}
            Mock Start-ClamAVBackgroundScan {if($FailScan){throw 'Isolated scan-host busy fixture.'}}
            $app=Join-Path $Root ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($app)
            $paths=Get-RemnexaUpdatePaths $app (Join-Path $app 'cache');$state=New-RemnexaUpdateState $paths.Context
            $id=[guid]::NewGuid().ToString('N')
            $state.Task=@{Id=$id;Component='Signatures';Status='Starting';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version='';PreparedPath='';AfterScanType='Quick';AfterScanPath=@('harmless fixture');Language='de';ScanStarted=$false}
            Write-RemnexaUpdateJson $paths.State $state
            Invoke-RemnexaComponentWorker $app $paths.Directory $id '2.2.0' '7.7.0'
            $result=Get-RemnexaComponentUpdates $app $paths.Directory
            $result.Task.Status|Should -Be Completed
            $result.Task.ScanStarted|Should -Be (-not $FailScan)
            $result.Task.Reason|Should -Be $(if($FailScan){'scan_not_started'}else{''})
            @($result.Task.AfterScanPath).Count|Should -Be 0
            Should -Invoke Start-ClamAVBackgroundScan -Times 1
        }
    }
}

Describe 'Component update console workflows' {
    BeforeEach {
        $script:console=New-Module -ArgumentList (Split-Path -Parent $PSScriptRoot) -ScriptBlock {
            param($Root)
            . (Join-Path $Root 'Core/UpdateConsole.ps1')
            $script:ComponentApplicationRoot=$Root;$script:CleanerVersion='2.2.0';$script:Language='de';$script:ComponentUpdatesAvailable=$true
            $script:Lines=[Collections.Generic.List[string]]::new();$script:Inputs=[Collections.Generic.Queue[string]]::new();$script:Starts=0
            $script:Texts=Get-Content (Join-Path $Root 'locales/de.json') -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
            function T {param($Key,[object[]]$Values=@())$script:Texts[$Key] -f $Values}
            function Write-Host {param($Object,$ForegroundColor)$script:Lines.Add([string]$Object)}
            function Write-Status {param($Message,$Level)$script:Lines.Add([string]$Message)}
            function Read-RemnexaInput {param($Prompt)$script:Inputs.Dequeue()}
            function Clear-RemnexaScreen {} function Show-BrandHeader {} function Stop-ClamAVScanEngine {}
            function Start-RemnexaComponentTask {param($ApplicationRoot,$ApplicationVersion,$Component,$AfterScanType,$AfterScanPath,$Language)$script:Starts++;$true}
            function Format-HistoryTimestamp {param($Timestamp)$Timestamp}
            function Get-AVUpdateStatusText {param($Status)$Status}
            function Get-RemovalHistory {@([pscustomobject]@{Timestamp='2026-11-20T10:00:00Z';ProgramName='harmless app'})}
            function Get-StartupHistory {@()}
            function Get-ClamAVScanHistory {param($First)@([pscustomobject]@{RecordedAtUtc='2026-11-21T10:00:00Z';Files=8;Findings=0;State='Completed'})}
            function Get-RemnexaComponentUpdates {
                @{Components=@(@{Name='PowerShell';InstalledVersion='7.7.0';AvailableVersion='7.8.0';Status='update_available';CanInstall=$true});Task=$null;History=@();Prepared=@{PowerShell='';ApplicationVersion='';ApplicationPath=''}}
            }
        }
    }
    It 'returns to the app without installing when the update confirmation is declined' {
        & $script:console {foreach($value in @('1','0','0')){$script:Inputs.Enqueue($value)};Show-ComponentUpdateCenter;$script:Starts|Should -Be 0}
    }
    It 'queues a confirmed update once and returns immediately to navigation' {
        & $script:console {foreach($value in @('1','J','0')){$script:Inputs.Enqueue($value)};Show-ComponentUpdateCenter;$script:Starts|Should -Be 1}
    }
    It 'shows saved activities in chronological order and labels them as history' {
        & $script:console {
            Show-ComponentActivities @{History=@(@{Component='PowerShell';Outcome='Ready';Timestamp='2026-11-22T10:00:00Z'})}
            $output=$script:Lines -join "`n"
            $output|Should -Match 'gespeicherter Verlauf'
            $output.IndexOf('2026-11-22')|Should -BeLessThan $output.IndexOf('2026-11-21')
            $output.IndexOf('2026-11-21')|Should -BeLessThan $output.IndexOf('2026-11-20')
        }
    }
}
