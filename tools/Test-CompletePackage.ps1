#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory,[string]$OutputPath)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $PackageDirectory).Path
$manifest=Get-Content (Join-Path $root 'app/package-manifest.json') -Raw|ConvertFrom-Json -DateKind String
if($manifest.Distribution -ne 'Complete' -or -not $manifest.RuntimeIncluded -or -not $manifest.ClamAVIncluded){throw 'This is not a Complete package.'}
$top=@(Get-ChildItem -LiteralPath $root -Force|Select-Object -ExpandProperty Name|Sort-Object)
if(($top -join ',') -cne 'app,README.txt,REMNEXA.exe,runtime'){throw 'Unexpected user package layout.'}
if(@(Get-ChildItem -LiteralPath $root -Recurse -File -Force).Count -ne @($manifest.Files).Count+1){throw 'Unlisted or missing package files.'}
foreach($record in $manifest.Files){if((Get-FileHash -LiteralPath (Join-Path $root $record.Path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.SHA256){throw ('Package integrity failure: '+$record.Path)}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-CompleteCheck-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
function Invoke-OwnedCheck {
    param([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=90)
    $info=[Diagnostics.ProcessStartInfo]::new($Executable);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.WorkingDirectory=$temp
    # Keep simulated installation roots separate from the harmless scan fixtures:
    # otherwise the real scan guard correctly treats those fixtures as system files.
    $info.Environment['PATH']='';$info.Environment['ProgramFiles']=Join-Path $temp 'unavailable-program-files';$info.Environment['ProgramW6432']=Join-Path $temp 'unavailable-program-files'
    $info.Environment['HTTP_PROXY']='http://127.0.0.1:9';$info.Environment['HTTPS_PROXY']='http://127.0.0.1:9';$info.Environment['ALL_PROXY']='http://127.0.0.1:9'
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info)
    try{
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){$process.Kill($true);throw 'Owned package validation process timed out.'}
        if($process.ExitCode){throw ('Package validation failed: '+$stdout.GetAwaiter().GetResult()+' '+$stderr.GetAwaiter().GetResult())}
        $stdout.GetAwaiter().GetResult()
    }finally{$process.Dispose()}
}
try{
    $diagnostic=Invoke-OwnedCheck (Join-Path $root 'REMNEXA.exe') @('--diagnose')|ConvertFrom-Json
    if(-not $diagnostic.ok -or $diagnostic.runtime -ne (Join-Path $root 'runtime/pwsh.exe') -or $diagnostic.version -ne $manifest.Components.PowerShell.Version){throw 'Complete relied on an external runtime.'}
    $self=Invoke-OwnedCheck (Join-Path $root 'REMNEXA.exe') @('-SelfTest','-NoElevation')|ConvertFrom-Json
    if(-not $self.Passed -or @($self.Checks).Count -ne 12){throw 'Complete self-test failed.'}
    $scanScript=Join-Path $temp 'scan.ps1'
    $code=@'
param([string]$Package,[string]$Temporary)
$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
Import-Module (Join-Path $Package 'app/Antivirus/Antivirus.psd1') -Force
$module=Get-Module Antivirus
& $module {Set-RemnexaProgressRendering $false}
$config=Get-AVConfig;$config.LogPath=Join-Path $Temporary 'logs';$config.QuarantinePath=Join-Path $Temporary 'quarantine';$config.AutoCheckUpdates=$false;$config.ScanPerformanceMode='Eco';$config.ExcludedPaths=@()
$configPath=Join-Path $Temporary 'antivirus.json';$config|ConvertTo-Json -Depth 8|Set-Content $configPath -Encoding utf8
$status=Get-ClamAVStatus -ConfigPath $configPath
if(-not $status.Installed -or -not $status.Ready -or $status.SignaturesOutdated){throw 'Bundled engine/databases are not ready or the archive lost their timestamps.'}
if($status.ClamScanPath -ne (Join-Path $Package 'app/ClamAV/clamscan.exe') -or $status.DatabasePath -ne (Join-Path $Package 'app/ClamAV/database')){throw 'Validation relied on an external antivirus installation.'}
$data=Join-Path $Temporary 'harmless';[void][IO.Directory]::CreateDirectory($data)
foreach($index in 1..8){[IO.File]::WriteAllText((Join-Path $data ($index.ToString()+'.txt')),('REMNEXA harmless offline packaging fixture '+$index))}
$rows=@(Invoke-ClamAVScan -ScanType Custom -Path $data -ConfigPath $configPath -PerformanceMode Eco)
if($rows.Count -ne 1 -or $rows[0].FilesTotal -ne 8 -or $rows[0].FilesReported -ne 8 -or $rows[0].Status -ne 'Clean' -or -not $rows[0].CoverageComplete){throw ('Actual offline application scan did not cover all harmless fixtures: '+($rows|ConvertTo-Json -Depth 4 -Compress))}
$fixture=Join-Path $Temporary 'known-benign.txt';[IO.File]::WriteAllText($fixture,'REMNEXA known benign detection test - not malware')
$bytes=[IO.File]::ReadAllBytes($fixture);$hash=[Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
$hdb=Join-Path $Temporary 'benign.hdb';[IO.File]::WriteAllText($hdb,($hash+':'+$bytes.Length+':Remnexa.Benign.PackagingFixture'+"`n"))
$arguments=@(('--database='+$status.DatabasePath),('--database='+$hdb),'--no-summary',$fixture)
$detection=& $module {param($Executable,$Arguments)Invoke-AVNativeProcess -FilePath $Executable -ArgumentList $Arguments -TimeoutSeconds 180 -WorkingDirectory (Split-Path -Parent $Executable)} $status.ClamScanPath $arguments
if($detection.ExitCode -ne 1 -or $detection.StandardOutput -notmatch 'Remnexa\.Benign\.PackagingFixture.*FOUND'){throw 'Known harmless signature did not produce the expected finding/exit code.'}
Stop-ClamAVScanEngine
[ordered]@{Runtime=$PSVersionTable.PSVersion.ToString();Engine=$status.Version;Ready=$status.Ready;SignatureAgeDays=$status.SignatureAgeDays;SignatureCount=$status.Signatures;CleanFixtures=$rows[0].FilesReported;ScanBackend=$rows[0].ScanBackend;HarmlessCustomSignatureDetected=$true;ExternalInstallationsUsed=$false;UpdatesRequested=$false;HTTPProxyUnavailable=$true}|ConvertTo-Json|Set-Content (Join-Path $Temporary 'scan-result.json') -Encoding utf8
'@
    [IO.File]::WriteAllText($scanScript,$code,[Text.UTF8Encoding]::new($false))
    $null=Invoke-OwnedCheck (Join-Path $root 'runtime/pwsh.exe') @('-NoProfile','-File',$scanScript,'-Package',$root,'-Temporary',$temp) -TimeoutSeconds 360
    $scan=Get-Content -LiteralPath (Join-Path $temp 'scan-result.json') -Raw|ConvertFrom-Json
    $report=[ordered]@{Passed=$true;PackageCommit=$manifest.SourceCommit;PackageHashesVerified=$true;Layout=$top;BundledRuntimeSelected=$true;SelfTests=@($self.Checks).Count;Elevated=$diagnostic.elevated;Scan=$scan;Signed=$manifest.Signed}
    if($OutputPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
    [pscustomobject]$report
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if((Split-Path -Parent $full).TrimEnd('\') -eq [IO.Path]::GetTempPath().TrimEnd('\') -and (Split-Path -Leaf $full) -match '^REMNEXA-CompleteCheck-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
}
