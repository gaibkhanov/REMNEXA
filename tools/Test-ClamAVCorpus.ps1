#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'dist/worker-corpus-validation.json')
)
$ErrorActionPreference='Stop'
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-CorpusTest-'+[guid]::NewGuid().ToString('N'))
$database=Join-Path $workspace 'database';$data=Join-Path $workspace 'data'
foreach($folder in @($database,$data)){[void][IO.Directory]::CreateDirectory($folder)}
function New-CorpusZip {
    param([string]$Path,[string]$Name,[byte[]]$Bytes)
    $zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry($Name);$stream=$entry.Open();try{$stream.Write($Bytes)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
}
Import-Module (Join-Path $ProjectRoot 'Antivirus/Antivirus.psd1') -Force
$module=Get-Module Antivirus;$locked=$null
try{
    $bytes=[Text.Encoding]::UTF8.GetBytes('REMNEXA harmless custom fixture for archive and scan-API consistency. No malware.')
    $hash=[Convert]::ToHexString([Security.Cryptography.MD5]::HashData($bytes)).ToLowerInvariant()
    $signature=Join-Path $database 'fixture.hdb'
    [IO.File]::WriteAllText($signature,("{0}:{1}:REMNEXA.BenignCorpus" -f $hash,$bytes.Length)+"`n")
    [IO.File]::WriteAllBytes((Join-Path $data 'match.dat'),$bytes)
    [IO.File]::WriteAllText((Join-Path $data 'clean.txt'),'Different harmless text.')
    [IO.File]::WriteAllText((Join-Path $data 'Unicode-漢字-ü.txt'),'Harmless Unicode fixture: 漢字 äöü.')
    [IO.File]::WriteAllBytes((Join-Path $data 'empty.dat'),[byte[]]::new(0))
    $random=[byte[]]::new(128KB);[Random]::new(9182).NextBytes($random);[IO.File]::WriteAllBytes((Join-Path $data 'random.dat'),$random)
    New-CorpusZip (Join-Path $data 'zip-match.zip') 'match.dat' $bytes
    New-CorpusZip (Join-Path $data 'zip-clean.zip') 'clean.txt' ([Text.Encoding]::UTF8.GetBytes('Different clean archive content.'))
    New-CorpusZip (Join-Path $data 'nested-match.zip') 'inner.zip' ([IO.File]::ReadAllBytes((Join-Path $data 'zip-match.zip')))
    $stream=[IO.File]::Create((Join-Path $data 'gzip-match.gz'))
    $gzip=[IO.Compression.GZipStream]::new($stream,[IO.Compression.CompressionLevel]::Optimal)
    try{$gzip.Write($bytes)}finally{$gzip.Dispose();$stream.Dispose()}
    $stream=[IO.File]::Create((Join-Path $data 'tar-match.tar'));$tar=[System.Formats.Tar.TarWriter]::new($stream)
    try{$tar.WriteEntry((Join-Path $data 'match.dat'),'match.dat')}finally{$tar.Dispose();$stream.Dispose()}
    [IO.File]::WriteAllBytes((Join-Path $data 'limit.dat'),[byte[]]::new(1MB+1))
    $expected=@{'match.dat'='Infected';'clean.txt'='Clean';'Unicode-漢字-ü.txt'='Clean';'empty.dat'='Clean';'random.dat'='Clean';'zip-match.zip'='Infected';'zip-clean.zip'='Clean';'nested-match.zip'='Infected';'gzip-match.gz'='Infected';'tar-match.tar'='Infected';'limit.dat'='LimitExceeded'}
    $paths=[string[]]@(Get-ChildItem -LiteralPath $data -File|Sort-Object Name|Select-Object -ExpandProperty FullName)
    $list=Join-Path $workspace 'files.txt';[IO.File]::WriteAllLines($list,$paths,[Text.UTF8Encoding]::new($false))
    $config=Get-AVConfig;$config.ClamAVPath=Join-Path $ProjectRoot 'ClamAV';$config.DatabasePath=$database
    $config.LogPath=Join-Path $workspace 'logs';$config.QuarantinePath=Join-Path $workspace 'quarantine';$config.ExcludedPaths=@();$config.ScanBackend='PrivateWorker';$config.AutoCheckUpdates=$false
    $configPath=Join-Path $workspace 'config.json';$config|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding utf8
    & $module {param($Path)$script:AVConfigPath=$Path;Set-RemnexaProgressRendering $false} $configPath
    $status=[pscustomobject]@{ClamScanPath=(Join-Path $config.ClamAVPath 'clamscan.exe');DatabasePath=$database}
    $profile=Get-ClamAVScanPerformance -Mode Balanced
    $parameters=@{Config=$config;Status=$status;Profile=$profile;FileList=$list;MaxFileSize='1M';IncludePUA=$false;TimeoutSeconds=120;CancellationToken=[Threading.CancellationToken]::None}
    $native=& $module {param($Parameters)Invoke-AVPrivateScan @Parameters} $parameters
    $firstId=$native.EngineProcessId
    $cli=& $module {
        param($Status,$List)
        Invoke-AVNativeProcess -FilePath $Status.ClamScanPath -ArgumentList @('--no-summary','--stdout',('--database='+$Status.DatabasePath),('--file-list='+$List),'--max-filesize=1M','--alert-exceeds-max=yes') -TimeoutSeconds 120
    } $status $list
    $comparisons=[Collections.Generic.List[object]]::new()
    foreach($backend in @(@('Private',$native),@('CLI',$cli))){
        if($backend[1].ExitCode -ne 1){throw 'Corpus scan did not report the expected fixture detections.'}
        $found=@(Get-ClamAVScanResult -InputObject @($backend[1].StandardOutput,$backend[1].StandardError) -ExitCode $backend[1].ExitCode)
        $lines=($backend[1].StandardOutput+"`n"+$backend[1].StandardError) -split '\r?\n'
        foreach($path in $paths){
            $name=[IO.Path]::GetFileName($path);$item=@($found|Where-Object Path -eq $path)
            $actual=if($item.Count){$item[0].Status}else{'Clean'}
            $acknowledged=@($lines|Where-Object{ $_ -match ('^'+[regex]::Escape($path)+':\s+') }).Count -gt 0
            if(-not $acknowledged -or $actual -ne $expected[$name]){throw ("Corpus mismatch: {0}, {1}, expected {2}, actual {3}." -f $backend[0],$name,$expected[$name],$actual)}
            $comparisons.Add([pscustomobject]@{Backend=$backend[0];Fixture=$name;Status=$actual})
        }
    }
    $warm=& $module {param($Parameters)Invoke-AVPrivateScan @Parameters} $parameters
    if(-not $warm.EngineReused -or $warm.EngineProcessId -ne $firstId){throw 'Unchanged signatures were not reused.'}
    [IO.File]::WriteAllText($signature,("{0}:{1}:REMNEXA.UpdatedCorpus" -f $hash,$bytes.Length)+"`n")
    $updated=& $module {param($Parameters)Invoke-AVPrivateScan @Parameters} $parameters
    if($updated.EngineReused -or $updated.EngineProcessId -eq $firstId -or $updated.StandardOutput -notlike '*REMNEXA.UpdatedCorpus*'){throw 'Updated signatures did not invalidate the cached engine.'}
    $lockedPath=Join-Path $workspace 'locked.dat';[IO.File]::WriteAllText($lockedPath,'Harmless locked file.')
    $locked=[IO.File]::Open($lockedPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $lockedList=Join-Path $workspace 'locked.txt';[IO.File]::WriteAllLines($lockedList,[string[]]@($lockedPath))
    $parameters.FileList=$lockedList
    $nativeError=& $module {param($Parameters)Invoke-AVPrivateScan @Parameters} $parameters
    $cliError=& $module {param($Status,$List)Invoke-AVNativeProcess -FilePath $Status.ClamScanPath -ArgumentList @('--no-summary','--stdout',('--database='+$Status.DatabasePath),('--file-list='+$List)) -TimeoutSeconds 120} $status $lockedList
    if($nativeError.ExitCode -ne 2 -or $cliError.ExitCode -ne 2){throw 'An unreadable file was reported as a clean scan.'}
    $report=[pscustomobject]@{Passed=$true;FixtureCount=$paths.Count;CliAndNativeParity=$true;WarmEngineReused=$true;SignatureChangeReloaded=$true;UnreadableFileReportedByBoth=$true;QuarantineRequested=$false;InstalledDatabasesChanged=$false;RealMalwareUsed=$false;Cases=$comparisons.ToArray()}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))))
    $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $OutputPath -Encoding utf8
    $report
}finally{
    if($locked){$locked.Dispose()}
    Stop-ClamAVScanEngine;Remove-Module Antivirus -ErrorAction SilentlyContinue
    if((Split-Path -Leaf $workspace) -match '^REMNEXA-CorpusTest-[a-f0-9]{32}$'){[IO.Directory]::Delete($workspace,$true)}
}
