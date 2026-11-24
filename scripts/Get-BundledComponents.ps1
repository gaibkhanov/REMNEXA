#Requires -Version 7.5
[CmdletBinding()]
param([string]$Destination=(Join-Path $PSScriptRoot '../tools/Modules/complete-cache'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../Core/PathSafety.psd1') -Force
$pins=Get-Content (Join-Path $PSScriptRoot '../config/bundle-components.json') -Raw|ConvertFrom-Json
$cache=[IO.Path]::GetFullPath($Destination);[void][IO.Directory]::CreateDirectory($cache)
if(-not(Get-RemnexaPathSafety $cache).IsSafe){throw 'Unsafe component cache.'}
$paths=@{}
foreach($name in @('powerShell','clamAV','clamAVSource')){
 $pin=$pins.$name;$uri=[uri]$pin.uri
 if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $pin.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid official component pin.'}
 $archive=Join-Path $cache ([IO.Path]::GetFileName($uri.AbsolutePath))
 if(Test-Path -LiteralPath $archive){
  if(-not(Get-RemnexaPathSafety $archive).IsSafe -or (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256){throw 'Cached archive does not match its pinned checksum.'}
 }else{
  $partial=Join-Path $cache ([guid]::NewGuid().ToString('N')+'.partial')
  try{
   & (Join-Path $env:SystemRoot 'System32/curl.exe') --silent --show-error --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --retry 1 --output $partial $pin.uri
   if($LASTEXITCODE -ne 0){throw ('Official component download failed: '+$name)}
   if((Get-FileHash $partial -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256){throw ('Official component checksum mismatch: '+$name)}
   [IO.File]::Move($partial,$archive)
  }finally{if(Test-Path -LiteralPath $partial){[IO.File]::Delete($partial)}}
 }
 $paths[$name+'Archive']=$archive
 if($name -eq 'clamAVSource'){continue}
 $directory=Join-Path $cache ($name+'-'+$pin.version)
 if(-not(Test-Path -LiteralPath $directory)){
  $stage=Join-Path $cache ('.extract-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($stage)
  try{
   $zip=[IO.Compression.ZipFile]::OpenRead($archive)
   try{
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $zip.Entries){
     $path=$entry.FullName.Replace('\','/')
     if($path -match '(^/|:|(^|/)\.\.(/|$))' -or -not $seen.Add($path) -or (($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000){throw 'Unsafe component archive entry.'}
    }
   }finally{$zip.Dispose()}
   [IO.Compression.ZipFile]::ExtractToDirectory($archive,$stage)
   [IO.File]::WriteAllText((Join-Path $stage '.upstream-sha256'),$pin.sha256)
   [IO.Directory]::Move($stage,$directory)
  }finally{if(Test-Path -LiteralPath $stage){$full=[IO.Path]::GetFullPath($stage);if((Split-Path -Parent $full) -eq $cache -and (Split-Path -Leaf $full) -match '^\.extract-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}}}
 }
 if(-not(Get-RemnexaPathSafety $directory).IsSafe -or [IO.File]::ReadAllText((Join-Path $directory '.upstream-sha256')) -cne $pin.sha256){throw 'Invalid extracted component cache.'}
 $zip=[IO.Compression.ZipFile]::OpenRead($archive)
 $expectedFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 try{
  foreach($entry in $zip.Entries){
   if(-not $entry.Name){continue}
   [void]$expectedFiles.Add($entry.FullName.Replace('\','/'))
   $file=Join-Path $directory $entry.FullName
   if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or -not(Get-RemnexaPathSafety $file).IsSafe){throw 'Missing or unsafe extracted component file.'}
   $stream=$entry.Open();try{$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()}finally{$stream.Dispose()}
   if((Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'Extracted component differs from its verified upstream archive.'}
  }
 }finally{$zip.Dispose()}
 foreach($file in Get-ChildItem -LiteralPath $directory -File -Recurse -Force){
  $relative=[IO.Path]::GetRelativePath($directory,$file.FullName).Replace('\','/')
  if($relative -ne '.upstream-sha256' -and -not $expectedFiles.Contains($relative)){throw 'Unexpected file in the extracted component cache.'}
 }
 $paths[$name+'Path']=$directory
}
[pscustomobject]$paths
