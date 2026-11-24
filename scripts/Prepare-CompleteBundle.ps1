#Requires -Version 7.5
[CmdletBinding()]
param([string]$Destination=(Join-Path $PSScriptRoot '../tools/Modules/complete-cache'),[string]$SignatureSeedPath)
$ErrorActionPreference='Stop'
$components=& (Join-Path $PSScriptRoot 'Get-BundledComponents.ps1') -Destination $Destination
$cache=[IO.Path]::GetFullPath($Destination)
$engines=@(Get-ChildItem -LiteralPath $components.clamAVPath -Filter clamscan.exe -Recurse -File)
if($engines.Count -ne 1){throw 'Expected exactly one verified ClamAV engine.'}
$engine=Split-Path -Parent $engines[0].FullName
$database=Join-Path $cache 'database';[void][IO.Directory]::CreateDirectory($database)
if(-not(Get-RemnexaPathSafety $database).IsSafe){throw 'Unsafe database cache.'}
if($SignatureSeedPath){
 if(-not(Get-RemnexaPathSafety $SignatureSeedPath).IsSafe){throw 'Unsafe signature seed directory.'}
 foreach($file in Get-ChildItem -LiteralPath $SignatureSeedPath -File){
  if($file.Name -notmatch '^(main|daily|bytecode)(\.(cvd|cld)|-[0-9]+\.cvd\.sign)$'){continue}
  if(-not(Get-RemnexaPathSafety $file.FullName).IsSafe){throw 'Unsafe signature seed file.'}
  $target=Join-Path $database $file.Name
  if(-not(Test-Path -LiteralPath $target)){[IO.File]::Copy($file.FullName,$target)}
 }
}
$config=Join-Path $cache 'freshclam-prepare.conf'
$text="DatabaseDirectory `"$($database.Replace('\','/'))`"`nDatabaseMirror database.clamav.net`nDNSDatabaseInfo current.cvd.clamav.net`nConnectTimeout 10`nReceiveTimeout 30`nMaxAttempts 2`n"
[IO.File]::WriteAllText($config,$text,[Text.UTF8Encoding]::new($false))
Import-Module (Join-Path $PSScriptRoot '../Core/NativeProcess.psd1') -Force
$run=Invoke-RemnexaNativeProcess -FilePath (Join-Path $engine 'freshclam.exe') -ArgumentList @(('--config-file='+$config),('--datadir='+$database),('--cvdcertsdir='+(Join-Path $engine 'certs')),'--stdout') -TimeoutSeconds 240 -WorkingDirectory $engine
if($run.ExitCode -ne 0){throw ('FreshClam could not prepare the complete package: '+$run.StandardOutput+' '+$run.StandardError)}
$checks=@()
foreach($name in @('main','daily','bytecode')){
 $files=@(Get-ChildItem -LiteralPath $database -File|Where-Object Name -Match ('^'+$name+'\.(cvd|cld)$'))
 if($files.Count -ne 1){throw ('Expected one official database: '+$name)}
 $info=Invoke-RemnexaNativeProcess -FilePath (Join-Path $engine 'sigtool.exe') -ArgumentList @(('--cvdcertsdir='+(Join-Path $engine 'certs')),('--info='+$files[0].FullName)) -TimeoutSeconds 60 -WorkingDirectory $engine
 if($info.ExitCode -ne 0){throw ('Database integrity verification failed: '+$name+' '+$info.StandardError)}
 $checks+=@{Name=$files[0].Name;SHA256=(Get-FileHash $files[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant();Bytes=$files[0].Length}
}
$summary=[ordered]@{PreparedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');FreshClamExitCode=0;Databases=$checks}
[IO.File]::WriteAllText((Join-Path $cache 'database-verification.json'),($summary|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{RuntimePath=$components.powerShellPath;ClamAVPath=$engine;DatabasePath=$database;SourceArchive=$components.clamAVSourceArchive;Verification=$summary}
