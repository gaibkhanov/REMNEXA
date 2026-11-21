#Requires -Version 7.5
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/background-scan-native.json'))
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-BackgroundNative-'+[guid]::NewGuid().ToString('N'))
$module=$null
function Wait-ScanState {
    param([scriptblock]$Predicate,[int]$Seconds=60)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{$state=Get-ClamAVBackgroundScan;if(& $Predicate $state){return $state};Start-Sleep -Milliseconds 25}while($watch.Elapsed.TotalSeconds -lt $Seconds)
    throw ('Background native validation timed out: '+($state|ConvertTo-Json -Depth 4 -Compress))
}
try {
    Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
    $module=Get-Module Antivirus
    $config=Get-AVConfig
    $status=Get-ClamAVStatus
    if(-not $status.Installed){throw 'Install ClamAV before running the real-backend test.'}
    foreach($folder in @('Antivirus','Core','locales')){Copy-Item -LiteralPath (Join-Path $ProjectRoot $folder) -Destination (Join-Path $workspace $folder) -Recurse}
    foreach($dir in @('database','data','logs')){[void][IO.Directory]::CreateDirectory((Join-Path $workspace $dir))}
    # The production status reader expects official CVD/CLD databases. Only this
    # test module recognizes the isolated harmless HDB; all scan/process code is unchanged.
    $override=@'
function Get-ClamAVStatus {
    param($ConfigPath,[switch]$ForScan)
    $config=Get-AVConfig -Path $ConfigPath
    [pscustomobject]@{Installed=$true;Ready=$true;SignaturesOutdated=$false;ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$config.DatabasePath}
}
'@
    [IO.File]::WriteAllText((Join-Path $workspace 'Antivirus/Public/ZZ-Fixture.ps1'),$override)
    $config.ClamAVPath=Split-Path -Parent $status.ClamScanPath
    $config.DatabasePath=Join-Path $workspace 'database';$config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine';$config.ExcludedPaths=@()
    $bytes=[Text.Encoding]::UTF8.GetBytes('REMNEXA harmless background scan custom hash fixture. No malware or EICAR.')
    $hash=[Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $config.DatabasePath 'fixture.hdb'),("{0}:{1}:REMNEXA.BackgroundFixture" -f $hash,$bytes.Length)+"`n")
    [IO.File]::WriteAllBytes((Join-Path $workspace 'data/000-match.dat'),$bytes)
    $content='Benign fixture. '*300
    foreach($index in 1..2500){[IO.File]::WriteAllText((Join-Path $workspace ('data/'+$index.ToString('D5')+'.txt')),$content)}
    $configPath=Join-Path $workspace 'config.json'
    & $module {param($Root)$script:AVModuleRoot=Join-Path $Root 'Antivirus'} $workspace
    $passes=[Collections.Generic.List[object]]::new()
    foreach($backend in @('ClamScan','PrivateWorker')){
        $config.ScanBackend=$backend;$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
        $watch=[Diagnostics.Stopwatch]::StartNew()
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $workspace 'data') -ConfigPath $configPath -Language en)
        $startSeconds=$watch.Elapsed.TotalSeconds
        [void](Wait-ScanState {param($s)$s.Findings -eq 1 -and $s.Files -lt $s.Total})
        Set-ClamAVBackgroundScan -Action Pause
        $paused=Wait-ScanState {param($s)$s.State -eq 'Paused'}
        Start-Sleep -Milliseconds 1400
        $still=Get-ClamAVBackgroundScan
        if($still.State -ne 'Paused' -or $still.Files -ne $paused.Files){throw 'Real engine advanced while paused.'}
        Set-ClamAVBackgroundScan -Action Resume
        $end=Wait-ScanState {param($s)$s.State -in @('Completed','Warning','Cancelled','Failed')}
        $full=Get-ClamAVBackgroundScan -IncludeResults
        if($end.State -ne 'Warning' -or $end.Files -ne 2501 -or $end.Findings -ne 1 -or @($full.Results|Where-Object { $_.Status -eq 'Infected' -and $_.CoverageComplete -and -not $_.Quarantined }).Count -ne 1){throw ('Real backend coverage failed: '+($full|ConvertTo-Json -Depth 5 -Compress))}
        $firstProcessId=$end.ScannerProcessId
        $passes.Add([pscustomobject]@{Backend=$backend;StartReturnSeconds=[Math]::Round($startSeconds,3);Files=$end.Files;Findings=$end.Findings;PausedFilesUnchanged=$true;ElapsedSeconds=[Math]::Round($end.ElapsedSeconds,3);CoverageComplete=$true;NoAutomaticQuarantine=$true})
        # Cancel a second, genuinely active backend from the paused state.
        [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $workspace 'data') -ConfigPath $configPath)
        [void](Wait-ScanState {param($s)$s.Findings -eq 1 -and $s.Files -lt $s.Total})
        Set-ClamAVBackgroundScan -Action Pause
        $second=Wait-ScanState {param($s)$s.State -eq 'Paused'}
        if($backend -eq 'PrivateWorker' -and $second.ScannerProcessId -ne $firstProcessId){throw 'The native background engine was not reused.'}
        Stop-ClamAVBackgroundScan
        $cancelled=Get-ClamAVBackgroundScan -IncludeResults
        if($cancelled.State -ne 'Cancelled' -or @($cancelled.Results|Where-Object CoverageComplete).Count){throw 'Real paused cancellation claimed completion.'}
        $passes[$passes.Count-1]|Add-Member CancelWhilePaused $true
        if($backend -eq 'PrivateWorker'){$passes[$passes.Count-1]|Add-Member WarmEngineReused $true}
        if($backend -eq 'PrivateWorker') {
            [void](Start-ClamAVBackgroundScan -ScanType Custom -Path (Join-Path $workspace 'data') -ConfigPath $configPath)
            $idle=Wait-ScanState {param($s)$s.State -in @('Completed','Warning','Failed')}
            if($idle.State -ne 'Warning' -or -not(Get-Process -Id $idle.ScannerProcessId -ErrorAction SilentlyContinue)){throw 'Native engine cache was not alive after completion.'}
            & $module {param($Path)$lease=Enter-AVScanLease (Get-AVConfig -Path $Path);$lease.ReleaseMutex();$lease.Dispose()} $configPath
            if(Get-Process -Id $idle.ScannerProcessId -ErrorAction SilentlyContinue){throw 'Foreground access did not release the background cache.'}
            $passes[$passes.Count-1]|Add-Member IdleEngineReleasedBeforeForeground $true
        }
    }
    $report=[pscustomobject]@{Passed=$true;TimeUtc=[DateTimeOffset]::UtcNow.ToString('o');HarmlessCustomSignatures=$true;ProductionDatabaseChanged=$false;Backends=$passes.ToArray()}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $OutputPath -Encoding utf8
    $report
}finally{
    if($module){Stop-ClamAVBackgroundScan;Remove-Module Antivirus -ErrorAction SilentlyContinue}
    $full=[IO.Path]::GetFullPath($workspace)
    if($full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -match '^REMNEXA-BackgroundNative-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}
}
