#Requires -Version 7.5
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot '../dist/windows-x64'),[string]$ZigPath=(Join-Path $PSScriptRoot '../tools/Modules/zig/zig-x86_64-windows-0.15.2/zig.exe'),[string]$RuntimePath,[string]$GitPath='git')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
Import-Module (Join-Path $root 'Core/PathSafety.psd1') -Force
$git=(Get-Command $GitPath -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$status=@(& $git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $status.Count){throw 'Build from a clean committed checkout.'}
$commit=& $git -C $root rev-parse HEAD
$application=[IO.File]::ReadAllText((Join-Path $root 'REMNEXA.ps1'))
$match=[regex]::Match($application,'\$script:CleanerVersion\s*=\s*''([\w.-]+)''');if(-not $match.Success){throw 'Missing application version.'};$version=$match.Groups[1].Value
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not(Get-RemnexaPathSafety $root).IsSafe){throw 'Unsafe source root.'}
[void][IO.Directory]::CreateDirectory($output)
if(-not(Get-RemnexaPathSafety $output).IsSafe){throw 'Unsafe build output.'}
$destination=Join-Path $output ('REMNEXA-'+$version)
$zip=Join-Path $output ('REMNEXA-'+$version+'-windows-x64-preview.zip')
if((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath ($zip+'.sha256'))){throw 'Build output exists; refusing to overwrite.'}
$stage=Join-Path $output ('.build-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($stage)
try {
    $launcher=& (Join-Path $PSScriptRoot 'Build-Launcher.ps1') -ZigPath $ZigPath -OutputPath (Join-Path $stage 'REMNEXA.exe')
    $files=@(& $git -C $root -c core.quotepath=false ls-files)
    foreach($relative in $files){
        if($relative -notmatch '^(REMNEXA\.ps1|LICENSE|Core/.+|Antivirus/.+|config/antivirus\.json|assets/.+|locales/[a-z]{2}\.json)$'){continue}
        if($relative -match '(^|/)(\.\.|Backup-[^/]*|tests|dist|runtime|ClamAV|ScanSessions)(/|$)' -or $relative -match '\.(log|jsonl|tmp|partial)$'){throw 'Forbidden application payload.'}
        $source=Join-Path $root $relative
        if(-not(Get-RemnexaPathSafety $source).IsSafe){throw 'Unsafe application payload.'}
        $target=Join-Path $stage ('app/'+$relative);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target));[IO.File]::Copy($source,$target)
    }
    foreach($suffix in @('','.de')){
        $notice=[IO.File]::ReadAllText((Join-Path $root ('docs/THIRD_PARTY_NOTICES'+$suffix+'.md')))
        $notice=$notice.Replace('(../LICENSE)','(LICENSE)').Replace('(../Antivirus/Workers/COPYING.txt)','(Antivirus/Workers/COPYING.txt)')
        $notice=$notice.Replace('(DEVELOPMENT_ROADMAP.md)',('(https://github.com/gaibkhanov/REMNEXA/blob/'+$commit+'/docs/DEVELOPMENT_ROADMAP.md)')).Replace('(DEVELOPMENT_ROADMAP.de.md)',('(https://github.com/gaibkhanov/REMNEXA/blob/'+$commit+'/docs/DEVELOPMENT_ROADMAP.de.md)'))
        [IO.File]::WriteAllText((Join-Path $stage ('app/THIRD_PARTY_NOTICES'+$suffix+'.md')),$notice,[Text.UTF8Encoding]::new($false))
    }
    Copy-Item -LiteralPath (Join-Path $root 'src/Launcher/THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $stage 'app/LAUNCHER_NOTICES.txt')
    if($RuntimePath){
        $runtime=(Resolve-Path -LiteralPath $RuntimePath).Path
        if(-not(Test-Path -LiteralPath (Join-Path $runtime 'pwsh.exe'))){throw 'Optional runtime has no pwsh.exe.'}
        if(-not((Test-Path -LiteralPath (Join-Path $runtime 'LICENSE.txt')) -or (Test-Path -LiteralPath (Join-Path $runtime 'LICENSE')))){throw 'Optional runtime license is missing.'}
        if(-not(Test-Path -LiteralPath (Join-Path $runtime 'ThirdPartyNotices.txt'))){throw 'Optional PowerShell third-party notices are missing.'}
        foreach($file in Get-ChildItem -LiteralPath $runtime -File -Recurse -Force){
            if(-not(Get-RemnexaPathSafety $file.FullName).IsSafe){throw 'Unsafe runtime component.'}
            $relative=[IO.Path]::GetRelativePath($runtime,$file.FullName);$target=Join-Path $stage ('runtime/'+$relative)
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target));[IO.File]::Copy($file.FullName,$target)
        }
        $diagnostic=& (Join-Path $stage 'REMNEXA.exe') --diagnose
        if($LASTEXITCODE -ne 0){throw 'Bundled runtime validation failed.'}
        $selected=($diagnostic -join "`n")|ConvertFrom-Json
        if(-not $selected.ok -or $selected.runtime -ne (Join-Path $stage 'runtime/pwsh.exe')){throw 'Bundled runtime was not selected as a compatible stable runtime.'}
    }
    $readme=@'
REMNEXA 2.2.0 - Windows x64 launcher preview / Launcher-Vorschau

EN: Extract the entire folder and double-click REMNEXA.exe.
PowerShell 7.5+ (stable) is required unless a compatible runtime is bundled.
The launcher uses runtime/pwsh.exe first, then an installed compatible runtime.
No automatic elevation, policy bypass, service or antivirus exclusion is added.
ClamAV binaries/signatures are optional and not included. Setup needs internet.
The app/ directory contains the application and must remain beside the EXE.
This launcher preview is unsigned and does not replace the stable source release.
License: app/LICENSE; optional native adapter: app/Antivirus/Workers/COPYING.txt.
Third-party notices: app/THIRD_PARTY_NOTICES.md.
Documentation: https://github.com/gaibkhanov/REMNEXA

DE: Den ganzen Ordner entpacken und REMNEXA.exe doppelklicken.
PowerShell ab 7.5 (stabil) wird benötigt, sofern keine passende Laufzeit beiliegt.
Zuerst wird runtime/pwsh.exe, danach eine passende installierte Laufzeit genutzt.
Keine automatische Erhöhung, Policy-Umgehung, Dienste oder Antivirus-Ausnahmen.
ClamAV-Programme/Signaturen sind optional und nicht enthalten. Einrichtung braucht Internet.
app/ enthält die Anwendung und muss neben der EXE bleiben.
Diese Launcher-Vorschau ist unsigniert und ersetzt nicht das stabile Quellrelease.
Lizenz: app/LICENSE; optionaler nativer Adapter: app/Antivirus/Workers/COPYING.txt.
Drittanbieterhinweise: app/THIRD_PARTY_NOTICES.de.md.
'@
    [IO.File]::WriteAllText((Join-Path $stage 'README.txt'),$readme.Replace('REMNEXA 2.2.0',('REMNEXA '+$version)),[Text.UTF8Encoding]::new($false))
    $records=@(Get-ChildItem -LiteralPath $stage -File -Recurse|ForEach-Object{[ordered]@{Path=[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}|Sort-Object { $_.Path })
    $manifest=[ordered]@{Version=$version;PackageStatus='LauncherPreview';SourceCommit=$commit;Architecture='x64';Compiler='Zig 0.15.2';RuntimeIncluded=[bool]$RuntimePath;Signed=$false;Files=$records}
    [IO.File]::WriteAllText((Join-Path $stage 'app/package-manifest.json'),($manifest|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    # Security/indexing tools can briefly hold a newly copied runtime directory.
    # Retry the same atomic rename with a fixed bound; never weaken permissions.
    for($moveAttempt=0;$moveAttempt -lt 7;$moveAttempt++){
        try{[IO.Directory]::Move($stage,$destination);break}
        catch [UnauthorizedAccessException]{if($moveAttempt -eq 6){throw};Start-Sleep -Milliseconds (250*[Math]::Pow(2,$moveAttempt))}
        catch [IO.IOException]{if($moveAttempt -eq 6){throw};Start-Sleep -Milliseconds (250*[Math]::Pow(2,$moveAttempt))}
    }
    $archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($file in (Get-ChildItem -LiteralPath $destination -File -Recurse|Sort-Object FullName)){
            $name='REMNEXA-'+$version+'/'+[IO.Path]::GetRelativePath($destination,$file.FullName).Replace('\','/')
            $entry=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal);$entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
            $input=[IO.File]::OpenRead($file.FullName);$target=$entry.Open();try{$input.CopyTo($target)}finally{$input.Dispose();$target.Dispose()}
        }
    }finally{$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($zip+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($zip)+"`n"),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Directory=$destination;Launcher=(Join-Path $destination 'REMNEXA.exe');Archive=$zip;SHA256=$hash;SourceCommit=$commit;RuntimeIncluded=[bool]$RuntimePath;Signed=$false}
}finally{
    if(Test-Path -LiteralPath $stage){
        $full=[IO.Path]::GetFullPath($stage)
        if((Split-Path -Parent $full) -eq $output -and (Split-Path -Leaf $full) -match '^\.build-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
    }
}
