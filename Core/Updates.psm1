# SPDX-License-Identifier: MIT
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PathSafety.psd1')
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psd1')
Import-Module (Join-Path $PSScriptRoot 'Progress.psd1')
$script:ComponentNames=@('PowerShell','Antivirus','Signatures','Application')
$script:UpdateProcesses=[Collections.Generic.List[object]]::new()

function Get-RemnexaUpdatePaths {
    param([Parameter(Mandatory)][string]$ApplicationRoot,[string]$StateDirectory)
    $app=[IO.Path]::GetFullPath($ApplicationRoot).TrimEnd('\')
    $package=if((Split-Path -Leaf $app) -eq 'app' -and (Test-Path (Join-Path (Split-Path -Parent $app) 'REMNEXA.exe'))){Split-Path -Parent $app}else{$app}
    $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($app.ToLowerInvariant()))).ToLowerInvariant()
    $state=if($StateDirectory){[IO.Path]::GetFullPath($StateDirectory)}else{Join-Path $env:LOCALAPPDATA ('REMNEXA/Updates/'+$key)}
    [pscustomobject]@{App=$app;Package=$package;Context=$key;Directory=$state;State=(Join-Path $state 'state.json');Lock=(Join-Path $state 'task.lock')}
}

function Assert-RemnexaUpdatePath {
    param([string]$Path)
    $existing=[IO.Path]::GetFullPath($Path)
    while($true){
        try{[void][IO.File]::GetAttributes($existing);break}
        catch [IO.FileNotFoundException]{$existing=[IO.Path]::GetDirectoryName($existing)}
        catch [IO.DirectoryNotFoundException]{$existing=[IO.Path]::GetDirectoryName($existing)}
        if(-not $existing){throw 'Unsafe update path.'}
    }
    # New destinations validate their nearest existing parent; inaccessible or
    # linked existing components are still rejected, rather than treated as absent.
    if(-not(Get-RemnexaPathSafety $existing).IsSafe){throw 'Unsafe update path.'}
}

function ConvertTo-RemnexaStableVersion {
    param([string]$Value)
    if($Value -notmatch '^\d{1,4}\.\d{1,4}\.\d{1,4}$'){throw 'A stable semantic version is required.'}
    [version]$Value
}

function Write-RemnexaUpdateJson {
    param([string]$Path,$Value)
    $directory=Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory);Assert-RemnexaUpdatePath $Path
    $temporary=Join-Path $directory ('.update-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,($temporary+'.bak'))}else{[IO.File]::Move($temporary,$Path)}
    }finally{foreach($owned in @($temporary,($temporary+'.bak'))){if([IO.File]::Exists($owned)){[IO.File]::Delete($owned)}}}
}

function New-RemnexaUpdateState {
    param([string]$Context)
    $components=foreach($name in $script:ComponentNames){[ordered]@{Name=$name;InstalledVersion='';AvailableVersion='';Status='unknown';CanInstall=$false;CheckedUtc=$null}}
    @{Schema=1;Context=$Context;LastCheckUtc=$null;LastAttemptUtc=$null;Components=@($components);Task=$null;History=@();Prepared=@{PowerShell='';ApplicationVersion='';ApplicationPath=''}}
}

function Get-RemnexaComponentUpdates {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ApplicationRoot,[string]$StateDirectory)
    $paths=Get-RemnexaUpdatePaths $ApplicationRoot $StateDirectory
    $state=New-RemnexaUpdateState $paths.Context
    try{
        Assert-RemnexaUpdatePath $paths.State
        if((Get-Item -LiteralPath $paths.State -ErrorAction Stop).Length -gt 1MB){throw 'Oversized update state.'}
        $stream=[IO.File]::Open($paths.State,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
        try{$saved=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable -DateKind String}finally{$reader.Dispose()}
        if(-not $saved.ContainsKey('Prepared')){$saved.Prepared=@{PowerShell='';ApplicationVersion='';ApplicationPath=''}}
        if($saved.Schema -ne 1 -or $saved.Context -cne $paths.Context -or @($saved.Components).Count -ne 4 -or @($saved.History).Count -gt 30){throw 'Invalid update state.'}
        foreach($name in $script:ComponentNames){if(@($saved.Components|Where-Object Name -eq $name).Count -ne 1){throw 'Invalid component inventory.'}}
        if($saved.Task -and $saved.Task.Status -notin @('Starting','Checking','Preparing','Downloading','Verifying','WaitingForScan','Installing','Completed','Ready','Failed','Cancelled')){throw 'Invalid task status.'}
        $state=$saved
        if($state.Task -and $state.Task.Status -notin @('Completed','Ready','Failed','Cancelled')){
            $age=([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($state.Task.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture)).TotalSeconds
            # A crashed worker must not be presented as running indefinitely.
            $probe=$null
            try{$probe=[IO.File]::Open($paths.Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);if($age -gt 15){$state.Task.Status='Failed';$state.Task.Reason='worker_stopped'}}catch [IO.IOException]{}finally{if($probe){$probe.Dispose()}}
        }
    }catch{$state=New-RemnexaUpdateState $paths.Context;Write-Verbose 'No readable component-update cache.'}
    $state
}

function Set-RemnexaUpdatePhase {
    param($State,$Paths,[string]$Status,[long]$Completed=-1,[long]$Total=-1,[string]$Reason='')
    if($Status -notin @('Completed','Ready','Failed','Cancelled') -and -not($Status -eq 'Installing' -and $State.Task.Status -eq 'Installing') -and (Test-Path -LiteralPath (Join-Path $Paths.Directory ('cancel-'+$State.Task.Id+'.json')))){throw [OperationCanceledException]::new('Update cancelled before activation.')}
    if($Status -eq $State.Task.Status -and ([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($State.Task.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture)).TotalMilliseconds -lt 500){return}
    $State.Task.Status=$Status;$State.Task.UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $State.Task.Completed=$Completed;$State.Task.Total=$Total;$State.Task.Reason=$Reason
    Write-RemnexaUpdateJson $Paths.State $State
}

function Get-RemnexaOfficialRelease {
    param([ValidateSet('PowerShell','Application')][string]$Component)
    $repo=if($Component -eq 'PowerShell'){'PowerShell/PowerShell'}else{'gaibkhanov/REMNEXA'}
    $release=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$repo+'/releases/latest') -Headers @{'User-Agent'='REMNEXA-Updates';Accept='application/vnd.github+json'} -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
    if($release.draft -or $release.prerelease){throw 'A stable release is required.'}
    $version=([string]$release.tag_name) -replace '^v',''
    [void](ConvertTo-RemnexaStableVersion $version)
    $expected=if($Component -eq 'PowerShell'){'PowerShell-'+$version+'-win-x64.zip'}else{'REMNEXA-'+$version+'-complete-windows-x64.zip'}
    $assets=@($release.assets|Where-Object name -ceq $expected)
    $asset=if($assets.Count -eq 1){$assets[0]}else{$null}
    $result=@{Version=$version;Uri='';Digest='';CanInstall=$false;Name=$expected}
    if($asset){
        $uri=[uri]$asset.browser_download_url
        $prefix='/'+$repo+'/releases/download/'+$release.tag_name+'/'
        if($uri.Scheme -cne 'https' -or $uri.Host -ine 'github.com' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cne ($prefix+$expected)){throw 'Unexpected release download source.'}
        $result.Uri=$uri.AbsoluteUri
        $digest=if($asset.PSObject.Properties['digest']){[string]$asset.digest}else{''}
        if($digest -match '^sha256:[a-fA-F0-9]{64}$'){$result.Digest=$digest.ToLowerInvariant();$result.CanInstall=$true}
    }
    $result
}

function Get-RemnexaLocalTools {
    param([string]$ApplicationRoot,[string]$ApplicationVersion,[string]$PowerShellVersion,[switch]$MetadataOnly)
    Import-Module (Join-Path $ApplicationRoot 'Antivirus/Antivirus.psd1')
    $module=Get-Module Antivirus
    if($MetadataOnly){
        $root=& $module {param($Path)Expand-AVPath ([string](Get-AVConfig -Path $Path).ClamAVPath)} (Join-Path $ApplicationRoot 'config/antivirus.json')
        $file=Join-Path $root 'clamscan.exe';Assert-RemnexaUpdatePath $file
        $fileVersion=if(Test-Path -LiteralPath $file){[Diagnostics.FileVersionInfo]::GetVersionInfo($file).FileVersion}else{''}
        $status=@{Version=$(if($fileVersion -match '^\d+\.\d+\.\d+$'){$fileVersion}else{''})}
    }else{try{$status=Get-ClamAVStatus -ConfigPath (Join-Path $ApplicationRoot 'config/antivirus.json')}catch{$status=@{Version=''}}}
    $databases=@(& $module {param($Path)Get-AVLocalDatabaseVersions (Get-AVConfig -Path $Path)} (Join-Path $ApplicationRoot 'config/antivirus.json'))
    $databaseText=(@($databases|ForEach-Object{$_.name+':'+$(if($null -eq $_.installedVersion){'?'}else{$_.installedVersion})}) -join ' | ')
    @{PowerShell=$PowerShellVersion;Antivirus=[string]$status.Version;Signatures=$databaseText;Application=$ApplicationVersion}
}

function Invoke-RemnexaComponentCheck {
    param($Paths,$State,[string]$ApplicationVersion,[string]$PowerShellVersion)
    $local=Get-RemnexaLocalTools $Paths.App $ApplicationVersion $PowerShellVersion
    foreach($row in $State.Components){$row.InstalledVersion=[string]$local[$row.Name]}
    if($State.Prepared.PowerShell -and (ConvertTo-RemnexaStableVersion $PowerShellVersion) -ge (ConvertTo-RemnexaStableVersion $State.Prepared.PowerShell)){$State.Prepared.PowerShell=''}
    if($State.Prepared.ApplicationVersion -and (ConvertTo-RemnexaStableVersion $ApplicationVersion) -ge (ConvertTo-RemnexaStableVersion $State.Prepared.ApplicationVersion)){$State.Prepared.ApplicationVersion='';$State.Prepared.ApplicationPath=''}
    $successful=$false
    foreach($name in @('PowerShell','Application')){
        $row=$State.Components|Where-Object Name -eq $name
        try{
            $remote=Get-RemnexaOfficialRelease $name
            $row.AvailableVersion=$remote.Version;$row.CanInstall=$remote.CanInstall
            $row.Status=if((ConvertTo-RemnexaStableVersion $remote.Version) -gt (ConvertTo-RemnexaStableVersion $local[$name])){'update_available'}else{'current'}
            $row.CheckedUtc=[DateTimeOffset]::UtcNow.ToString('o');$successful=$true
        }catch{
            $failure=$_
            $row.Status=& (Get-Module Antivirus) {param($ErrorRecord)Get-AVUpdateFailureStatus $ErrorRecord} $failure
            $row.CanInstall=$false
        }
    }
    try{
        $av=Invoke-ClamAVUpdateCheck -ConfigPath (Join-Path $Paths.App 'config/antivirus.json') -StatePath (Join-Path $Paths.Directory 'antivirus-metadata.json') -Force
        foreach($pair in @(@('Antivirus','engine'),@('Signatures','signatures'))){
            $row=$State.Components|Where-Object Name -eq $pair[0];$source=$av.($pair[1])
            $row.Status=if($source.isStale -and $source.status -in @('current','update_available')){'unknown'}else{[string]$source.status}
            $row.CanInstall=[bool]$source.canUpdate -and ($pair[0] -eq 'Signatures' -or -not $source.isStale)
            if($pair[0] -eq 'Antivirus'){$row.AvailableVersion=[string]$source.availableVersion}
            $row.CheckedUtc=$source.checkedUtc
        }
        if(-not $av.isStale){$successful=$true}
    }catch{foreach($row in $State.Components|Where-Object Name -in @('Antivirus','Signatures')){$row.Status='offline';$row.CanInstall=$false}}
    if($successful){$State.LastCheckUtc=[DateTimeOffset]::UtcNow.ToString('o')}
}

function Expand-RemnexaUpdateArchive {
    param([string]$Archive,[string]$Destination,[long]$MaximumBytes=4GB)
    Assert-RemnexaUpdatePath $Destination
    [void][IO.Directory]::CreateDirectory($Destination)
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive);$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$total=[long]0
    try{
        if($zip.Entries.Count -gt 25000){throw 'Too many archive entries.'}
        # Validate the whole archive before extracting any file.
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.Replace('\','/');$total+=$entry.Length
            if($name -match '(^/|:|(^|/)\.\.(/|$)|[\x00-\x1f]|[. ](?:/|$))' -or -not $seen.Add($name) -or (($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000 -or $total -gt $MaximumBytes){throw 'Unsafe update archive.'}
        }
        foreach($entry in $zip.Entries){
            $target=Join-Path $Destination $entry.FullName;Assert-RemnexaUpdatePath $target
            if(-not $entry.Name){[void][IO.Directory]::CreateDirectory($target);continue}
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target));[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    }finally{$zip.Dispose()}
}

function Receive-RemnexaUpdateArchive {
    param($Release,[string]$Path,$State,$Paths)
    if(-not $Release.CanInstall -or $Release.Digest -notmatch '^sha256:([a-f0-9]{64})$'){throw 'No verified download is available.'}
    $hash=$Matches[1]
    $module=Get-Module Antivirus
    $phaseCommand=Get-Command Set-RemnexaUpdatePhase
    $callback={param($Done,$Total)& $phaseCommand $State $Paths 'Downloading' $Done $Total}.GetNewClosure()
    & $module {param($Uri,$Path,$Callback)Receive-AVPackage -Uri $Uri -OutFile $Path -OnProgress $Callback} $Release.Uri $Path $callback
    Set-RemnexaUpdatePhase $State $Paths 'Verifying'
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'Update checksum mismatch.'}
}

function Install-RemnexaPowerShellUpdate {
    param($Paths,$State,[string]$PowerShellVersion,[string]$Stage)
    $release=Get-RemnexaOfficialRelease PowerShell
    if((ConvertTo-RemnexaStableVersion $release.Version) -le (ConvertTo-RemnexaStableVersion $PowerShellVersion)){return 'Completed'}
    if($State.Prepared.PowerShell -eq $release.Version){
        $existing=Join-Path $Paths.Package ('runtime/versions/'+$release.Version+'/pwsh.exe');Assert-RemnexaUpdatePath $existing
        if(Test-Path -LiteralPath $existing){$State.Task.Version=$release.Version;return 'Ready'}
    }
    $archive=Join-Path $Stage 'powershell.zip';Receive-RemnexaUpdateArchive $release $archive $State $Paths
    $runtime=Join-Path $Paths.Package 'runtime';$versions=Join-Path $runtime 'versions'
    [void][IO.Directory]::CreateDirectory($versions);Assert-RemnexaUpdatePath $versions
    $destination=Join-Path $versions $release.Version
    # Staging and the atomic rename stay on the runtime volume.
    $pending=Join-Path $versions ('.pending-'+$State.Task.Id)
    try{
        if(Test-Path -LiteralPath $destination){throw 'Runtime version already exists; refusing to replace running files.'}
        Expand-RemnexaUpdateArchive $archive $pending
        foreach($name in @('pwsh.exe','LICENSE.txt','ThirdPartyNotices.txt')){if(-not(Test-Path (Join-Path $pending $name))){throw 'Incomplete portable PowerShell runtime.'}}
        $probe=Invoke-RemnexaNativeProcess -FilePath (Join-Path $pending 'pwsh.exe') -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-Command','[Console]::Write($PSVersionTable.PSVersion.ToString())') -TimeoutSeconds 30 -WorkingDirectory $pending
        if($probe.ExitCode -ne 0 -or $probe.StandardOutput.Trim() -cne $release.Version){throw 'Portable PowerShell version check failed.'}
        Set-RemnexaUpdatePhase $State $Paths 'Installing'
        [IO.Directory]::Move($pending,$destination)
        # Only the exact validated numeric version is made selectable by the launcher.
        $pointer=Join-Path $runtime ('active-'+$State.Task.Id+'.tmp');$active=Join-Path $runtime 'active.txt'
        Assert-RemnexaUpdatePath $active
        [IO.File]::WriteAllText($pointer,$release.Version,[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $active){[IO.File]::Replace($pointer,$active,($pointer+'.bak'));[IO.File]::Delete(($pointer+'.bak'))}else{[IO.File]::Move($pointer,$active)}
        $State.Task.Version=$release.Version
        $State.Prepared.PowerShell=$release.Version
        return 'Ready'
    }finally{Remove-RemnexaOwnedStage $pending $versions '.pending-'}
}

function Remove-RemnexaOwnedStage {
    param([string]$Path,[string]$Parent,[string]$Prefix)
    $full=[IO.Path]::GetFullPath($Path)
    if((Split-Path -Parent $full) -ne [IO.Path]::GetFullPath($Parent).TrimEnd('\') -or (Split-Path -Leaf $full) -notmatch ('^'+[regex]::Escape($Prefix)+'[a-f0-9]{32}$')){throw 'Unsafe update cleanup.'}
    if(Test-Path -LiteralPath $full){Assert-RemnexaUpdatePath $full;[IO.Directory]::Delete($full,$true)}
}

function Start-RemnexaComponentTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ApplicationRoot,[ValidateSet('Check','PowerShell','Antivirus','Signatures','Both','Application')][string]$Component='Check',
          [string]$ApplicationVersion,[string]$PowerShellVersion=$PSVersionTable.PSVersion.ToString(),[string]$StateDirectory,[switch]$Force,
          [ValidateSet('','Quick','Full','Custom')][string]$AfterScanType='',[string[]]$AfterScanPath=@(),[ValidateSet('de','en','es','fr','ru','tr')][string]$Language='de')
    $paths=Get-RemnexaUpdatePaths $ApplicationRoot $StateDirectory
    Assert-RemnexaUpdatePath $paths.App;[void][IO.Directory]::CreateDirectory($paths.Directory);Assert-RemnexaUpdatePath $paths.Directory
    $guard=[IO.File]::Open(($paths.State+'.start'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        foreach($owned in $script:UpdateProcesses.ToArray()){if($owned.Process.HasExited){$owned.Process.Dispose();[void]$script:UpdateProcesses.Remove($owned)}}
        $state=Get-RemnexaComponentUpdates $ApplicationRoot $StateDirectory
        if($state.Task -and $state.Task.Status -notin @('Completed','Ready','Failed','Cancelled')){return $false}
        if($Component -eq 'Check' -and -not $Force){
            if($state.LastCheckUtc -and [DateTimeOffset]::Parse($state.LastCheckUtc,[Globalization.CultureInfo]::InvariantCulture).AddHours(24) -gt [DateTimeOffset]::UtcNow){return $false}
            if($state.LastAttemptUtc -and [DateTimeOffset]::Parse($state.LastAttemptUtc,[Globalization.CultureInfo]::InvariantCulture).AddMinutes(5) -gt [DateTimeOffset]::UtcNow){return $false}
        }
        $id=[guid]::NewGuid().ToString('N')
        $state.LastAttemptUtc=[DateTimeOffset]::UtcNow.ToString('o')
        $state.Task=@{Id=$id;Component=$Component;Status='Starting';UpdatedUtc=$state.LastAttemptUtc;StartedUtc=$state.LastAttemptUtc;Completed=-1;Total=-1;Reason='';Version='';PreparedPath='';AfterScanType=$AfterScanType;AfterScanPath=$AfterScanPath;Language=$Language;ScanStarted=$false}
        Write-RemnexaUpdateJson $paths.State $state
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'));$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        foreach($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'UpdateWorker.ps1'),'-ApplicationRoot',$paths.App,'-StateDirectory',$paths.Directory,'-Id',$id,'-ApplicationVersion',$ApplicationVersion,'-PowerShellVersion',$PowerShellVersion)){$info.ArgumentList.Add([string]$arg)}
        try{
            $process=[Diagnostics.Process]::Start($info)
            $script:UpdateProcesses.Add(@{Process=$process;Component=$Component;Id=$id;Directory=$paths.Directory;Output=$process.StandardOutput.ReadToEndAsync();Error=$process.StandardError.ReadToEndAsync()})
            return $true
        }catch{$state.Task.Status='Failed';$state.Task.Reason='start_failed';Write-RemnexaUpdateJson $paths.State $state;throw}
    }finally{$guard.Dispose()}
}

function Stop-RemnexaComponentTask {
    param([Parameter(Mandatory)][string]$ApplicationRoot,[string]$StateDirectory)
    $paths=Get-RemnexaUpdatePaths $ApplicationRoot $StateDirectory
    $state=Get-RemnexaComponentUpdates $ApplicationRoot $StateDirectory
    if($state.Task -and $state.Task.Status -in @('Starting','Checking','Preparing','Downloading','Verifying','WaitingForScan')){
        Write-RemnexaUpdateJson (Join-Path $paths.Directory ('cancel-'+$state.Task.Id+'.json')) @{Cancel=$true}
        return $true
    }
    return $false
}

. (Join-Path $PSScriptRoot 'UpdateOperations.ps1')
function Close-RemnexaComponentSession {
    param([string]$ApplicationRoot)
    foreach($owned in $script:UpdateProcesses){
        if($owned.Component -eq 'Check' -and -not $owned.Process.HasExited){
            $owned.Process.Kill($true);[void]$owned.Process.WaitForExit(2000)
            $paths=Get-RemnexaUpdatePaths $ApplicationRoot $owned.Directory
            $state=Get-RemnexaComponentUpdates $ApplicationRoot $owned.Directory
            if($state.Task -and $state.Task.Id -ceq $owned.Id){Set-RemnexaUpdatePhase $state $paths 'Cancelled'}
        }
        $owned.Process.Dispose()
    }
    $script:UpdateProcesses.Clear()
}
function Get-RemnexaAntivirusUpdateState {
    param([string]$ApplicationRoot)
    $paths=Get-RemnexaUpdatePaths $ApplicationRoot
    Get-ClamAVUpdateState -ConfigPath (Join-Path $paths.App 'config/antivirus.json') -StatePath (Join-Path $paths.Directory 'antivirus-metadata.json')
}
Export-ModuleMember -Function Get-RemnexaComponentUpdates,Start-RemnexaComponentTask,Stop-RemnexaComponentTask,Get-RemnexaLocalTools,Close-RemnexaComponentSession,Get-RemnexaAntivirusUpdateState
