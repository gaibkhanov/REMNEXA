#Requires -Version 7.5
[CmdletBinding()]
param([string]$BaseRuntime=(Join-Path $PSScriptRoot '../runtime'),
      [string]$ComponentDirectory=(Join-Path $PSScriptRoot 'Modules/complete-cache'),[string]$OutputPath=(Join-Path $PSScriptRoot '../dist/component-runtime-validation.json'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Antivirus/Antivirus.psd1') -Force
Import-Module (Join-Path $root 'Core/Updates.psm1') -Force
$updates=Get-Module Updates;$av=Get-Module Antivirus
$pins=Get-Content (Join-Path $root 'config/bundle-components.json') -Raw|ConvertFrom-Json
$archive=Join-Path $ComponentDirectory ([IO.Path]::GetFileName(([uri]$pins.powerShell.uri).AbsolutePath))
if((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pins.powerShell.sha256){throw 'Prepare the pinned official PowerShell archive first.'}
$owned=Join-Path $root ('dist/component-integration-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($owned)
$oldProcess=$null
function Invoke-PrivateLauncherDiagnostic {
    param([string]$Executable)
    $info=[Diagnostics.ProcessStartInfo]::new($Executable);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.ArgumentList.Add('--diagnose')
    $info.Environment['PATH']='';$info.Environment['ProgramFiles']=Join-Path $owned 'unavailable';$info.Environment['ProgramW6432']=Join-Path $owned 'unavailable'
    $process=[Diagnostics.Process]::Start($info)
    try{
        $output=$process.StandardOutput.ReadToEndAsync();$errorOutput=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)){$process.Kill($true);throw 'Owned launcher diagnostic timed out.'}
        if($process.ExitCode){throw $errorOutput.GetAwaiter().GetResult()}
        $output.GetAwaiter().GetResult()|ConvertFrom-Json
    }finally{$process.Dispose()}
}
try{
    $package=Join-Path $owned 'package with spaces';$app=Join-Path $package 'app'
    [void][IO.Directory]::CreateDirectory($app)
    [IO.File]::WriteAllText((Join-Path $app 'REMNEXA.ps1'),'# harmless launcher fixture')
    Copy-Item -LiteralPath (Join-Path $root 'dist/launcher/REMNEXA.exe') -Destination (Join-Path $package 'REMNEXA.exe')
    & $updates {param($Source,$Destination)Copy-RemnexaUpdateTree $Source $Destination} ([IO.Path]::GetFullPath($BaseRuntime)) (Join-Path $package 'runtime')
    $before=Invoke-PrivateLauncherDiagnostic (Join-Path $package 'REMNEXA.exe')
    if([version]$before.version -ge [version]$pins.powerShell.version){throw 'This upgrade test needs an older baseline runtime.'}
    $oldFile=Join-Path $package 'runtime/pwsh.exe';$oldHash=(Get-FileHash $oldFile).Hash
    $start=[Diagnostics.ProcessStartInfo]::new($oldFile);$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-Command','[Threading.Thread]::Sleep(180000)')){$start.ArgumentList.Add($argument)}
    $oldProcess=[Diagnostics.Process]::Start($start)
    & $av {
        param($Archive)
        $script:FixtureArchive=$Archive
        function script:Receive-AVPackage {param($Uri,$OutFile,$OnProgress)[IO.File]::Copy($script:FixtureArchive,$OutFile);if($OnProgress){& $OnProgress (Get-Item $OutFile).Length (Get-Item $OutFile).Length}}
    } ([IO.Path]::GetFullPath($archive))
    $stage=Join-Path $owned 'stage';[void][IO.Directory]::CreateDirectory($stage)
    $result=& $updates {
        param($App,$StateDirectory,$Stage,$Pin,$Previous)
        $script:FixtureRelease=@{Version=$Pin.version;Uri=$Pin.uri;Digest=('sha256:'+$Pin.sha256);CanInstall=$true}
        function script:Get-RemnexaOfficialRelease {param($Component)$script:FixtureRelease}
        $paths=Get-RemnexaUpdatePaths $App $StateDirectory;$state=New-RemnexaUpdateState $paths.Context
        $state.Task=@{Id=[guid]::NewGuid().ToString('N');Status='Preparing';UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o');Completed=-1;Total=-1;Reason='';Version=''}
        Install-RemnexaPowerShellUpdate $paths $state $Previous $Stage
    } $app (Join-Path $owned 'state') $stage $pins.powerShell $before.version
    if($result -ne 'Ready' -or $oldProcess.HasExited -or (Get-FileHash $oldFile).Hash -cne $oldHash){throw 'The running baseline runtime was changed or interrupted.'}
    $after=Invoke-PrivateLauncherDiagnostic (Join-Path $package 'REMNEXA.exe')
    if($after.version -cne $pins.powerShell.version -or $after.runtime -ne (Join-Path $package ('runtime/versions/'+$pins.powerShell.version+'/pwsh.exe'))){throw 'The launcher did not select the verified updated runtime.'}
    foreach($invalid in @('../outside','9999.1.0',$before.version)){
        [IO.File]::WriteAllText((Join-Path $package 'runtime/active.txt'),$invalid)
        $fallback=Invoke-PrivateLauncherDiagnostic (Join-Path $package 'REMNEXA.exe')
        if($fallback.runtime -ne $oldFile){throw 'An unsafe, missing or non-newer runtime was selected.'}
    }
    $report=[ordered]@{Passed=$true;PreviousVersion=$before.version;PreparedVersion=$after.version;RunningPreviousVersionPreserved=$true;OriginalBytesPreserved=$true;UpdatedRuntimeSelectedOnNextLaunch=$true;UnsafeMissingAndNonNewerPointersRejected=$true;NetworkDownloads=0;OfficialArchiveSHA256=$pins.powerShell.sha256}
    $report|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
    [pscustomobject]$report
}finally{
    if($oldProcess){if(-not $oldProcess.HasExited){$oldProcess.Kill($true);[void]$oldProcess.WaitForExit(2000)};$oldProcess.Dispose()}
    & $updates {param($Path,$Parent)Remove-RemnexaOwnedStage $Path $Parent 'component-integration-'} $owned (Join-Path $root 'dist')
}
