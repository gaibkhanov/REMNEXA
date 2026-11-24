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
Import-Module (Join-Path $PSScriptRoot 'LauncherToolchain.psm1') -Force
$archive=Get-RemnexaVerifiedLauncherArchive -Directory $root -Version $version -SHA256 $hash
if((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'Official Zig toolchain checksum mismatch.'}
[IO.Compression.ZipFile]::ExtractToDirectory($archive,$root,$true)
if(-not(Test-Path -LiteralPath $exe)){throw 'Verified Zig toolchain is incomplete.'}
if((& $exe version) -ne $version){throw 'Extracted Zig version is unexpected.'}
[IO.File]::WriteAllText((Join-Path $root 'verified-toolchain.sha256'),$hash)
Write-Output $exe
