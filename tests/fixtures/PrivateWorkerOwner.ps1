param([Parameter(Mandatory)][string]$PidFile)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '../../Antivirus/Private/WorkerTransport.cs')
$config=[Remnexa.Worker.Frame]::new();$config.Kind='init';$config.Threads=1;$config.MaxBytes=1MB;$config.IdleSeconds=15
$client=[Remnexa.Worker.Client]::new((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $PSScriptRoot 'PrivateWorker.ps1'),$config,2GB,5000)
try {
    if(-not $client.Ready.Wait(20000)){throw 'Test peer not ready.'}
    [IO.File]::WriteAllText($PidFile,$client.ProcessId.ToString())
    Start-Sleep -Seconds 90
}finally{$client.Dispose()}
