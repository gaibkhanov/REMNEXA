param([int]$ProcessId,[long]$StartTicks,[string]$SessionDirectory,[string]$Report)
$ErrorActionPreference='Stop'
$result=[ordered]@{Passed=$false;Error='';Samples=0;BlankFrames=0;Paused=$false;Resumed=$false;Cancelled=$false}
try {
    $target=Get-Process -Id $ProcessId -ErrorAction Stop
    try{if($target.StartTime.ToUniversalTime().Ticks -ne $StartTicks){throw 'Unexpected fixture process identity.'}}finally{$target.Dispose()}
    Add-Type -Path (Join-Path $PSScriptRoot 'ScanConsoleProbe.cs')
    [void][Remnexa.Tests.ScanConsoleProbe]::FreeConsole()
    if(-not[Remnexa.Tests.ScanConsoleProbe]::AttachConsole([uint32]$ProcessId)){throw 'Cannot attach to the owned fixture console.'}
    function Snapshot {Get-Content -LiteralPath (Join-Path $SessionDirectory 'status.json') -Raw|ConvertFrom-Json}
    function Wait-State {param([string[]]$States)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        do{$snapshot=Snapshot;if($snapshot.State -in $States){return $snapshot};Start-Sleep -Milliseconds 80}while($timer.Elapsed.TotalSeconds -lt 6)
        throw ('Console key did not reach state: '+($States -join ',')+'; current='+$snapshot.State)
    }
    $mode=[Remnexa.Tests.ScanConsoleProbe]::InputMode()
    if(($mode -band 0x50) -ne 0 -or ($mode -band 0x80) -eq 0){throw 'Quick Edit or mouse input is still enabled.'}
    $result.InputMode=$mode
    [Remnexa.Tests.ScanConsoleProbe]::Click()
    for($sample=0;$sample -lt 20;$sample++){
        $text=[Remnexa.Tests.ScanConsoleProbe]::Text();$result.Samples++
        if($text -notmatch 'REMNEXA' -or $text -notmatch '\[C\]'){$result.BlankFrames++}
        Start-Sleep -Milliseconds 70
    }
    if($result.BlankFrames){throw 'Frame or controls disappeared after a mouse click.'}
    [Remnexa.Tests.ScanConsoleProbe]::Press('P');$paused=Wait-State @('Paused');$result.Paused=$true
    Start-Sleep -Milliseconds 400
    if((Snapshot).Files -ne $paused.Files){throw 'Paused scanner kept processing.'}
    [Remnexa.Tests.ScanConsoleProbe]::Press('R');[void](Wait-State @('Running'));$result.Resumed=$true
    $resumeWatch=[Diagnostics.Stopwatch]::StartNew()
    do{$resumed=Snapshot;if($resumed.Files -gt $paused.Files){break};Start-Sleep -Milliseconds 80}while($resumeWatch.Elapsed.TotalSeconds -lt 6)
    if($resumed.Files -le $paused.Files){throw 'Resume key did not continue processing.'}
    [Remnexa.Tests.ScanConsoleProbe]::Press('C');$cancelled=Wait-State @('Cancelled');$result.Cancelled=$true
    if($cancelled.Findings -ne 1){throw 'Live findings were lost during console cancellation.'}
    $result.Passed=$true
}catch{$result.Error=$_.Exception.Message;throw}
finally{
    if('Remnexa.Tests.ScanConsoleProbe' -as [type]){[void][Remnexa.Tests.ScanConsoleProbe]::FreeConsole()}
    [IO.File]::WriteAllText($Report,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
