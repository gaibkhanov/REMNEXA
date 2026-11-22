#Requires -Version 7.5
[CmdletBinding()]
param([string]$ZigPath=(Join-Path $PSScriptRoot '../tools/Modules/zig/zig-x86_64-windows-0.15.2/zig.exe'),[string]$OutputPath=(Join-Path $PSScriptRoot '../dist/launcher/REMNEXA.exe'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not(Test-Path -LiteralPath $ZigPath)){throw 'Zig 0.15.2 is required. Run scripts/Install-LauncherToolchain.ps1 first, or pass -ZigPath.'}
$tool=(Resolve-Path -LiteralPath $ZigPath).Path
$headers=Join-Path (Split-Path -Parent $tool) 'lib/libc/include/any-windows-any'
if((& $tool version) -ne '0.15.2'){throw 'Build requires pinned Zig 0.15.2.'}
$output=[IO.Path]::GetFullPath($OutputPath);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
$resource=Join-Path (Split-Path -Parent $output) ('.launcher-'+[guid]::NewGuid().ToString('N')+'.res')
Push-Location (Join-Path $root 'src/Launcher')
try {
    & $tool rc '/fo' $resource 'launcher.rc'
    if($LASTEXITCODE -ne 0){throw 'Launcher resource compilation failed.'}
    & $tool cc -target x86_64-windows-gnu -isystem $headers -std=c11 -Oz -s -fno-builtin -fno-stack-protector -nostdlib '-Wl,--entry,Entry' '-Wl,--subsystem,console' launcher.c $resource -lkernel32 -luser32 -lshell32 -ladvapi32 -o $output
    if($LASTEXITCODE -ne 0){throw 'Native launcher compilation failed.'}
}finally{Pop-Location;if(Test-Path -LiteralPath $resource){[IO.File]::Delete($resource)}}
# Normalize unsigned PE metadata; no code/resource bytes or signature is changed.
$bytes=[IO.File]::ReadAllBytes($output);$pe=[BitConverter]::ToInt32($bytes,0x3c)
foreach($offset in @(($pe+8),($pe+24+64))){[Array]::Copy([byte[]]@(0,0,0,0),0,$bytes,$offset,4)}
[IO.File]::WriteAllBytes($output,$bytes)
[pscustomobject]@{Path=$output;SHA256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();Compiler='Zig 0.15.2 / Clang';Architecture='x64';Signed=$false}
