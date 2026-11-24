Describe 'Persisted antivirus scan history' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
        $script:historyModule=Get-Module Antivirus
        $script:historyData=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:historyData)
        $config=Get-AVConfig;$config.LogPath=Join-Path $script:historyData 'logs'
        $script:historyConfig=Join-Path $script:historyData 'config.json'
        $config|ConvertTo-Json -Depth 8|Set-Content $script:historyConfig -Encoding utf8
        $script:historyContext=& $script:historyModule {param($Config)Get-AVUpdateContext (Get-AVConfig -Path $Config)} $script:historyConfig
        function New-HistorySession {
            $directory=Join-Path $script:historyData ('logs/ScanSessions/scan-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($directory)
            $server=@{Protocol=1;ProcessId=$PID;StartTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks;Context=$script:historyContext}
            & $script:historyModule {param($Path,$Value)Write-AVSessionJson $Path $Value} (Join-Path $directory 'server.json') $server
            $directory
        }
        function New-HistoryRecord {
            param([string]$State='Cancelled',[string]$At='2026-11-22T06:43:00Z')
            @{HistoryId=[guid]::NewGuid().ToString('N');State=$State;ScanType='Quick';Files=0;Total=189161;Findings=0;ElapsedSeconds=30;StartedAtUtc='2026-11-22T06:42:30Z';CompletedAtUtc=$At;RecordedAtUtc=$At}
        }
        function Save-HistoryFixture {
            param($Directory,$Record,[switch]$Snapshot)
            $Record.ReportFile='results-'+$Record.HistoryId+'.json'
            $name=if($Snapshot){'status.json'}else{'history-'+$Record.HistoryId+'.json'}
            & $script:historyModule {param($Path,$Value)Write-AVSessionJson $Path $Value} (Join-Path $Directory $name) $Record
        }
    }
    AfterEach {Remove-Module Antivirus -ErrorAction SilentlyContinue}
    It 'returns no history without starting a scan when no sessions exist' {
        @(Get-ClamAVScanHistory -ConfigPath $script:historyConfig).Count|Should -Be 0
    }
    It 'preserves several scans from one reused host and sorts the latest first without duplicates' {
        $directory=New-HistorySession
        $old=New-HistoryRecord -At '2026-11-21T06:43:00Z';Save-HistoryFixture $directory $old
        $latest=New-HistoryRecord -State Warning;Save-HistoryFixture $directory $latest;Save-HistoryFixture $directory $latest -Snapshot
        $entries=@(Get-ClamAVScanHistory -ConfigPath $script:historyConfig)
        $entries.Count|Should -Be 2;$entries[0].Id|Should -Be $latest.HistoryId
        $entries[0].IsLegacy|Should -BeFalse
        @(Get-ClamAVScanHistory -ConfigPath $script:historyConfig -First 1).Count|Should -Be 1
        Test-Path (Join-Path $directory 'status.json')|Should -BeTrue
    }
    It 'reads an old cancelled snapshot using its saved time without inventing start or completion times' {
        $directory=New-HistorySession
        $legacy=@{State='Cancelled';Files=0;Total=189161;Findings=0;ElapsedSeconds=300;ReportFile='results.json'}
        $path=Join-Path $directory 'status.json'
        & $script:historyModule {param($Path,$Value)Write-AVSessionJson $Path $Value} $path $legacy
        [IO.File]::SetLastWriteTimeUtc($path,[datetime]'2026-11-22T06:43:44Z')
        $before=(Get-FileHash $path).Hash
        $entry=Get-ClamAVScanHistory -ConfigPath $script:historyConfig
        $entry.State|Should -Be Cancelled;$entry.IsLegacy|Should -BeTrue;$entry.ScanType|Should -Be Unknown
        $entry.Files|Should -Be 0;$entry.StartedAtUtc|Should -BeNullOrEmpty;$entry.CompletedAtUtc|Should -BeNullOrEmpty
        ([DateTimeOffset]::Parse($entry.RecordedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))|Should -Be '2026-11-22 06:43:44'
        (Get-FileHash $path).Hash|Should -Be $before
    }
    It 'keeps a live scan out of history and marks an abandoned active snapshot as incomplete' {
        $directory=New-HistorySession;$record=New-HistoryRecord -State Running;Save-HistoryFixture $directory $record -Snapshot
        @(Get-ClamAVScanHistory -ConfigPath $script:historyConfig).Count|Should -Be 0
        $server=Get-Content (Join-Path $directory 'server.json') -Raw|ConvertFrom-Json;$server.StartTicks=1
        & $script:historyModule {param($Path,$Value)Write-AVSessionJson $Path $Value} (Join-Path $directory 'server.json') $server
        $entry=Get-ClamAVScanHistory -ConfigPath $script:historyConfig
        $entry.State|Should -Be Failed
        (Get-Content (Join-Path $directory 'status.json') -Raw|ConvertFrom-Json).State|Should -Be Running
    }
    It 'ignores corrupted summaries and a different installation context' {
        $directory=New-HistorySession;$record=New-HistoryRecord;Save-HistoryFixture $directory $record
        [IO.File]::WriteAllText((Join-Path $directory ('history-'+[guid]::NewGuid().ToString('N')+'.json')),'{broken')
        $invalid=New-HistoryRecord;$invalid.Files=-1;Save-HistoryFixture $directory $invalid
        $other=New-HistorySession;$record=New-HistoryRecord;Save-HistoryFixture $other $record
        & $script:historyModule {param($Path)Write-AVSessionJson $Path @{Context='other installation'}} (Join-Path $other 'server.json')
        @(Get-ClamAVScanHistory -ConfigPath $script:historyConfig).Count|Should -Be 1
    }
    It 'does not traverse a linked scan session or accept a report traversal path' {
        $directory=New-HistorySession;$record=New-HistoryRecord;Save-HistoryFixture $directory $record
        $path=Join-Path $directory ('history-'+$record.HistoryId+'.json')
        $record.ReportFile='../private.json'
        & $script:historyModule {param($Path,$Value)Write-AVSessionJson $Path $Value} $path $record
        $entry=Get-ClamAVScanHistory -ConfigPath $script:historyConfig
        $entry.ReportPath|Should -Be (Join-Path $directory 'results.json')
        $link=Join-Path (Split-Path -Parent $directory) ('scan-'+[guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Junction -Path $link -Target $directory)
        try{@(Get-ClamAVScanHistory -ConfigPath $script:historyConfig).Count|Should -Be 1}
        finally{[IO.Directory]::Delete($link)}
    }
}
