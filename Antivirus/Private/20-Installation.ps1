function Find-ClamAVInstallation {
    param([AllowNull()][object]$Config)

    if ($null -eq $Config) { $Config = Get-AVConfig }
    $configured = Expand-AVPath ([string]$Config.ClamAVPath)
    if($configured -and (Test-Path -LiteralPath (Join-Path $configured 'clamscan.exe') -PathType Leaf)) { return [IO.Path]::GetFullPath($configured) }
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($configured) { $candidates.Add($configured) }
    foreach ($commandName in @('clamscan.exe', 'clamscan')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { $candidates.Add((Split-Path -Parent $command.Source)) }
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'ClamAV'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'ClamAV' })
    )) {
        if ($candidate) { $candidates.Add($candidate) }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'clamscan.exe') -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Resolve-ClamAVReleaseAsset {
    param([AllowEmptyString()][string]$DownloadUri,[ValidateRange(1,30)][int]$TimeoutSeconds=10)

    if ($DownloadUri -and $DownloadUri -match '\.zip(?:\?.*)?$') {
        $name = [IO.Path]::GetFileName(([uri]$DownloadUri).AbsolutePath)
        $version = if ($name -match '^clamav-([0-9.]+)\.') { $Matches[1] } else { $null }
        return [PSCustomObject]@{ Uri = $DownloadUri; Digest = ''; Name = $name; Version = $version }
    }

    $architectureToken = switch ([string]$env:PROCESSOR_ARCHITECTURE) {
        'ARM64' { '.win.arm64.zip' }
        'x86'   { '.win.win32.zip' }
        default { '.win.x64.zip' }
    }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Cisco-Talos/clamav/releases/latest' -Headers @{ 'User-Agent' = 'REMNEXA-ClamAV' } -TimeoutSec $TimeoutSeconds -MaximumRedirection 0 -ErrorAction Stop
    if(($release.PSObject.Properties['draft'] -and $release.draft) -or ($release.PSObject.Properties['prerelease'] -and $release.prerelease)) { throw 'No supported stable ClamAV release was returned.' }
    $asset = @($release.assets | Where-Object { $_.name.EndsWith($architectureToken, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if ($null -eq $asset) { throw "Im aktuellen offiziellen ClamAV-Release wurde kein Windows-Paket '$architectureToken' gefunden." }
    return [PSCustomObject]@{
        Uri    = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
        Name   = [string]$asset.name
        Version = ([string]$release.tag_name -replace '^clamav-', '')
    }
}

function Assert-ClamAVArchiveDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Digest,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    if ($Digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'Das ClamAV-Archiv besitzt keinen gueltigen SHA-256-Pruefwert. Download wird verworfen.'
    }
    $expectedHash = $Matches[1].ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if ($actualHash -cne $expectedHash) {
        throw 'Die SHA-256-Pruefung des ClamAV-Pakets ist fehlgeschlagen. Installation wurde abgebrochen.'
    }
    return $actualHash
}

function Assert-ClamAVDownloadUri {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Uri)

    $parsedUri = $null
    if ([string]::IsNullOrWhiteSpace($Uri) -or
        -not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsedUri) -or
        $parsedUri.Scheme -ne [uri]::UriSchemeHttps) {
        throw 'ClamAV-Archive duerfen nur ueber eine absolute HTTPS-Adresse geladen werden.'
    }
    return $parsedUri
}

function Assert-ClamAVReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Asset,
        [AllowEmptyString()][string]$ExpectedSha256
    )

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'ExpectedSha256 muss aus genau 64 hexadezimalen Zeichen bestehen.'
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        if ($Asset.Digest -and $Asset.Digest -match '^sha256:([a-fA-F0-9]{64})$' -and $Matches[1] -ine $ExpectedSha256) {
            throw 'ExpectedSha256 stimmt nicht mit dem Digest des offiziellen Releases ueberein.'
        }
        $Asset.Digest = 'sha256:' + $ExpectedSha256
    }
    if ([string]$Asset.Digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
        throw 'Das ClamAV-Release enthaelt keinen gueltigen SHA-256-Pruefwert. Download wird abgebrochen.'
    }

    [void](Assert-ClamAVDownloadUri -Uri ([string]$Asset.Uri))
    return $Asset
}

function New-FreshClamConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ClamAVPath,
        [Parameter(Mandatory = $true)][string]$DatabasePath
    )

    $target = Join-Path $ClamAVPath 'freshclam.conf'
    $sampleCandidates = @(
        (Join-Path $ClamAVPath 'conf_examples\freshclam.conf.sample'),
        (Join-Path $ClamAVPath 'freshclam.conf.sample')
    )
    $sample = @($sampleCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }) | Select-Object -First 1
    if ($sample) {
        $lines = @(Get-Content -LiteralPath $sample -ErrorAction Stop | Where-Object { $_ -notmatch '^\s*Example\s*$' })
        $lines += 'DatabaseDirectory "' + $DatabasePath.Replace('\', '/') + '"'
        $lines | Set-Content -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
    }
    else {
        @(
            'DatabaseMirror database.clamav.net',
            'DNSDatabaseInfo current.cvd.clamav.net',
            'DatabaseDirectory "' + $DatabasePath.Replace('\', '/') + '"'
        ) | Set-Content -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
    }
    return $target
}

function Install-ClamAVPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][scriptblock]$CommitAction,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "ClamAV-Quellordner '$SourceRoot' wurde nicht gefunden."
    }

    $target = [IO.Path]::GetFullPath($TargetPath)
    $pathSeparators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $driveRoot = [IO.Path]::GetPathRoot($target)
    if ($target.TrimEnd($pathSeparators).Equals($driveRoot.TrimEnd($pathSeparators), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsicherer ClamAV-Zielpfad '$target'. Ein Laufwerksstammverzeichnis darf nicht als Installationsziel dienen."
    }

    $parent = Split-Path -Parent $target
    $leaf = Split-Path -Leaf $target
    if ([string]::IsNullOrWhiteSpace($parent) -or [string]::IsNullOrWhiteSpace($leaf)) {
        throw "Unsicherer ClamAV-Zielpfad '$target'."
    }

    $targetExists = Test-Path -LiteralPath $target
    if ($targetExists -and -not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "ClamAV-Ziel '$target' existiert, ist aber kein Ordner."
    }
    if ($targetExists -and -not $Force) {
        throw "Zielordner '$target' existiert bereits. Fuer bewusstes Ersetzen -Force angeben."
    }

    $operationId = [guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $parent ('.' + $leaf + '.install.' + $operationId)
    $backupRoot = if ($targetExists) { Join-Path $parent ('.' + $leaf + '.backup.' + $operationId) } else { $null }
    $targetMoved = $false
    $newTargetPlaced = $false

    try {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Path $stagingRoot -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $SourceRoot -Force -ErrorAction Stop |
            Copy-Item -Destination $stagingRoot -Recurse -Force -ErrorAction Stop

        if (-not (Test-Path -LiteralPath (Join-Path $stagingRoot 'clamscan.exe') -PathType Leaf)) {
            throw 'Das vorbereitete ClamAV-Paket enthaelt keine clamscan.exe.'
        }

        $database = [IO.Path]::GetFullPath((Expand-AVPath $DatabasePath))
        $databaseIsInsideTarget = $database.Equals($target, [StringComparison]::OrdinalIgnoreCase) -or
            (Test-AVPathIsWithin -Path $database -Parent $target)
        if ($databaseIsInsideTarget) {
            $databaseRelative = $database.Substring($target.Length).TrimStart($pathSeparators)
            $stagedDatabase = if ($databaseRelative) { Join-Path $stagingRoot $databaseRelative } else { $stagingRoot }
            if ($targetExists -and $databaseRelative) {
                $existingDatabase = Join-Path $target $databaseRelative
                if (Test-Path -LiteralPath $existingDatabase -PathType Container) {
                    New-Item -ItemType Directory -Path $stagedDatabase -Force -ErrorAction Stop | Out-Null
                    Get-ChildItem -LiteralPath $existingDatabase -Force -ErrorAction Stop |
                        Copy-Item -Destination $stagedDatabase -Recurse -Force -ErrorAction Stop
                }
            }
            New-Item -ItemType Directory -Path $stagedDatabase -Force -ErrorAction Stop | Out-Null
        }
        else {
            New-Item -ItemType Directory -Path $database -Force -ErrorAction Stop | Out-Null
        }

        [void](New-FreshClamConfiguration -ClamAVPath $stagingRoot -DatabasePath $database)

        if ($targetExists) {
            Move-Item -LiteralPath $target -Destination $backupRoot -ErrorAction Stop
            $targetMoved = $true
        }
        Move-Item -LiteralPath $stagingRoot -Destination $target -ErrorAction Stop
        $newTargetPlaced = $true

        & $CommitAction $target $database

        if ($targetMoved) {
            Write-AVLog -Message "Vorheriger ClamAV-Zielordner wurde als Sicherung erhalten: $backupRoot" -Level 'Warning' -Event 'Initialize'
        }
        return [PSCustomObject]@{
            Path = $target
            DatabasePath = $database
            BackupPath = $backupRoot
        }
    }
    catch {
        $installFailure = $_
        $rollbackFailure = $null
        try {
            if ($newTargetPlaced -and (Test-Path -LiteralPath $target -PathType Container)) {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            }
            if ($targetMoved -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
                Move-Item -LiteralPath $backupRoot -Destination $target -ErrorAction Stop
                $targetMoved = $false
            }
        }
        catch {
            $rollbackFailure = $_.Exception.Message
        }

        if ($rollbackFailure) {
            throw "ClamAV-Installation fehlgeschlagen: $($installFailure.Exception.Message) Wiederherstellung ebenfalls fehlgeschlagen: $rollbackFailure Sicherung bleibt unter '$backupRoot' erhalten."
        }
        throw $installFailure
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
