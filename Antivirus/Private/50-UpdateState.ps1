# Metadata only. The update worker never invokes installation, freshclam or scans.
function Get-AVUpdateOptions {
    param($Config)
    $defaults=@{ AutoCheckUpdates=$true; UpdateCheckIntervalHours=24; UpdateNetworkTimeoutSeconds=3; UpdateRetryCount=1; UpdateRetryBackoffSeconds=1 }
    foreach($key in @($defaults.Keys)) {
        if($Config.PSObject.Properties[$key]) { $defaults[$key]=$Config.$key }
    }
    if($defaults.AutoCheckUpdates -isnot [bool]) { throw 'Invalid update-check switch.' }
    foreach($rule in @(@('UpdateCheckIntervalHours',1,168),@('UpdateNetworkTimeoutSeconds',1,10),@('UpdateRetryCount',0,2),@('UpdateRetryBackoffSeconds',1,30))) {
        $value=$defaults[$rule[0]]
        if($value -isnot [int] -and $value -isnot [long]) { throw 'Invalid update-check numeric setting.' }
        if($value -lt $rule[1] -or $value -gt $rule[2]) { throw 'Update-check setting exceeds its bounds.' }
    }
    [pscustomobject]$defaults
}

function Get-AVUpdateStatePath {
    param([string]$StatePath)
    if($StatePath) { return [IO.Path]::GetFullPath($StatePath) }
    return Join-Path $env:LOCALAPPDATA 'REMNEXA/AntivirusUpdates.json'
}

function Get-AVUpdateContext {
    param($Config)
    $value=(Expand-AVPath ([string]$Config.ClamAVPath))+'|'+(Expand-AVPath ([string]$Config.DatabasePath))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant()))).ToLowerInvariant()
}

function Enter-AVUpdateLease {
    param([string]$StatePath)
    $directory=Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop|Out-Null
    if(-not (Get-RemnexaPathSafety -Path $directory).IsSafe) { throw 'Unsafe metadata directory.' }
    $lockPath=$StatePath+'.lock'
    if((Test-Path -LiteralPath $lockPath) -and -not (Get-RemnexaPathSafety -Path $lockPath).IsSafe) { throw 'Unsafe metadata lock.' }
    [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}

function New-AVUpdateState {
    param([string]$Context)
    [pscustomobject]@{
        schemaVersion=1; context=$Context; lastSuccessfulCheckUtc=$null; lastAttemptUtc=$null; nextRetryUtc=$null; failureCount=0; status='unknown'
        engine=[pscustomobject]@{installedVersion=$null;availableVersion=$null;updateAvailable=$false;status='unknown';canUpdate=$false;reason='';checkedUtc=$null}
        signatures=[pscustomobject]@{status='unknown';lastSuccessfulUpdateUtc=$null;recommended=$false;canUpdate=$false;databases=@();checkedUtc=$null}
    }
}

function ConvertTo-AVSemanticVersion {
    param([string]$Version)
    if($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$' -or $Version.Length -gt 80) { throw 'Invalid ClamAV semantic version.' }
    [Management.Automation.SemanticVersion]::Parse($Version)
}

function Test-AVUpdateTimestamp {
    param($Value)
    if($null -eq $Value) { return $true }
    $time=[DateTimeOffset]::MinValue
    return ($Value -is [string] -and [DateTimeOffset]::TryParse($Value,[ref]$time) -and $time.Offset -eq [TimeSpan]::Zero -and $time -le [DateTimeOffset]::UtcNow.AddMinutes(5))
}

function Read-AVUpdateState {
    param([string]$Path,[string]$Context)
    $empty=New-AVUpdateState $Context
    try {
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)) { return $empty }
        if((Get-Item -LiteralPath $Path).Length -gt 64KB -or -not (Get-RemnexaPathSafety -Path $Path).IsSafe) { return $empty }
        $state=[IO.File]::ReadAllText($Path)|ConvertFrom-Json -DateKind String -ErrorAction Stop
        $allowed=@('current','update_available','unknown','offline','check_failed','not_installed')
        if($state.schemaVersion -ne 1 -or $state.context -cne $Context -or $state.status -notin $allowed -or $state.engine.status -notin $allowed -or $state.signatures.status -notin $allowed) { return $empty }
        foreach($stamp in @($state.lastSuccessfulCheckUtc,$state.lastAttemptUtc,$state.signatures.lastSuccessfulUpdateUtc,$state.engine.checkedUtc,$state.signatures.checkedUtc)) {
            if(-not(Test-AVUpdateTimestamp $stamp)) { return $empty }
        }
        if($state.nextRetryUtc) {
            $retry=[DateTimeOffset]::Parse($state.nextRetryUtc)
            if($retry.Offset -ne [TimeSpan]::Zero -or $retry -gt [DateTimeOffset]::UtcNow.AddHours(2)) { return $empty }
        }
        if($state.failureCount -lt 0 -or $state.failureCount -gt 10 -or $state.engine.updateAvailable -isnot [bool] -or $state.engine.canUpdate -isnot [bool] -or $state.signatures.recommended -isnot [bool] -or $state.signatures.canUpdate -isnot [bool]) { return $empty }
        foreach($version in @($state.engine.installedVersion,$state.engine.availableVersion)) { if($version) { [void](ConvertTo-AVSemanticVersion $version) } }
        if($state.engine.reason -notin @('','hash_unavailable','source_unavailable','version_unknown')) { return $empty }
        if(@($state.signatures.databases).Count -gt 3) { return $empty }
        foreach($db in $state.signatures.databases) {
            if($db.name -notin @('main','daily','bytecode') -or $db.status -notin $allowed) { return $empty }
            foreach($version in @($db.installedVersion,$db.availableVersion)) { if($null -ne $version -and ([string]$version -notmatch '^\d{1,10}$')) { return $empty } }
        }
        return $state
    }
    catch { return $empty }
}

function Save-AVUpdateState {
    param($State,[string]$Path)
    $directory=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop|Out-Null
    if(-not (Get-RemnexaPathSafety -Path $directory).IsSafe) { throw 'Unsafe update-state directory.' }
    if((Test-Path -LiteralPath $Path) -and -not (Get-RemnexaPathSafety -Path $Path).IsSafe) { throw 'Unsafe update-state path.' }
    $temporary=Join-Path $directory ('.updates-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $backup=$temporary+'.bak'
    try {
        [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        if((Read-AVUpdateState -Path $temporary -Context $State.context).lastAttemptUtc -ne $State.lastAttemptUtc) { throw 'Staged update state did not validate.' }
        if(Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporary,$Path,$backup) }
        else { [IO.File]::Move($temporary,$Path) }
    }
    finally {
        foreach($file in @($temporary,$backup)) { if(Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } }
    }
}

function Test-AVUpdateDue {
    param($State,$Options,[switch]$Force)
    if($Force) { return $true }
    $now=[DateTimeOffset]::UtcNow
    if($State.nextRetryUtc -and [DateTimeOffset]::Parse($State.nextRetryUtc) -gt $now) { return $false }
    if($State.status -in @('offline','check_failed')) { return $true }
    return (-not $State.lastSuccessfulCheckUtc -or [DateTimeOffset]::Parse($State.lastSuccessfulCheckUtc).AddHours($Options.UpdateCheckIntervalHours) -le $now)
}

function Get-AVLocalDatabaseVersions {
    param($Config)
    $root=Expand-AVPath ([string]$Config.DatabasePath)
    foreach($name in @('main','daily','bytecode')) {
        $version=$null
        $versions=[Collections.Generic.HashSet[long]]::new()
        $unreliable=$false
        foreach($extension in @('cld','cvd')) {
            $path=Join-Path $root ($name+'.'+$extension)
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            try {
                if(-not (Get-RemnexaPathSafety -Path $path).IsSafe) { $unreliable=$true;continue }
                $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try { $buffer=[byte[]]::new(512);$read=$stream.Read($buffer,0,512);$header=[Text.Encoding]::ASCII.GetString($buffer,0,$read) } finally { $stream.Dispose() }
                if($read -eq 512 -and $header -match '^ClamAV-VDB:[^:]+:(\d{1,10}):') { [void]$versions.Add([long]$Matches[1]) }
                else { $unreliable=$true }
            }
            catch { $unreliable=$true }
        }
        if(-not $unreliable -and $versions.Count -eq 1) { $version=@($versions)[0] }
        [pscustomobject]@{name=$name;installedVersion=$version;availableVersion=$null;status='unknown'}
    }
}

function ConvertFrom-AVDnsUpdateInfo {
    param([string]$Text)
    # Official libfreshclam_internal.c:textrecordfield: main=1,daily=2,bytecode=7.
    # DNS is advisory metadata, never an installation or software-release source.
    $parts=$Text.Trim().Split(':')
    if($Text.Length -gt 1024 -or $parts.Count -lt 8) { throw 'Invalid ClamAV DNS metadata.' }
    foreach($index in @(1,2,3,7)) { if($parts[$index] -notmatch '^\d{1,10}$') { throw 'Invalid database version in DNS metadata.' } }
    $age=([DateTimeOffset]::UtcNow-[DateTimeOffset]::FromUnixTimeSeconds([long]$parts[3])).TotalHours
    if($age -lt -0.1 -or $age -gt 3) { throw 'ClamAV DNS metadata is stale.' }
    @{main=[long]$parts[1];daily=[long]$parts[2];bytecode=[long]$parts[7]}
}

function Get-AVRemoteDatabaseVersions {
    param([int]$TimeoutSeconds=3)
    # Use Windows DNS, but bound the native query with the configured deadline.
    # The command is a fixed application literal and contains no foreign input.
    $command='$ErrorActionPreference="Stop"; Resolve-DnsName -Name current.cvd.clamav.net -Type TXT -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.PSObject.Properties["Strings"] } | ForEach-Object { $_.Strings -join "" } | Select-Object -First 1 | ConvertTo-Json -Compress'
    $run=Invoke-AVNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-Command',$command) -TimeoutSeconds $TimeoutSeconds
    if($run.ExitCode -ne 0) { throw 'Official database DNS endpoint is offline or unavailable.' }
    if($run.StandardOutput.Length -gt 2048) { throw 'Invalid DNS metadata size.' }
    $text=$run.StandardOutput|ConvertFrom-Json -ErrorAction Stop
    if($text -isnot [string]) { throw 'Invalid DNS metadata response.' }
    ConvertFrom-AVDnsUpdateInfo -Text $text
}

function Set-AVEngineUpdateComparison {
    param($State,$Asset)
    $latest=ConvertTo-AVSemanticVersion ([string]$Asset.Version)
    $State.engine.availableVersion=$latest.ToString()
    if(-not $State.engine.installedVersion) { $State.engine.reason='version_unknown';return }
    $installed=ConvertTo-AVSemanticVersion $State.engine.installedVersion
    $newer=$latest.CompareTo($installed) -gt 0
    $State.engine.updateAvailable=$newer
    $State.engine.status=if($newer){'update_available'}else{'current'}
    $State.engine.canUpdate=$false
    try {
        [void](Assert-ClamAVReleaseAsset -Asset $Asset)
        $uri=[uri]$Asset.Uri
        if($uri.Host -ine 'github.com' -or $uri.AbsolutePath -notmatch '^/Cisco-Talos/clamav/releases/download/') { throw 'Unexpected official release source.' }
        $State.engine.canUpdate=$newer
        $State.engine.reason=''
    }
    catch { $State.engine.reason='hash_unavailable' }
}

function Set-AVSignatureUpdateComparison {
    param($State,[hashtable]$Available)
    foreach($db in $State.signatures.databases) {
        if(-not $Available.ContainsKey($db.name) -or [string]$Available[$db.name] -notmatch '^\d{1,10}$') { throw 'Invalid remote database metadata.' }
        $db.availableVersion=$Available[$db.name]
        $db.status=if($null -eq $db.installedVersion){'unknown'}elseif([long]$db.availableVersion -gt [long]$db.installedVersion){'update_available'}else{'current'}
    }
    $states=@($State.signatures.databases.status)
    $State.signatures.status=if($states -contains 'update_available'){'update_available'}elseif($states.Count -eq 3 -and @($states|Where-Object{$_ -ne 'current'}).Count -eq 0){'current'}else{'unknown'}
    $State.signatures.recommended=$State.signatures.status -ne 'current'
}

function Get-AVUpdateFailureStatus {
    param($Failure)
    $exception=$Failure.Exception
    while($exception) {
        if($exception -is [Net.Sockets.SocketException]) { return 'offline' }
        if($exception -is [Net.Http.HttpRequestException] -and $exception.HttpRequestError -in @([Net.Http.HttpRequestError]::NameResolutionError,[Net.Http.HttpRequestError]::ConnectionError)) { return 'offline' }
        $exception=$exception.InnerException
    }
    $detail=[string]$Failure
    if($detail -match '(?i)offline|no internet|name.*resolution|no such host|host.*unknown|network.*unreachable|connection.*refused|connection.*failed|could not.*resolv') { return 'offline' }
    return 'check_failed'
}

function Invoke-AVUpdateMetadataCheck {
    param([string]$ConfigPath,[string]$StatePath,[switch]$Force)
    $config=Get-AVConfig -Path $ConfigPath
    $options=Get-AVUpdateOptions $config
    $state=Read-AVUpdateState -Path $StatePath -Context (Get-AVUpdateContext $config)
    if(-not(Test-AVUpdateDue $state $options -Force:$Force)) { return $state }
    $state.lastAttemptUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $root=Find-ClamAVInstallation -Config $config
    if(-not $root) {
        $state.status='not_installed';$state.engine.status='not_installed';$state.signatures.status='not_installed'
        Save-AVUpdateState $state $StatePath;return $state
    }
    $state.engine.status='unknown';$state.engine.updateAvailable=$false;$state.engine.canUpdate=$false
    try {
        $run=Invoke-AVNativeProcess -FilePath (Join-Path $root 'clamscan.exe') -ArgumentList @('--version') -TimeoutSeconds $options.UpdateNetworkTimeoutSeconds
        if($run.ExitCode -eq 0 -and $run.StandardOutput -match 'ClamAV\s+([^\s/]+)') { $state.engine.installedVersion=(ConvertTo-AVSemanticVersion $Matches[1]).ToString() }
    }
    catch { $state.engine.installedVersion=$null }
    $state.signatures.databases=@(Get-AVLocalDatabaseVersions $config)
    $state.signatures.canUpdate=Test-Path -LiteralPath (Join-Path $root 'freshclam.exe') -PathType Leaf
    $state.signatures.status='unknown';$state.signatures.recommended=$true
    $engineOK=$false;$signaturesOK=$false;$networkReached=$false;$failureStatus='offline'
    for($attempt=0;$attempt -le $options.UpdateRetryCount;$attempt++) {
        if(-not $engineOK) {
            try {
                $asset=Resolve-ClamAVReleaseAsset -DownloadUri '' -TimeoutSeconds $options.UpdateNetworkTimeoutSeconds
                $networkReached=$true
                Set-AVEngineUpdateComparison $state $asset
                $state.engine.checkedUtc=[DateTimeOffset]::UtcNow.ToString('o')
                $engineOK=$true
            }
            catch { $state.engine.reason='source_unavailable';if((Get-AVUpdateFailureStatus $_) -eq 'check_failed'){$failureStatus='check_failed'} }
        }
        if(-not $signaturesOK) {
            try { $available=Get-AVRemoteDatabaseVersions -TimeoutSeconds $options.UpdateNetworkTimeoutSeconds;Set-AVSignatureUpdateComparison $state $available;$state.signatures.checkedUtc=[DateTimeOffset]::UtcNow.ToString('o');$signaturesOK=$true;$networkReached=$true }
            catch { $state.signatures.status='unknown';if((Get-AVUpdateFailureStatus $_) -eq 'check_failed'){$failureStatus='check_failed'} }
        }
        if($engineOK -and $signaturesOK) { break }
        if($attempt -lt $options.UpdateRetryCount) { Start-Sleep -Milliseconds ([int](1000*$options.UpdateRetryBackoffSeconds*[Math]::Pow(2,$attempt))) }
    }
    if($engineOK -and $signaturesOK) {
        $state.lastSuccessfulCheckUtc=[DateTimeOffset]::UtcNow.ToString('o');$state.failureCount=0;$state.nextRetryUtc=$null
        $state.status=if($state.engine.updateAvailable -or $state.signatures.status -eq 'update_available'){'update_available'}elseif($state.engine.status -eq 'current' -and $state.signatures.status -eq 'current'){'current'}else{'unknown'}
    }
    else {
        $state.failureCount=[Math]::Min(10,$state.failureCount+1)
        $state.nextRetryUtc=[DateTimeOffset]::UtcNow.AddSeconds([Math]::Min(3600,60*[Math]::Pow(2,$state.failureCount-1))).ToString('o')
        $state.status=if($networkReached){'check_failed'}else{$failureStatus}
        if(-not $engineOK) { $state.engine.status=$state.status }
        if(-not $signaturesOK) { $state.signatures.status=$state.status }
    }
    Save-AVUpdateState $state $StatePath
    return $state
}
