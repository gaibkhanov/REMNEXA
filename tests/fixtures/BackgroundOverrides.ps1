# Test-only overrides copied into an isolated Antivirus module by the test suite.
function Get-AVScanResources {[pscustomobject]@{AvailableMemoryBytes=8GB;CpuLoadPercent=10}}
function Test-AVAdministrator {return $true}
function Write-AVLog {param($Message,$Level,$Event,$Data)}
function Get-ClamAVStatus {
    param($ConfigPath,[switch]$ForScan)
    $config=Get-AVConfig -Path $ConfigPath
    [pscustomobject]@{Installed=$true;Ready=$true;SignaturesOutdated=$false;ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$config.DatabasePath}
}
function Invoke-AVNativeProcess {
    param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter,$ProcessPriority,$CancellationToken,$PauseControl)
    $config=Get-AVConfig
    $list=($ArgumentList|Where-Object{$_ -like '--file-list=*'}).Substring(12)
    $mode=if(Test-Path (Join-Path $config.LogPath 'fail')){'Fail'}else{'Clean'}
    Invoke-RemnexaNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-File',(Join-Path $script:AVModuleRoot '../BackgroundScanner.ps1'),'-List',$list,'-PidFile',(Join-Path $config.LogPath 'scanner.pid'),'-Mode',$mode) -TimeoutSeconds 30 -OnOutput $OnOutput -OnHeartbeat $OnHeartbeat -CaptureFilter $CaptureFilter -CancellationToken $CancellationToken -PauseControl $PauseControl
}
