#Requires -Version 7.5
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/independent-native-validation.json'))
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-IndependentNative-'+[guid]::NewGuid().ToString('N'))
$module=$null;$session=$null
try {
    Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
    $module=Get-Module Antivirus;$config=Get-AVConfig;$status=Get-ClamAVStatus
    if(-not $status.Installed){throw 'ClamAV is required for the real-engine test.'}
    foreach($folder in @('Antivirus','Core','locales')){Copy-Item -LiteralPath (Join-Path $ProjectRoot $folder) -Destination (Join-Path $workspace $folder) -Recurse}
    foreach($folder in @('data','database','logs')){[void][IO.Directory]::CreateDirectory((Join-Path $workspace $folder))}
    $override=@'
function Get-ClamAVStatus {
 param($ConfigPath,[switch]$ForScan)
 $config=Get-AVConfig -Path $ConfigPath
 [pscustomobject]@{Installed=$true;Ready=$true;SignaturesOutdated=$false;ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$config.DatabasePath}
}
'@
    [IO.File]::WriteAllText((Join-Path $workspace 'Antivirus/Public/ZZ-Fixture.ps1'),$override)
    $config.ClamAVPath=Split-Path -Parent $status.ClamScanPath;$config.DatabasePath=Join-Path $workspace 'database';$config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine';$config.ExcludedPaths=@()
    $bytes=[Text.Encoding]::UTF8.GetBytes('REMNEXA harmless independent-process custom hash fixture. No malware or EICAR.')
    $hash=[Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $config.DatabasePath 'fixture.hdb'),("{0}:{1}:REMNEXA.IndependentFixture" -f $hash,$bytes.Length)+"`n")
    [IO.File]::WriteAllBytes((Join-Path $workspace 'data/000-match.dat'),$bytes)
    foreach($index in 1..2500){[IO.File]::WriteAllText((Join-Path $workspace ('data/'+$index.ToString('D5')+'.txt')),('Benign fixture. '*300))}
    $configPath=Join-Path $workspace 'config.json'
    $passes=[Collections.Generic.List[object]]::new()
    foreach($backend in @('ClamScan','PrivateWorker')) {
        $config.ScanBackend=$backend;$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
        & $module {param($Path)$script:AVConfigPath=$Path;$script:AVIndependentSession=$null} $configPath
        $ready=Join-Path $workspace ('parent-'+$backend+'.json')
        $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'));$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-File',(Join-Path $ProjectRoot 'tests/fixtures/IndependentScanParent.ps1'),'-ModuleRoot',$workspace,'-ConfigPath',$configPath,'-DataPath',(Join-Path $workspace 'data'),'-ReadyPath',$ready,'-Mode','Detach')){$start.ArgumentList.Add($arg)}
        $parent=[Diagnostics.Process]::Start($start)
        try {
            $out=$parent.StandardOutput.ReadToEndAsync();$err=$parent.StandardError.ReadToEndAsync()
            if(-not $parent.WaitForExit(45000)){throw 'Independent creator did not exit.'}
            if($parent.ExitCode -ne 0){throw ($out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult())}
        }finally{if(-not $parent.HasExited){$parent.Kill($true)};$parent.Dispose()}
        $creator=[IO.File]::ReadAllText($ready)|ConvertFrom-Json
        $session=& $module {Find-AVIndependentSession}
        $scan=Get-ClamAVBackgroundScan
        if($scan.State -notin @('Starting','Running','Pausing') -or -not $scan.Detached){throw 'Real scan did not remain active after creator exit.'}
        $filesAfterExit=$scan.Files;$timer=[Diagnostics.Stopwatch]::StartNew()
        do{$scan=Get-ClamAVBackgroundScan -IncludeResults;if($scan.State -notin @('Starting','Running','Pausing','Paused','Cancelling')){break};Start-Sleep -Milliseconds 100}while($timer.Elapsed.TotalSeconds -lt 90)
        if($scan.State -ne 'Warning' -or $scan.Files -ne 2501 -or $scan.Findings -ne 1 -or @($scan.Results|Where-Object { $_.Status -eq 'Infected' -and $_.CoverageComplete -and -not $_.Quarantined }).Count -ne 1 -or -not(Test-Path -LiteralPath $scan.ReportPath)){throw ('Independent real scan failed: '+($scan|ConvertTo-Json -Depth 5 -Compress))}
        $passes.Add([pscustomobject]@{Backend=$backend;CreatorExited=$true;ScanActiveAfterCreatorExit=$true;FilesAfterCreatorExit=$filesAfterExit;FilesCompleted=$scan.Files;Findings=1;CoverageComplete=$true;ReportPersisted=$true;PausedScanResumedBeforeDetach=$true;NoAutomaticQuarantine=$true})
        Stop-ClamAVBackgroundScan
        $hostProcess=Get-Process -Id $creator.HostId -ErrorAction SilentlyContinue
        if($hostProcess){try{if(-not $hostProcess.WaitForExit(5000)){throw 'Independent host did not release its completed scan.'}}finally{$hostProcess.Dispose()}}
    }
    $report=[pscustomobject]@{Passed=$true;TimeUtc=[DateTimeOffset]::UtcNow.ToString('o');HarmlessCustomSignatures=$true;InstalledDatabasesChanged=$false;Backends=$passes.ToArray()}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding utf8
    $report
}finally{
    if($module){try{Stop-ClamAVBackgroundScan}catch{};Remove-Module Antivirus -ErrorAction SilentlyContinue}
    if($session){$hostProcess=Get-Process -Id ([int]$session.Descriptor.ProcessId) -ErrorAction SilentlyContinue;if($hostProcess){try{if(-not $hostProcess.WaitForExit(5000) -and $hostProcess.StartTime.ToUniversalTime().Ticks -eq [long]$session.Descriptor.StartTicks){$hostProcess.Kill($true);[void]$hostProcess.WaitForExit(5000)}}finally{$hostProcess.Dispose()}}}
    $full=[IO.Path]::GetFullPath($workspace)
    if($full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -match '^REMNEXA-IndependentNative-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}
}
