#Requires -Version 7.5
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$archivePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
if ($ExpectedSha256 -and (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $ExpectedSha256) {
    throw 'Package SHA-256 does not match the expected digest.'
}
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = [long]0
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName
        $parts = $name.Split('/')
        if ($name -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+$' -or
            @($parts | Where-Object { $_ -in @('.', '..', '.git', 'runtime', 'ClamAV', 'dist') -or $_ -like 'Backup-*' -or $_ -like '.Backup-*' -or $_ -like '.env*' }).Count -gt 0) {
            throw "Unsafe or forbidden archive entry: $name"
        }
        if ($entries.ContainsKey($name)) { throw "Duplicate archive entry: $name" }
        if ($entry.Length -gt 20MB -or $entry.Length -lt 0) { throw 'An archive entry exceeds the source-package size limit.' }
        $total += $entry.Length
        if ($total -gt 100MB -or $entries.Count -ge 5000) { throw 'The source package exceeds the verification limits.' }
        $entries.Add($name, $entry)
    }
    $manifests = @($entries.Keys | Where-Object { $_ -match '^REMNEXA-[^/]+/package-manifest\.json$' })
    if ($manifests.Count -ne 1) { throw 'Expected exactly one package manifest.' }
    $manifestEntry = $entries[$manifests[0]]
    if ($manifestEntry.Length -gt 2MB) { throw 'The package manifest is too large.' }
    $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.UTF8Encoding]::new($false, $true))
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
    finally { $reader.Dispose() }
    if ($manifest.SchemaVersion -ne 1 -or $manifest.Distribution -ne 'Source' -or
        $manifest.Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$' -or
        $manifest.SourceCommit -notmatch '^[a-f0-9]{40}$' -or $manifest.WorkingTreeDirty -isnot [bool]) {
        throw 'Invalid package metadata.'
    }
    $root = 'REMNEXA-' + $manifest.Version + '/'
    if ($manifests[0] -cne ($root + 'package-manifest.json')) { throw 'Package root and version do not match.' }
    $listed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($manifest.Files)) {
        $name = $root + $record.Path
        if (-not $listed.Add($name) -or -not $entries.ContainsKey($name) -or
            $record.Path -eq 'package-manifest.json' -or $record.SHA256 -notmatch '^[a-f0-9]{64}$' -or
            $record.Bytes -isnot [long] -and $record.Bytes -isnot [int] -or $record.Bytes -lt 0) {
            throw 'Invalid or missing manifest file record.'
        }
        $entry = $entries[$name]
        if ($entry.FullName -cne $name -or $entry.Length -ne $record.Bytes) { throw "Package file metadata does not match: $($record.Path)" }
        $stream = $entry.Open()
        try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() }
        finally { $stream.Dispose() }
        if ($hash -cne $record.SHA256) { throw "Package file integrity failed: $($record.Path)" }
    }
    if ($listed.Count -eq 0 -or $entries.Count -ne ($listed.Count + 1)) { throw 'Unlisted or missing package files.' }
    foreach ($required in @('REMNEXA.ps1','REMNEXA.cmd','LICENSE','README.md','README.de.md','Core/PathSafety.psd1','locales/en.json','locales/de.json','config/antivirus.json')) {
        if (-not $listed.Contains($root + $required)) { throw "Required package file is missing: $required" }
    }
    [PSCustomObject]@{
        Passed = $true
        Version = $manifest.Version
        Distribution = $manifest.Distribution
        FilesVerified = $listed.Count
        SourceCommit = $manifest.SourceCommit
        WorkingTreeDirty = $manifest.WorkingTreeDirty
        SHA256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
finally { $archive.Dispose() }
