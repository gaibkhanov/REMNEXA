#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/worker-memory-validation.json')
)
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-MemoryTest-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
$module=Get-Module Antivirus
try{
    $config=Get-AVConfig;$config.ClamAVPath=Join-Path $ProjectRoot 'ClamAV';$config.DatabasePath=Join-Path $ProjectRoot 'ClamAV/database'
    $config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine';$config.ExcludedPaths=@()
    $config.ScanBackend='PrivateWorker';$config.AutoCheckUpdates=$false;$config.DefaultTimeoutSeconds=180
    $configPath=Join-Path $workspace 'config.json';$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
    $file=Join-Path $workspace 'benign.txt';[IO.File]::WriteAllText($file,'Harmless constrained-worker validation. No malware test payload.')
    & $module {
        param($ConfigPath)
        $script:AVConfigPath=$ConfigPath;$script:TestAvailableMemory=[long]1GB
        Set-RemnexaProgressRendering $false
        # Only the resource snapshot is simulated, in this isolated process.
        # Worker memory limits and scans use real Windows APIs and installed data.
        function script:Get-AVScanResources {[pscustomobject]@{AvailableMemoryBytes=$script:TestAvailableMemory;CpuLoadPercent=10}}
    } $configPath
    $refused=$false
    try{Invoke-ClamAVScan -Path $file -ConfigPath $configPath|Out-Null}catch{$refused=$true}
    if(-not $refused -or (Get-ClamAVScanEngineState).Running){throw 'Cold scan below memory threshold was not refused.'}
    & $module {$script:TestAvailableMemory=[long]2GB}
    $cold=@(Invoke-ClamAVScan -Path $file -ConfigPath $configPath -PerformanceMode Balanced)
    $state=Get-ClamAVScanEngineState
    if($cold.Count -ne 1 -or -not $cold[0].CoverageComplete -or $cold[0].ScanThreads -ne 1 -or $state.MemoryLimit -ne 1536MB){throw 'Constrained full-database scan did not complete with one bounded worker.'}
    $process=Get-Process -Id $state.ProcessId
    try{$peak=$process.PeakWorkingSet64;$privateBytes=$process.PrivateMemorySize64}finally{$process.Dispose()}
    $workerId=$state.ProcessId
    & $module {$script:TestAvailableMemory=[long]512MB}
    $warm=@(Invoke-ClamAVScan -Path $file -ConfigPath $configPath -PerformanceMode Balanced)
    if($warm.Count -ne 1 -or -not $warm[0].CoverageComplete -or -not $warm[0].EngineReused -or $warm[0].EngineProcessId -ne $workerId){throw 'Warm reuse at the memory boundary failed.'}
    & $module {$script:TestAvailableMemory=[long](512MB-1)}
    $warmRefused=$false
    try{Invoke-ClamAVScan -Path $file -ConfigPath $configPath|Out-Null}catch{$warmRefused=$true}
    if(-not $warmRefused -or (Get-ClamAVScanEngineState).Running -or (Get-Process -Id $workerId -ErrorAction SilentlyContinue)){throw 'Memory refusal did not stop the owned worker.'}
    $report=[pscustomobject]@{Passed=$true;TestKind='Simulated available-memory snapshots plus real Windows job limits and full installed signatures';IsEightGiBVm=$false;HostMemoryConstrained=$false;ColdBelowTwoGiBRefused=$refused;ColdAtTwoGiBComplete=$cold[0].CoverageComplete;Threads=$cold[0].ScanThreads;JobMemoryLimitBytes=$state.MemoryLimit;PeakWorkingSetBytes=$peak;PrivateBytesAfterColdScan=$privateBytes;WarmAt512MiBComplete=$warm[0].CoverageComplete;WarmBelow512MiBRefused=$warmRefused;OwnedWorkerStopped=$true}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json|Set-Content -LiteralPath $OutputPath -Encoding utf8
    $report
}finally{
    Stop-ClamAVScanEngine;Remove-Module Antivirus -ErrorAction SilentlyContinue
    if((Split-Path -Leaf $workspace) -match '^REMNEXA-MemoryTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($workspace,$true)}
}
