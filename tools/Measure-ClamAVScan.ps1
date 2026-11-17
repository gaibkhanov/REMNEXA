[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineRoot,
    [string]$CurrentRoot=(Split-Path -Parent $PSScriptRoot),
    [ValidateRange(100,50000)][int]$FileCount=4000,
    [ValidateRange(1,5)][int]$Repetitions=2,
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/clamav-scan-benchmark.json'),
    [switch]$Worker,[string]$Dataset,[string]$ResultPath
)
$ErrorActionPreference='Stop'
if($Worker) {
    $config=Get-Content (Join-Path $CurrentRoot 'config/antivirus.json') -Raw|ConvertFrom-Json
    $config.ClamAVPath=Join-Path $BaselineRoot 'ClamAV'
    $config.DatabasePath=Join-Path $BaselineRoot 'ClamAV/database'
    $config.LogPath=Join-Path (Split-Path $Dataset) 'logs'
    $config.QuarantinePath=Join-Path (Split-Path $Dataset) 'quarantine'
    $config.ExcludedPaths=@();$config.AutoCheckUpdates=$false
    $configPath=$ResultPath+'.config.json'
    $config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
    Import-Module (Join-Path $CurrentRoot 'Antivirus/Antivirus.psd1') -Force
    $module=Get-Module Antivirus
    & $module {
        param($ConfigPath)
        $script:AVConfigPath=$ConfigPath
        Set-RemnexaProgressRendering $false
        $script:BenchmarkOriginal=(Get-Command Invoke-AVNativeProcess).ScriptBlock
        $script:BenchmarkPriority=(Get-Command Invoke-AVNativeProcess).Parameters.ContainsKey('ProcessPriority')
        $script:BenchmarkPhases=[ordered]@{ScannerSeconds=0;FirstFileSeconds=$null;StatusSeconds=0}
        $script:BenchmarkInventory=(Get-Command New-AVScanFileList).ScriptBlock
        $script:BenchmarkInventoryCancellation=(Get-Command New-AVScanFileList).Parameters.ContainsKey('CancellationToken')
        function script:New-AVScanFileList {
            param($Targets,$Config,$ListPath,$Progress,$CancellationToken=[Threading.CancellationToken]::None,$CancellationControl=$null)
            $timer=[Diagnostics.Stopwatch]::StartNew()
            $params=@{Targets=$Targets;Config=$Config;ListPath=$ListPath;Progress=$Progress}
            if($script:BenchmarkInventoryCancellation){$params.CancellationToken=$CancellationToken;$params.CancellationControl=$CancellationControl}
            $result=& $script:BenchmarkInventory @params
            $script:BenchmarkPhases.InventorySeconds=$timer.Elapsed.TotalSeconds
            return $result
        }
        function script:Invoke-AVNativeProcess {
            param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter,$ProcessPriority='Normal',$CancellationToken=[Threading.CancellationToken]::None)
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $isScan=@($ArgumentList|Where-Object{$_ -like '--file-list=*'}).Count -gt 0
            $originalCallback=$OnOutput;$phases=$script:BenchmarkPhases
            $callback={param($Line,$Stream)
                if($isScan -and $null -eq $phases.FirstFileSeconds -and ($Line.StartsWith('Scanning ') -or $Line -match ': (OK|Empty file|.* FOUND)$')){$phases.FirstFileSeconds=$watch.Elapsed.TotalSeconds}
                if($originalCallback){& $originalCallback $Line $Stream}
            }.GetNewClosure()
            $nativeParameters=@{FilePath=$FilePath;ArgumentList=$ArgumentList;TimeoutSeconds=$TimeoutSeconds;WorkingDirectory=$WorkingDirectory;OnOutput=$callback;OnHeartbeat=$OnHeartbeat;CaptureFilter=$CaptureFilter}
            if($script:BenchmarkPriority){$nativeParameters.ProcessPriority=$ProcessPriority;$nativeParameters.CancellationToken=$CancellationToken}
            $result=& $script:BenchmarkOriginal @nativeParameters
            if($isScan){$script:BenchmarkPhases.ScannerSeconds=$watch.Elapsed.TotalSeconds}else{$script:BenchmarkPhases.StatusSeconds+=$watch.Elapsed.TotalSeconds}
            return $result
        }
    } $configPath
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $results=@(Invoke-ClamAVScan -Path $Dataset -ScanType Custom -ConfigPath $configPath)
    $elapsed=$watch.Elapsed.TotalSeconds
    $phases=& $module {$script:BenchmarkPhases}
    $priority=if($results[0].PSObject.Properties['ProcessPriority']){$results[0].ProcessPriority}else{'Normal'}
    [pscustomobject]@{Seconds=$elapsed;Files=$results[0].FilesReported;CoverageComplete=$results[0].CoverageComplete;FilesPerSecond=$results[0].FilesReported/$elapsed;ProcessPriority=$priority;Phases=$phases}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ResultPath -Encoding utf8
    exit 0
}
if(-not(Test-Path (Join-Path $CurrentRoot 'ClamAV/clamscan.exe'))){throw 'A locally configured ClamAV installation is required. No download is performed.'}
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ScanBench-'+[guid]::NewGuid().ToString('N'))
$dataset=Join-Path $workspace 'data'
[void][IO.Directory]::CreateDirectory($dataset)
$random=[Random]::new(48291)
for($i=0;$i -lt $FileCount;$i++){
    $folder=Join-Path $dataset ('folder{0:D3}' -f [int][Math]::Floor($i/100))
    [void][IO.Directory]::CreateDirectory($folder)
    $bytes=[byte[]]::new(1024+($i%8)*1024);$random.NextBytes($bytes)
    # Ordinary benign data, no executable payloads or EICAR on the host.
    [IO.File]::WriteAllBytes((Join-Path $folder ('file{0:D6}.dat' -f $i)),$bytes)
}
$rows=[Collections.Generic.List[object]]::new()
for($iteration=1;$iteration -le $Repetitions;$iteration++){
    # Alternate order to reduce systematic filesystem-cache bias.
    $variants=if($iteration%2){@('Baseline','Optimized')}else{@('Optimized','Baseline')}
    foreach($variant in $variants){
        $root=if($variant -eq 'Baseline'){$BaselineRoot}else{$CurrentRoot}
        $resultPath=Join-Path $workspace ($variant+$iteration+'.json')
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $CurrentRoot 'runtime/pwsh.exe'))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-File',$PSCommandPath,'-Worker','-BaselineRoot',$CurrentRoot,'-CurrentRoot',$root,'-Dataset',$dataset,'-ResultPath',$resultPath)){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($info);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $samples=[Collections.Generic.Dictionary[int,object]]::new();$peak=[long]0;$watch=[Diagnostics.Stopwatch]::StartNew();$lastDiscovery=[long]-1000
        $ids=[Collections.Generic.HashSet[int]]::new();[void]$ids.Add($process.Id)
        try{
            while(-not $process.HasExited){
                if($watch.Elapsed.TotalSeconds -gt 600){throw 'Benchmark worker exceeded ten minutes.'}
                if($watch.ElapsedMilliseconds-$lastDiscovery -ge 500){
                    foreach($child in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$process.Id))){[void]$ids.Add([int]$child.ProcessId)}
                    $lastDiscovery=$watch.ElapsedMilliseconds
                }
                $workingSet=[long]0
                foreach($id in $ids){try{$sample=[Diagnostics.Process]::GetProcessById($id);$workingSet+=$sample.WorkingSet64;$samples[$id]=[pscustomobject]@{Cpu=$sample.TotalProcessorTime.TotalSeconds;Peak=$sample.PeakWorkingSet64};$sample.Dispose()}catch{}}
                $peak=[Math]::Max($peak,$workingSet)
                [Threading.Thread]::Sleep(100)
            }
            if($process.ExitCode -ne 0){throw ('Benchmark worker failed: '+$stderr.GetAwaiter().GetResult()+' '+$stdout.GetAwaiter().GetResult())}
            $row=Get-Content $resultPath -Raw|ConvertFrom-Json
            $cpu=($samples.Values|Measure-Object Cpu -Sum).Sum
            $row|Add-Member Variant $variant;$row|Add-Member Iteration $iteration
            $row|Add-Member CpuSecondsSampled $cpu
            $row|Add-Member CpuPercentMachineSampled (100*$cpu/($watch.Elapsed.TotalSeconds*[Environment]::ProcessorCount))
            $row|Add-Member PeakWorkingSetMiBSampled ($peak/1MB)
            $rows.Add($row)
            Write-Host ('{0} #{1}: {2:N2}s, {3} files, sampled peak {4:N0} MiB' -f $variant,$iteration,$row.Seconds,$row.Files,$row.PeakWorkingSetMiBSampled)
        }finally{if(-not $process.HasExited){$process.Kill($true);[void]$process.WaitForExit(5000)};$process.Dispose()}
    }
}
$report=[ordered]@{FileCount=$FileCount;Repetitions=$Repetitions;LogicalCores=[Environment]::ProcessorCount;DatasetSeed=48291;DatabaseHashes=@(Get-ChildItem (Join-Path $CurrentRoot 'ClamAV/database') -File|Where-Object Extension -in '.cvd','.cld','.cud'|Get-FileHash -Algorithm SHA256|ForEach-Object{[pscustomobject]@{Name=[IO.Path]::GetFileName($_.Path);Sha256=$_.Hash}});Runs=$rows;Notes='Sequential offline scans of identical benign files; alternating run order; CPU and concurrent working set sampled every 100 ms with child discovery every 500 ms. FirstFileSeconds includes engine loading and the first file, not pure signature-load time. No HDD comparison or process disk-I/O attribution.'}
[void][IO.Directory]::CreateDirectory((Split-Path $OutputPath))
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host ('Result: '+$OutputPath)
