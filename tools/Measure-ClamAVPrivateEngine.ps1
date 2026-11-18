[CmdletBinding()]
param(
    [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [ValidateRange(10,10000)][int]$FileCount=1000,
    [ValidateRange(1,5)][int]$Repetitions=2,
    [ValidateSet('Both','ClamScan','PrivateWorker')][string]$Backend='Both',
    [ValidateSet('Unknown','SSD','HDD')][string]$DiskType='Unknown',
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/private-engine-benchmark.json')
)
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-PrivateBench-'+[guid]::NewGuid().ToString('N'))
$data=Join-Path $workspace 'data'
[void][IO.Directory]::CreateDirectory($data)
$random=[Random]::new(48291);$bytesTotal=0L
for($i=0;$i -lt $FileCount;$i++){
    $bytes=[byte[]]::new(1024+($i%8)*1024);$random.NextBytes($bytes);$bytesTotal+=$bytes.Length
    [IO.File]::WriteAllBytes((Join-Path $data ('file{0:D6}.dat' -f $i)),$bytes)
}
Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
$module=Get-Module Antivirus
$config=Get-AVConfig
$config.ClamAVPath=Join-Path $ProjectRoot 'ClamAV';$config.DatabasePath=Join-Path $ProjectRoot 'ClamAV/database'
$config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine'
$config.AutoCheckUpdates=$false;$config.ExcludedPaths=@();$config.ScanEngineIdleSeconds=60
$configPath=Join-Path $workspace 'config.json'
$rows=[Collections.Generic.List[object]]::new()
try {
    & $module {
        param($ConfigPath)
        $script:AVConfigPath=$ConfigPath
        Set-RemnexaProgressRendering $false
        $script:BenchNative=(Get-Command Invoke-AVNativeProcess).ScriptBlock
        $script:BenchPrivate=(Get-Command Invoke-AVPrivateScan).ScriptBlock
        $script:BenchSamples=[Collections.Generic.Dictionary[int,object]]::new()
        function script:Save-BenchSample {
            param($Event)
            try{
                $process=[Diagnostics.Process]::GetProcessById($Event.ProcessId)
                $script:BenchSamples[$Event.ProcessId]=[pscustomobject]@{Cpu=$process.TotalProcessorTime.TotalSeconds;Peak=$process.PeakWorkingSet64}
                $process.Dispose()
            }catch{Write-Verbose $_.Exception.Message}
        }
        function script:Invoke-AVNativeProcess {
            param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter,$ProcessPriority,$CancellationToken)
            $sampleCommand=Get-Command Save-BenchSample
            $callback={param($Event) & $sampleCommand $Event;if($OnHeartbeat){& $OnHeartbeat $Event}}.GetNewClosure()
            & $script:BenchNative -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -WorkingDirectory $WorkingDirectory -OnOutput $OnOutput -OnHeartbeat $callback -CaptureFilter $CaptureFilter -ProcessPriority $ProcessPriority -CancellationToken $CancellationToken
        }
        function script:Invoke-AVPrivateScan {
            param($Config,$Status,$Profile,$FileList,$MaxFileSize,$IncludePUA,$TimeoutSeconds,$OnOutput,$OnHeartbeat,$CaptureFilter,$CancellationToken)
            $sampleCommand=Get-Command Save-BenchSample
            $callback={param($Event) & $sampleCommand $Event;if($OnHeartbeat){& $OnHeartbeat $Event}}.GetNewClosure()
            & $script:BenchPrivate -Config $Config -Status $Status -Profile $Profile -FileList $FileList -MaxFileSize $MaxFileSize -IncludePUA $IncludePUA -TimeoutSeconds $TimeoutSeconds -OnOutput $OnOutput -OnHeartbeat $callback -CaptureFilter $CaptureFilter -CancellationToken $CancellationToken
        }
    } $configPath
    foreach($iteration in 1..$Repetitions){
        $variants=if($iteration%2){@('ClamScan','PrivateWorker')}else{@('PrivateWorker','ClamScan')}
        if($Backend -ne 'Both'){$variants=@($Backend)}
        foreach($variant in $variants){
            Stop-ClamAVScanEngine
            $config.ScanBackend=$variant;$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
            $count=if($variant -eq 'PrivateWorker'){2}else{1}
            foreach($pass in 1..$count){
                & $module {$script:BenchSamples.Clear()}
                $cpuStart=0.0
                $state=Get-ClamAVScanEngineState
                if($state.Running){$cpuStart=(Get-Process -Id $state.ProcessId).TotalProcessorTime.TotalSeconds}
                $watch=[Diagnostics.Stopwatch]::StartNew()
                $result=@(Invoke-ClamAVScan -Path $data -ConfigPath $configPath -PerformanceMode Balanced)
                $seconds=$watch.Elapsed.TotalSeconds
                if($result.Count -ne 1 -or -not $result[0].CoverageComplete -or $result[0].FilesReported -ne $FileCount){throw 'Benchmark scan was not complete and clean.'}
                $samples=@(& $module {$script:BenchSamples.Values|ForEach-Object{$_}})
                $cpu=($samples|Measure-Object Cpu -Sum).Sum-$cpuStart
                $peak=($samples|Measure-Object Peak -Maximum).Maximum
                $row=[pscustomobject]@{Iteration=$iteration;Backend=$result[0].ScanBackend;Warm=($variant -eq 'PrivateWorker' -and $pass -eq 2);Seconds=$seconds;Files=$result[0].FilesReported;FilesPerSecond=$FileCount/$seconds;CpuSeconds=$cpu;CpuPercentOfMachine=100*$cpu/($seconds*[Environment]::ProcessorCount);SampledPeakMiB=$peak/1MB;FirstFileSeconds=$result[0].PhaseTimes.FirstFileSeconds;Phases=$result[0].PhaseTimes;Threads=$(if($result[0].PSObject.Properties['ScanThreads']){$result[0].ScanThreads}else{1});EngineReused=$(if($result[0].PSObject.Properties['EngineReused']){$result[0].EngineReused}else{$false})}
                $rows.Add($row);$row|Format-List Iteration,Backend,Warm,Seconds,Files,Threads,EngineReused
                if($variant -eq 'PrivateWorker'){
                    $state=Get-ClamAVScanEngineState
                    if(-not $state.Running -or $state.TokenMode -ne 'restricted'){throw 'A restricted persistent engine was not observed.'}
                    if(@(Get-NetTCPConnection -ErrorAction Stop|Where-Object OwningProcess -eq $state.ProcessId).Count){throw 'Unexpected TCP socket in private worker.'}
                }
            }
        }
    }
    $report=[pscustomobject]@{SchemaVersion=1;Dataset='Seed 48291; harmless random data; 1-8 KiB files';FileCount=$FileCount;Bytes=$bytesTotal;LogicalCores=[Environment]::ProcessorCount;DiskType=$DiskType;EngineVersion='1.5.4';Notes=@('Shared Windows workload; storage type is operator-supplied when known, not auto-detected.','Worker-only sampled peak working set; warm peak includes initialization high-water mark.','CPU and RAM exclude the PowerShell frontend. Warm CPU subtracts pre-scan worker CPU.','Same installed signatures and dataset; alternating backend order. No downloads or quarantine.');Runs=$rows.ToArray()}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding utf8
}finally{
    Stop-ClamAVScanEngine
    Remove-Module Antivirus -ErrorAction SilentlyContinue
    # Only this unique, explicitly constructed fixture directory is removed.
    if((Split-Path -Leaf $workspace) -match '^REMNEXA-PrivateBench-[a-f0-9]{32}$'){[IO.Directory]::Delete($workspace,$true)}
}
