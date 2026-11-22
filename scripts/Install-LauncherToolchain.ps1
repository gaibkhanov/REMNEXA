#Requires -Version 7.5
[CmdletBinding()]
param([string]$Destination=(Join-Path $PSScriptRoot '../tools/Modules/zig'))
$ErrorActionPreference='Stop'
$version='0.15.2'
$hash='3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c'
$root=[IO.Path]::GetFullPath($Destination);[void][IO.Directory]::CreateDirectory($root)
$exe=Join-Path $root ('zig-x86_64-windows-'+$version+'/zig.exe')
if((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath (Join-Path $root 'verified-toolchain.sha256')) -and ([IO.File]::ReadAllText((Join-Path $root 'verified-toolchain.sha256')).Trim() -ceq $hash)){Write-Output $exe;return}
$archive=Join-Path $root 'verified-zig.zip'
if(-not(Test-Path -LiteralPath $archive) -or (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash){
    & (Join-Path $env:SystemRoot 'System32/curl.exe') --silent --show-error --fail --location --connect-timeout 15 --max-time 180 --retry 1 --output $archive ('https://ziglang.org/download/'+$version+'/zig-x86_64-windows-'+$version+'.zip')
    if($LASTEXITCODE -ne 0){throw 'Official Zig toolchain download failed.'}
}
if((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'Official Zig toolchain checksum mismatch.'}
[IO.Compression.ZipFile]::ExtractToDirectory($archive,$root,$true)
if(-not(Test-Path -LiteralPath $exe)){throw 'Verified Zig toolchain is incomplete.'}
if((& $exe version) -ne $version){throw 'Extracted Zig version is unexpected.'}
[IO.File]::WriteAllText((Join-Path $root 'verified-toolchain.sha256'),$hash)
Write-Output $exe
