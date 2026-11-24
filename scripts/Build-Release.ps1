#Requires -Version 7.5
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot '../dist/windows-x64'),[string]$ZigPath=(Join-Path $PSScriptRoot '../tools/Modules/zig/zig-x86_64-windows-0.15.2/zig.exe'),[string]$RuntimePath,[string]$GitPath='git',
      [ValidateSet('Complete','Standard')][string]$Distribution='Complete',[string]$ComponentDirectory=(Join-Path $PSScriptRoot '../tools/Modules/complete-cache'),
      [string]$SigningCertificateThumbprint,[string]$SignToolPath,[string]$TimestampServer='https://timestamp.digicert.com')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
Import-Module (Join-Path $root 'Core/PathSafety.psd1') -Force
$git=(Get-Command $GitPath -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$status=@(& $git -C $root status --porcelain);if($LASTEXITCODE -ne 0 -or $status.Count){throw 'Build from a clean committed checkout.'}
$commit=& $git -C $root rev-parse HEAD
$pins=$null;$clamBundle=$null
if($Distribution -eq 'Complete'){
    Import-Module (Join-Path $PSScriptRoot 'BundlePayload.psm1') -Force
    $pins=Get-Content (Join-Path $root 'config/bundle-components.json') -Raw|ConvertFrom-Json
    $ComponentDirectory=[IO.Path]::GetFullPath($ComponentDirectory)
    if(-not $RuntimePath){$RuntimePath=Join-Path $ComponentDirectory ('powerShell-'+$pins.powerShell.version)}
    $runtimeArchive=Join-Path $ComponentDirectory ([IO.Path]::GetFileName(([uri]$pins.powerShell.uri).AbsolutePath))
    $clamArchive=Join-Path $ComponentDirectory ([IO.Path]::GetFileName(([uri]$pins.clamAV.uri).AbsolutePath))
    $clamSourceArchive=Join-Path $ComponentDirectory ([IO.Path]::GetFileName(([uri]$pins.clamAVSource.uri).AbsolutePath))
    foreach($path in @($RuntimePath,$runtimeArchive,$clamArchive,$clamSourceArchive,(Join-Path $ComponentDirectory 'database-verification.json'))){if(-not(Test-Path -LiteralPath $path)){throw 'Complete prerequisites are missing. Run scripts/Prepare-CompleteBundle.ps1 before building.'}}
    Assert-RemnexaBundleRuntime -Directory $RuntimePath -Archive $runtimeArchive -Pin $pins.powerShell
}
$signingContext=$null
if($SigningCertificateThumbprint){
    Import-Module (Join-Path $PSScriptRoot 'ReleaseSigning.psm1') -Force
    $signingContext=Get-RemnexaSigningContext -Thumbprint $SigningCertificateThumbprint -SignToolPath $SignToolPath -TimestampServer $TimestampServer
}elseif($SignToolPath){throw 'Specify -SigningCertificateThumbprint when selecting a signing tool.'}
$application=[IO.File]::ReadAllText((Join-Path $root 'REMNEXA.ps1'))
$match=[regex]::Match($application,'\$script:CleanerVersion\s*=\s*''([\w.-]+)''');if(-not $match.Success){throw 'Missing application version.'};$version=$match.Groups[1].Value
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not(Get-RemnexaPathSafety $root).IsSafe){throw 'Unsafe source root.'}
[void][IO.Directory]::CreateDirectory($output)
if(-not(Get-RemnexaPathSafety $output).IsSafe){throw 'Unsafe build output.'}
$destination=Join-Path $output ('REMNEXA-'+$version)
$variant=if($Distribution -eq 'Complete'){'-complete'}else{''}
$zip=Join-Path $output ('REMNEXA-'+$version+$variant+'-windows-x64-preview.zip')
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
    if($Distribution -eq 'Complete'){
        $clamBundle=Add-RemnexaClamBundle -Archive $clamArchive -SourceArchive $clamSourceArchive -DatabasePath (Join-Path $ComponentDirectory 'database') -VerificationPath (Join-Path $ComponentDirectory 'database-verification.json') -PackageDirectory $stage -Pins $pins
    }
    if($RuntimePath){
        $runtime=(Resolve-Path -LiteralPath $RuntimePath).Path
        if(-not(Test-Path -LiteralPath (Join-Path $runtime 'pwsh.exe'))){throw 'Optional runtime has no pwsh.exe.'}
        if(-not((Test-Path -LiteralPath (Join-Path $runtime 'LICENSE.txt')) -or (Test-Path -LiteralPath (Join-Path $runtime 'LICENSE')))){throw 'Optional runtime license is missing.'}
        if(-not(Test-Path -LiteralPath (Join-Path $runtime 'ThirdPartyNotices.txt'))){throw 'Optional PowerShell third-party notices are missing.'}
        foreach($file in Get-ChildItem -LiteralPath $runtime -File -Recurse -Force){
            $relative=[IO.Path]::GetRelativePath($runtime,$file.FullName)
            # The optional upstream preview CMD alias is not a runtime dependency.
            if($relative -match '^preview[\\/]'){continue}
            if($relative -eq '.upstream-sha256'){continue}
            if(-not(Get-RemnexaPathSafety $file.FullName).IsSafe){throw 'Unsafe runtime component.'}
            $target=Join-Path $stage ('runtime/'+$relative)
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target));[IO.File]::Copy($file.FullName,$target)
        }
        if($Distribution -eq 'Complete'){Assert-RemnexaBundleRuntime -Directory (Join-Path $stage 'runtime') -Archive $runtimeArchive -Pin $pins.powerShell}
        $diagnostic=& (Join-Path $stage 'REMNEXA.exe') --diagnose
        if($LASTEXITCODE -ne 0){throw 'Bundled runtime validation failed.'}
        $selected=($diagnostic -join "`n")|ConvertFrom-Json
        if(-not $selected.ok -or $selected.runtime -ne (Join-Path $stage 'runtime/pwsh.exe')){throw 'Bundled runtime was not selected as a compatible stable runtime.'}
    }
    $signingReport=$null
    if($signingContext){$signingReport=Invoke-RemnexaPackageSigning -PackageDirectory $stage -Context $signingContext}
    $readme=@'
REMNEXA 2.2.0 - Windows x64 launcher preview / Launcher-Vorschau

EN: Extract the entire folder and double-click REMNEXA.exe.
Folder layout: REMNEXA.exe + README.txt + app/ + optional runtime/.
This is the user package. Developer tools, tests and compatibility launchers are excluded.
Keep app/ and runtime/ beside the EXE; do not copy the EXE on its own.
Requires Windows 11 or newer (client build 22000+). Windows 10/Server are unsupported.
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
Ordnerstruktur: REMNEXA.exe + README.txt + app/ + optional runtime/.
Dies ist das Benutzerpaket. Quellcode-Werkzeuge, Tests und weitere Starter fehlen bewusst.
app/ und runtime/ neben der EXE lassen; die EXE nicht einzeln herauskopieren.
Windows 11 oder neuer (Client-Build ab 22000) erforderlich; Windows 10/Server nicht unterstützt.
PowerShell ab 7.5 (stabil) wird benötigt, sofern keine passende Laufzeit beiliegt.
Zuerst wird runtime/pwsh.exe, danach eine passende installierte Laufzeit genutzt.
Keine automatische Erhöhung, Policy-Umgehung, Dienste oder Antivirus-Ausnahmen.
ClamAV-Programme/Signaturen sind optional und nicht enthalten. Einrichtung braucht Internet.
app/ enthält die Anwendung und muss neben der EXE bleiben.
Diese Launcher-Vorschau ist unsigniert und ersetzt nicht das stabile Quellrelease.
Lizenz: app/LICENSE; optionaler nativer Adapter: app/Antivirus/Workers/COPYING.txt.
Drittanbieterhinweise: app/THIRD_PARTY_NOTICES.de.md.
'@
    if($signingReport){
        $readme=$readme.Replace('This launcher preview is unsigned and does not replace the stable source release.','The launcher and application scripts have verified, timestamped Authenticode signatures. This preview does not replace the stable source release.')
        $readme=$readme.Replace('Diese Launcher-Vorschau ist unsigniert und ersetzt nicht das stabile Quellrelease.','Launcher und Anwendungsskripte haben geprüfte Authenticode-Signaturen mit Zeitstempel. Diese Vorschau ersetzt nicht das stabile Quellrelease.')
    }
    if($Distribution -eq 'Complete'){
        $readme=$readme.Replace('Windows x64 launcher preview / Launcher-Vorschau','Complete - Windows x64 preview / Vorschau')
        $readme=$readme.Replace('REMNEXA.exe + README.txt + app/ + optional runtime/.','REMNEXA.exe + README.txt + app/ + runtime/.')
        $readme=$readme.Replace('PowerShell 7.5+ (stable) is required unless a compatible runtime is bundled.',('PowerShell '+$pins.powerShell.version+' is included. No additional PowerShell installation is required.'))
        $readme=$readme.Replace('ClamAV binaries/signatures are optional and not included. Setup needs internet.',('ClamAV '+$pins.clamAV.version+' and a verified signature snapshot are included. Scanning works offline from the first start.'))
        $readme=$readme.Replace('PowerShell ab 7.5 (stabil) wird benötigt, sofern keine passende Laufzeit beiliegt.',('PowerShell '+$pins.powerShell.version+' ist enthalten. Keine zusätzliche PowerShell-Installation nötig.'))
        $readme=$readme.Replace('ClamAV-Programme/Signaturen sind optional und nicht enthalten. Einrichtung braucht Internet.',('ClamAV '+$pins.clamAV.version+' und geprüfte Virensignaturen sind enthalten. Scans sind ab dem ersten Start offline möglich.'))
        $readme+="`r`nEN: Internet is only needed for future updates. Extract to a writable folder. Windows UAC consent may still be required for protected scan targets.`r`nDE: Internet wird nur für spätere Updates benötigt. In einen beschreibbaren Ordner entpacken. Für geschützte Scan-Ziele kann Windows weiterhin eine UAC-Bestätigung verlangen.`r`nClamAV source and license notices: app/licenses/clamav/.`r`n"
        $readme+="`r`nEN: Use [U] or /updates inside REMNEXA to check and confirm background updates. Keep using the app during downloads. PowerShell updates activate on the next launch; the dashboard shows versions and recent activities.`r`nDE: Mit [U] oder /updates Hintergrundupdates prüfen und bestätigen. Während Downloads bleibt die App nutzbar. PowerShell-Updates gelten ab dem nächsten Start; das Dashboard zeigt Versionen und letzte Aktivitäten.`r`n"
    }
    [IO.File]::WriteAllText((Join-Path $stage 'README.txt'),$readme.Replace('REMNEXA 2.2.0',('REMNEXA '+$version)),[Text.UTF8Encoding]::new($false))
    $records=@(Get-ChildItem -LiteralPath $stage -File -Recurse|ForEach-Object{[ordered]@{Path=[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}|Sort-Object { $_.Path })
    $manifest=[ordered]@{Version=$version;PackageStatus=$(if($Distribution -eq 'Complete'){'CompletePreview'}else{'LauncherPreview'});Distribution=$Distribution;SourceCommit=$commit;Architecture='x64';MinimumWindowsVersion='10.0.22000';WindowsProductType='Workstation';Compiler='Zig 0.15.2';RuntimeIncluded=[bool]$RuntimePath;ClamAVIncluded=($null -ne $clamBundle);Components=$(if($pins){[ordered]@{PowerShell=@{Version=$pins.powerShell.version;ArchiveSHA256=$pins.powerShell.sha256};ClamAV=$clamBundle}}else{$null});Signed=[bool]$signingReport;Signing=$signingReport;Files=$records}
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
            $entry=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=if($name -match '/ClamAV/database/(main|daily|bytecode)\.(cvd|cld)$'){[DateTimeOffset]$file.LastWriteTimeUtc}else{[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)}
            $input=[IO.File]::OpenRead($file.FullName);$target=$entry.Open();try{$input.CopyTo($target)}finally{$input.Dispose();$target.Dispose()}
        }
    }finally{$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($zip+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($zip)+"`n"),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Directory=$destination;Launcher=(Join-Path $destination 'REMNEXA.exe');Archive=$zip;SHA256=$hash;SourceCommit=$commit;Distribution=$Distribution;RuntimeIncluded=[bool]$RuntimePath;ClamAVIncluded=($null -ne $clamBundle);Signed=[bool]$signingReport}
}finally{
    if(Test-Path -LiteralPath $stage){
        $full=[IO.Path]::GetFullPath($stage)
        if((Split-Path -Parent $full) -eq $output -and (Split-Path -Leaf $full) -match '^\.build-[a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
    }
}
