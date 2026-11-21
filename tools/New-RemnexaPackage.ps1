#Requires -Version 7.5
[CmdletBinding()]
param(
    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')][string]$Version,
    [string]$GitPath = 'git'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path.TrimEnd('\', '/')
Import-Module (Join-Path $PSScriptRoot '..\Core\PathSafety.psd1') -Force -ErrorAction Stop
if (-not (Get-RemnexaPathSafety -Path $root).IsSafe) { throw 'Source root has an unsafe path component.' }
$git = (Get-Command -Name $GitPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$gitRoot = & $git -C $root rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($gitRoot).TrimEnd('\', '/') -ne $root) { throw 'SourcePath must be the Git checkout root.' }
$commit = & $git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') { throw 'Could not determine source commit.' }
$status = @(& $git -C $root status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect source status.' }
if ($status.Count -gt 0) { throw 'Commit or stash source changes before building a release package.' }
$paths = @(& $git -C $root -c core.quotepath=false ls-files)
if ($LASTEXITCODE -ne 0 -or $paths.Count -eq 0) { throw 'No tracked source files were returned.' }
$application = [IO.File]::ReadAllText((Join-Path $root 'REMNEXA.ps1'))
$versionMatch = [regex]::Match($application, '\$script:CleanerVersion\s*=\s*''(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?)''')
if (-not $versionMatch.Success -or $versionMatch.Groups[1].Value -cne $Version) { throw 'Package version does not match the application version.' }
foreach ($path in $paths) {
    $parts = $path.Split('/')
    if ($path -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -or
        @($parts | Where-Object { $_ -in @('.', '..', '.git', 'runtime', 'ClamAV', 'dist') -or $_ -like 'Backup-*' -or $_ -like '.Backup-*' -or $_ -like '.env*' }).Count -gt 0 -or
        $path -eq 'package-manifest.json' -or $path -like 'tools/Modules/*') { throw "Forbidden source-package path: $path" }
    if (-not (Get-RemnexaPathSafety -Path (Join-Path $root $path)).IsSafe) { throw "Unsafe source path: $path" }
}

$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $output)) { New-Item -ItemType Directory -Path $output | Out-Null }
if (-not (Get-RemnexaPathSafety -Path $output).IsSafe) { throw 'Output directory has an unsafe path component.' }
$name = 'REMNEXA-' + $Version + '-source.zip'
$destination = Join-Path $output $name
$checksum = $destination + '.sha256'
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $checksum)) { throw 'Package or checksum already exists; refusing to overwrite.' }
$temporary = Join-Path $output ('.package-' + [guid]::NewGuid().ToString('N') + '.zip')
$archive = $null
$records = [Collections.Generic.List[object]]::new()
try {
    $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($path in ($paths | Sort-Object)) {
        $source = Join-Path $root $path
        # Recheck directly before reading; this reduces, not eliminates, races.
        if (-not (Get-RemnexaPathSafety -Path $source).IsSafe) { throw "Unsafe source path: $path" }
        $stream = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($stream.Length -gt 20MB) { throw "Source file exceeds package limits: $path" }
            $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
            $records.Add([PSCustomObject]@{ Path=$path; Bytes=$stream.Length; SHA256=$hash })
            $stream.Position = 0
            $entry = $archive.CreateEntry(('REMNEXA-' + $Version + '/' + $path), [IO.Compression.CompressionLevel]::Optimal)
            $target = $entry.Open()
            try { $stream.CopyTo($target) } finally { $target.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    $manifest = [ordered]@{ SchemaVersion=1; Version=$Version; Distribution='Source'; SourceCommit=$commit; WorkingTreeDirty=$false; Files=$records.ToArray() }
    $entry = $archive.CreateEntry(('REMNEXA-' + $Version + '/package-manifest.json'))
    $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 6)) } finally { $writer.Dispose() }
    $archive.Dispose(); $archive = $null
    $verification = & (Join-Path $PSScriptRoot 'Test-RemnexaPackage.ps1') -Path $temporary
    if (-not $verification.Passed) { throw 'Generated package failed verification.' }
    Move-Item -LiteralPath $temporary -Destination $destination -ErrorAction Stop
    $line = $verification.SHA256 + '  ' + $name + [Environment]::NewLine
    $checksumStream = [IO.File]::Open($checksum, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [Text.Encoding]::UTF8.GetBytes($line); $checksumStream.Write($bytes, 0, $bytes.Length) }
    finally { $checksumStream.Dispose() }
    [PSCustomObject]@{ Package=$destination; Checksum=$checksum; Version=$Version; FilesVerified=$verification.FilesVerified; SourceCommit=$commit; SHA256=$verification.SHA256 }
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
