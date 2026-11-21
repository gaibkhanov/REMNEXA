#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/worker-host-test.json'),
    [switch]$IncludeNativeEngine
)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$report=[ordered]@{
    Passed=$false
    ParentElevated=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Runtime=$PSVersionTable.PSVersion.ToString()
    Stage='TransportCompilation'
    TokenMode=$null
    WorkerStopped=$false
    NativeTests=$null
    Failure=$null
}
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-HostTest-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
$client=$null;$batch=$null
try{
    if(-not('Remnexa.Worker.Client' -as [type])){Add-Type -Path (Join-Path $ProjectRoot 'Antivirus/Private/WorkerTransport.cs')}
    $frame=[Remnexa.Worker.Frame]::new();$frame.Kind='init';$frame.Threads=1;$frame.MaxBytes=1MB;$frame.IdleSeconds=15
    $report.Stage='RestrictedLaunch'
    $client=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $ProjectRoot 'tests/fixtures/PrivateWorker.ps1'),$frame,1536MB,2500)
    $report.TokenMode=$client.TokenMode
    $report.Stage='Handshake'
    if(-not $client.Ready.Wait(20000)){throw 'Worker handshake timed out.'}
    [void]$client.Ready.GetAwaiter().GetResult()
    $report.Stage='ScanRoundTrip'
    $file=Join-Path $workspace 'benign.dat';[IO.File]::WriteAllText($file,'Harmless host validation fixture.')
    $list=Join-Path $workspace 'files.txt';[IO.File]::WriteAllLines($list,[string[]]@($file),[Text.UTF8Encoding]::new($false))
    $batch=$client.BeginBatch($list,1)
    $reply=$batch.Take(10000)
    if(-not $reply -or $reply.Code -ne 0 -or $reply.Path -cne $file){throw 'Worker round trip was not complete and clean.'}
    $batch.Acknowledge($reply.Id)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not $batch.Completed -and $watch.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 20}
    if(-not $batch.Completed -or $batch.Error){throw 'Worker batch did not finish safely.'}
    $batch.Dispose();$batch=$null
    $workerId=$client.ProcessId
    $client.Dispose();$client=$null
    $report.WorkerStopped=-not [bool](Get-Process -Id $workerId -ErrorAction SilentlyContinue)
    if(-not $report.WorkerStopped){throw 'Owned worker survived disposal.'}
    if($IncludeNativeEngine){
        $report.Stage='NativeEngine'
        $nativePath=Join-Path $workspace 'native.json'
        & (Join-Path $ProjectRoot 'tools/Test-ClamAVPrivateEngine.ps1') -ProjectRoot $ProjectRoot -TestStartupCancellation -OutputPath $nativePath|Out-Null
        $report.NativeTests=Get-Content -LiteralPath $nativePath -Raw|ConvertFrom-Json
        if(-not $report.NativeTests.Passed){throw 'Native-engine validation failed.'}
    }
    $report.Passed=$true;$report.Stage='Completed'
}catch{
    $failure=$_.Exception.GetBaseException()
    $report.Failure=[ordered]@{Type=$failure.GetType().FullName;Message=$failure.Message;NativeErrorCode=$(if($failure -is [ComponentModel.Win32Exception]){$failure.NativeErrorCode}else{$null});WorkerExitCode=$(if($client){$client.ExitCode}else{$null});Diagnostics=$(if($client){$client.Diagnostics}else{''})}
}finally{
    try{if($batch){$batch.Dispose()}}finally{if($client){$workerId=$client.ProcessId;$client.Dispose();$report.WorkerStopped=-not [bool](Get-Process -Id $workerId -ErrorAction SilentlyContinue)}}
    if((Split-Path -Leaf $workspace) -match '^REMNEXA-HostTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($workspace,$true)}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    [IO.File]::WriteAllText($OutputPath,($report|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
}
[pscustomobject]$report
