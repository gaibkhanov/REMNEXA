# SPDX-License-Identifier: MIT
# Private update operations, loaded by Updates.psm1. Only verified archives execute.
function Copy-RemnexaUpdateTree {
    param([string]$Source,[string]$Destination)
    Assert-RemnexaUpdatePath $Source;Assert-RemnexaUpdatePath $Destination
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Source);$count=0;$bytes=[long]0
    while($pending.Count){
        $directory=$pending.Pop()
        $relative=[IO.Path]::GetRelativePath($Source,$directory);$target=Join-Path $Destination $relative
        [void][IO.Directory]::CreateDirectory($target)
        foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($directory)){
            Assert-RemnexaUpdatePath $entry;$count++
            if($count -gt 50000){throw 'Too many files in the portable installation.'}
            if([IO.Directory]::Exists($entry)){$pending.Push($entry)}else{
                $bytes+=(Get-Item -LiteralPath $entry).Length;if($bytes -gt 4GB){throw 'Portable installation exceeds the staging limit.'}
                [IO.File]::Copy($entry,(Join-Path $target ([IO.Path]::GetFileName($entry))))
            }
        }
    }
}

function Get-RemnexaDatabaseFingerprint {
    param([string]$Directory)
    $values=foreach($file in Get-ChildItem -LiteralPath $Directory -File -ErrorAction Stop|Sort-Object Name){
        Assert-RemnexaUpdatePath $file.FullName
        if($file.Extension -in @('.cvd','.cld','.hdb','.ndb','.ldb','.sfp','.ign','.ign2')){$file.Name+':'+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
    $values -join '|'
}

function Install-RemnexaAntivirusUpdate {
    param($Paths,$State,[string]$Stage)
    $configPath=Join-Path $Paths.App 'config/antivirus.json';$config=Get-AVConfig -Path $configPath
    $module=Get-Module Antivirus
    $root=& $module {param($Config)Expand-AVPath $Config.ClamAVPath} $config
    $database=& $module {param($Config)Expand-AVPath $Config.DatabasePath} $config
    # Never manage another program's ClamAV or a database shared outside the bundle.
    if(-not $root.StartsWith(($Paths.App+'\'),[StringComparison]::OrdinalIgnoreCase) -or -not $database.StartsWith(($root.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'external_installation'}
    Assert-RemnexaUpdatePath $root;Assert-RemnexaUpdatePath $database
    if(-not(Test-Path -LiteralPath (Join-Path $root 'clamscan.exe'))){throw 'antivirus_not_installed'}
    $fingerprint=Get-RemnexaDatabaseFingerprint $database
    $staged=Join-Path $Stage 'ClamAV';Copy-RemnexaUpdateTree $root $staged
    $clone=Get-AVConfig -Path $configPath
    $clone.ClamAVPath=$staged;$clone.DatabasePath=Join-Path $staged ([IO.Path]::GetRelativePath($root,$database))
    $clone.LogPath=Join-Path $Stage 'logs';$clone.QuarantinePath=Join-Path $Stage 'quarantine';$clone.AutoCheckUpdates=$false
    $clonePath=Join-Path $Stage 'antivirus.json';Write-RemnexaUpdateJson $clonePath $clone
    # Discard absolute paths from the installed FreshClam configuration in the clone.
    & $module {param($Root,$Database)[void](New-FreshClamConfiguration -ClamAVPath $Root -DatabasePath $Database)} $staged $clone.DatabasePath
    $phaseCommand=Get-Command Set-RemnexaUpdatePhase
    $download={param($Done,$Total)& $phaseCommand $State $Paths 'Downloading' $Done $Total}.GetNewClosure()
    $heartbeat={param($Event)& $phaseCommand $State $Paths 'Preparing'}.GetNewClosure()
    $previousConfig=& $module {$script:AVConfigPath}
    try{
        & $module {param($Path)$script:AVConfigPath=$Path} $clonePath
        if($State.Task.Component -in @('Antivirus','Both')){[void](Update-ClamAVEngine -ConfigPath $clonePath -DownloadProgress $download -Confirm:$false)}
        if($State.Task.Component -in @('Signatures','Both')){[void](Update-ClamAVSignature -ConfigPath $clonePath -Timeout 600 -OnHeartbeat $heartbeat)}
    }finally{& $module {param($Path)$script:AVConfigPath=$Path} $previousConfig}
    $ready=Get-ClamAVStatus -ConfigPath $clonePath
    if(-not $ready.Ready){throw 'Staged antivirus is not ready.'}
    $original=Get-ClamAVStatus -ConfigPath $configPath
    if($original.Version -and (ConvertTo-RemnexaStableVersion $ready.Version) -lt (ConvertTo-RemnexaStableVersion $original.Version)){throw 'Engine downgrade rejected.'}
    # The replacement config must describe its final location, not the staging tree.
    & $module {param($Root,$Database)[void](New-FreshClamConfiguration -ClamAVPath $Root -DatabasePath $Database)} $staged $database
    Set-RemnexaUpdatePhase $State $Paths 'WaitingForScan'
    $watch=[Diagnostics.Stopwatch]::StartNew();$lease=$null
    while(-not $lease){
        Set-RemnexaUpdatePhase $State $Paths 'WaitingForScan'
        try{$lease=& $module {param($Config)Enter-AVScanLease $Config} $config}catch{
            if($watch.Elapsed.TotalMinutes -ge 10){throw 'scan_still_running'}
            Start-Sleep -Milliseconds 500
        }
    }
    $backup=Join-Path (Split-Path -Parent $root) ('.ClamAV-previous-'+$State.Task.Id);$moved=$false;$committed=$false
    try{
        Assert-RemnexaUpdatePath $root;Assert-RemnexaUpdatePath $backup
        if((Get-RemnexaDatabaseFingerprint $database) -cne $fingerprint){throw 'database_changed_retry'}
        Set-RemnexaUpdatePhase $State $Paths 'Installing'
        [IO.Directory]::Move($root,$backup);$moved=$true
        [IO.Directory]::Move($staged,$root)
        $verified=Get-ClamAVStatus -ConfigPath $configPath
        if(-not $verified.Ready -or $verified.Version -cne $ready.Version){throw 'Activated antivirus verification failed.'}
        $State.Task.Version=$verified.Version;$committed=$true
    }catch{
        if($moved -and -not $committed){
            if(Test-Path -LiteralPath $root){Assert-RemnexaUpdatePath $root;[IO.Directory]::Move($root,(Join-Path $Stage 'rejected-ClamAV'))}
            [IO.Directory]::Move($backup,$root)
        }
        throw
    }finally{
        $lease.ReleaseMutex();$lease.Dispose()
        if($committed){try{Remove-RemnexaOwnedStage $backup (Split-Path -Parent $root) '.ClamAV-previous-'}catch{Write-Verbose 'Previous installation retained because files are still in use.'}}
    }
    # A previous metadata snapshot must not imply that a different database is current.
    try{[void](Invoke-ClamAVUpdateCheck -ConfigPath $configPath -StatePath (Join-Path $Paths.Directory 'antivirus-metadata.json') -Force)}catch{Write-Verbose 'Post-update metadata refresh skipped.'}
    return 'Completed'
}

function Test-RemnexaPreparedApplication {
    param([string]$Directory,[string]$Version)
    $manifestPath=Join-Path $Directory 'app/package-manifest.json';Assert-RemnexaUpdatePath $manifestPath
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8|ConvertFrom-Json -DateKind String
    if($manifest.Version -cne $Version -or $manifest.Distribution -ne 'Complete' -or -not $manifest.RuntimeIncluded -or -not $manifest.ClamAVIncluded -or $manifest.Architecture -ne 'x64'){throw 'Not a compatible Complete application update.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $manifest.Files){
        if($entry.Path -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))' -or -not $seen.Add($entry.Path) -or $entry.SHA256 -notmatch '^[a-f0-9]{64}$'){throw 'Unsafe application manifest.'}
        $file=Join-Path $Directory $entry.Path;Assert-RemnexaUpdatePath $file
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.SHA256){throw 'Application update file verification failed.'}
    }
    foreach($required in @('REMNEXA.exe','README.txt','runtime/pwsh.exe','app/REMNEXA.ps1','app/ClamAV/clamscan.exe','app/config/antivirus.json')){if(-not $seen.Contains($required)){throw 'Required Complete application file is missing.'}}
    foreach($db in @('main','daily','bytecode')){if(-not $seen.Contains('app/ClamAV/database/'+$db+'.cvd') -and -not $seen.Contains('app/ClamAV/database/'+$db+'.cld')){throw 'Required signature database is missing.'}}
    if(@(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force).Count -ne $seen.Count+1 -or -not $seen.Contains('REMNEXA.exe')){throw 'Unlisted application update files.'}
    $true
}

function Install-RemnexaApplicationUpdate {
    param($Paths,$State,[string]$ApplicationVersion,[string]$Stage)
    $release=Get-RemnexaOfficialRelease Application
    if((ConvertTo-RemnexaStableVersion $release.Version) -le (ConvertTo-RemnexaStableVersion $ApplicationVersion)){return 'Completed'}
    $archive=Join-Path $Stage 'application.zip';Receive-RemnexaUpdateArchive $release $archive $State $Paths
    $directory=Join-Path $Stage 'application';Expand-RemnexaUpdateArchive $archive $directory
    $candidate=Join-Path $directory ('REMNEXA-'+$release.Version)
    [void](Test-RemnexaPreparedApplication $candidate $release.Version)
    $prepared=Join-Path $Paths.App ('.updates/ready-'+$State.Task.Id)
    Set-RemnexaUpdatePhase $State $Paths 'Installing'
    Assert-RemnexaUpdatePath $prepared;[IO.Directory]::Move($candidate,$prepared)
    $State.Task.Version=$release.Version;$State.Task.PreparedPath=$prepared
    $State.Prepared.ApplicationVersion=$release.Version;$State.Prepared.ApplicationPath=$prepared
    return 'Ready'
}

function Invoke-RemnexaComponentWorker {
    param([string]$ApplicationRoot,[string]$StateDirectory,[string]$Id,[string]$ApplicationVersion,[string]$PowerShellVersion)
    $paths=Get-RemnexaUpdatePaths $ApplicationRoot $StateDirectory
    Assert-RemnexaUpdatePath $paths.Lock
    $lease=[IO.File]::Open($paths.Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $state=$null;$stage=$null
    try{
        $state=Get-RemnexaComponentUpdates $ApplicationRoot $StateDirectory
        if(-not $state.Task -or $state.Task.Id -cne $Id){throw 'Worker request does not match its update task.'}
        Import-Module (Join-Path $paths.App 'Antivirus/Antivirus.psd1')
        Set-RemnexaProgressRendering $false
        if($state.Task.Component -eq 'Check'){
            Set-RemnexaUpdatePhase $state $paths 'Checking'
            Invoke-RemnexaComponentCheck $paths $state $ApplicationVersion $PowerShellVersion
            Set-RemnexaUpdatePhase $state $paths 'Completed'
        }else{
            Set-RemnexaUpdatePhase $state $paths 'Preparing'
            $parent=Join-Path $paths.App '.updates';[void][IO.Directory]::CreateDirectory($parent);Assert-RemnexaUpdatePath $parent
            $stage=Join-Path $parent ('operation-'+$Id);[void][IO.Directory]::CreateDirectory($stage)
            $outcome=switch($state.Task.Component){
                'PowerShell' {Install-RemnexaPowerShellUpdate $paths $state $PowerShellVersion $stage}
                'Application' {Install-RemnexaApplicationUpdate $paths $state $ApplicationVersion $stage}
                default {Install-RemnexaAntivirusUpdate $paths $state $stage}
            }
            $local=Get-RemnexaLocalTools $paths.App $ApplicationVersion $PowerShellVersion
            foreach($row in $state.Components){$row.InstalledVersion=[string]$local[$row.Name]}
            if($state.Task.Component -eq 'Signatures'){$state.Task.Version=$local.Signatures}
            if($state.Task.AfterScanType){
                try{
                    [void](Start-ClamAVBackgroundScan -ScanType $state.Task.AfterScanType -Path @($state.Task.AfterScanPath) -ConfigPath (Join-Path $paths.App 'config/antivirus.json') -Language $state.Task.Language)
                    $state.Task.ScanStarted=$true
                }catch{
                    # The update has already succeeded. A busy scan host must
                    # not turn that into a false installation-failure report.
                    $state.Task.Reason='scan_not_started'
                }
            }
            $state.Task.AfterScanPath=@()
            $state.History=@(@{Id=$Id;Component=$state.Task.Component;Outcome=$outcome;Version=$state.Task.Version;Timestamp=[DateTimeOffset]::UtcNow.ToString('o');PreparedPath=$state.Task.PreparedPath})+@($state.History|Select-Object -First 19)
            Set-RemnexaUpdatePhase $state $paths $outcome -Reason $state.Task.Reason
        }
    }catch{
        if($state -and $state.Task.Id -ceq $Id){
            $outcome=if($_.Exception -is [OperationCanceledException]){'Cancelled'}else{'Failed'}
            $reason=if($_.Exception.Message -in @('external_installation','antivirus_not_installed','scan_still_running','database_changed_retry')){$_.Exception.Message}else{'update_failed'}
            $state.History=@(@{Id=$Id;Component=$state.Task.Component;Outcome=$outcome;Version='';Timestamp=[DateTimeOffset]::UtcNow.ToString('o');PreparedPath=''})+@($state.History|Select-Object -First 19)
            Set-RemnexaUpdatePhase $state $paths $outcome -Reason $reason
            [IO.File]::WriteAllText((Join-Path $paths.Directory ('failure-'+$Id+'.txt')),$_.Exception.Message,[Text.UTF8Encoding]::new($false))
        }
        Write-Verbose $_.Exception.Message
    }finally{
        if($stage){Remove-RemnexaOwnedStage $stage (Split-Path -Parent $stage) 'operation-'}
        $lease.Dispose()
    }
}
