param([string]$ModuleRoot,[string]$ConfigPath,[string]$DataPath,[string]$ReadyPath,[ValidateSet('Detach','Implicit','Cancel')][string]$Mode)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $ModuleRoot 'Antivirus/Antivirus.psd1') -Force
$module=Get-Module Antivirus
& $module {param($Config)$script:AVConfigPath=$Config;$script:AVScanHostWindowStyle='Hidden'} $ConfigPath
[void](Start-ClamAVBackgroundScan -ScanType Custom -Path $DataPath -ConfigPath $ConfigPath)
$watch=[Diagnostics.Stopwatch]::StartNew()
do{$scan=Get-ClamAVBackgroundScan;if($scan -and $scan.Findings -eq 1){break};Start-Sleep -Milliseconds 50}while($watch.Elapsed.TotalSeconds -lt 20)
if(-not $scan -or $scan.Findings -ne 1){throw ('Independent fixture never produced a finding: '+($scan|ConvertTo-Json -Depth 5))}
if($Mode -eq 'Detach'){
    Set-ClamAVBackgroundScan Pause
    do{$scan=Get-ClamAVBackgroundScan;if($scan.State -eq 'Paused'){break};Start-Sleep -Milliseconds 50}while($watch.Elapsed.TotalSeconds -lt 25)
    if($scan.State -ne 'Paused'){throw 'Fixture never paused.'}
    Disconnect-ClamAVBackgroundScan -Resume
}
if($Mode -eq 'Cancel'){Stop-ClamAVBackgroundScan}
$session=& $module {$script:AVIndependentSession}
[pscustomobject]@{HostId=$session.Descriptor.ProcessId;HostTicks=$session.Descriptor.StartTicks;Directory=$session.Directory;State=(Get-ClamAVBackgroundScan).State;CreatorId=$PID}|ConvertTo-Json|Set-Content -LiteralPath $ReadyPath -Encoding utf8
# Intentionally end the creator PowerShell process, not merely its module/runspace.
exit 0
