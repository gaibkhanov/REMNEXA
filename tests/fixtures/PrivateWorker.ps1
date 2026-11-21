# Test-only transport peer. No ClamAV dependency and no production entry point.
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '../../Antivirus/Private/WorkerTransport.cs')
$inputStream=[Console]::OpenStandardInput();$outputStream=[Console]::OpenStandardOutput()
$config=[Remnexa.Worker.Wire]::Read($inputStream)
$reply=[Remnexa.Worker.Frame]::new();$reply.Kind='ready';$reply.Threads=$config.Threads;$reply.Version='fixture'
if($config.Version -eq 'resources'){
    Add-Type -Path (Join-Path $PSScriptRoot 'WorkerResourceProbe.cs')
    $reply.Message=[Remnexa.Tests.WorkerResourceProbe]::Snapshot()
}
[Remnexa.Worker.Wire]::Write($outputStream,$reply)
$buffer=[Collections.Generic.List[object]]::new()
while($true){
    if($config.Version -eq 'idle'){Start-Sleep -Seconds $config.IdleSeconds;exit 0}
    # Normal test peer uses synchronous reads; only the native worker owns its
    # actual asynchronous idle implementation.
    $frame=[Remnexa.Worker.Wire]::Read($inputStream)
    if($frame.Kind -eq 'file'){
        $bytes=[byte[]]::new($frame.Length);[Remnexa.Worker.Wire]::Exact($inputStream,$bytes,$bytes.Length)
        if($config.Version -eq 'stall'){Start-Sleep -Seconds 120}
        $reply=[Remnexa.Worker.Frame]::new();$reply.Kind='result';$reply.Id=$frame.Id;$reply.Code=0
        if($frame.Name -eq 'found.dat'){$reply.Code=1;$reply.Signature="Fixture.Benign`e[31m"}
        if($config.Version -eq 'duplicate'){
            [Remnexa.Worker.Wire]::Write($outputStream,$reply);[Remnexa.Worker.Wire]::Write($outputStream,$reply)
        }elseif($config.Version -eq 'reverse'){
            $buffer.Add($reply)
            if($buffer.Count -eq $config.Threads){for($i=$buffer.Count-1;$i -ge 0;$i--){[Remnexa.Worker.Wire]::Write($outputStream,$buffer[$i])};$buffer.Clear()}
        }else{[Remnexa.Worker.Wire]::Write($outputStream,$reply)}
    }elseif($frame.Kind -eq 'end'){
        for($i=$buffer.Count-1;$i -ge 0;$i--){[Remnexa.Worker.Wire]::Write($outputStream,$buffer[$i])};$buffer.Clear()
        $reply=[Remnexa.Worker.Frame]::new();$reply.Kind='end';$reply.Id=$frame.Id;[Remnexa.Worker.Wire]::Write($outputStream,$reply)
    }else{throw 'Unexpected fixture command.'}
}
