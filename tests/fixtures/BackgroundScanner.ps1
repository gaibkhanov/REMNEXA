# Harmless observed-process fixture, never imports a malware engine.
param([string]$List,[string]$PidFile,[string]$Mode='Clean')
[IO.File]::WriteAllText($PidFile,[string]$PID)
$files=[IO.File]::ReadAllLines($List)
for($index=0;$index -lt $files.Length;$index++) {
    if($index -eq 0){[Console]::WriteLine($files[$index]+': Fixture.Harmless FOUND')}
    else{[Console]::WriteLine($files[$index]+': OK')}
    [Console]::Out.Flush()
    Start-Sleep -Milliseconds 300
    if($Mode -eq 'Fail' -and $index -eq 2){[Console]::Error.WriteLine('Fixture scanner failure');exit 2}
}
exit 1
