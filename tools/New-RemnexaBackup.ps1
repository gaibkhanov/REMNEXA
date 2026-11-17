[CmdletBinding()]
param(
    [Parameter()]
    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')]
    [string]$Version = '2.2.0-rc.2'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    throw "Quellordner nicht gefunden: $SourcePath"
}

$sourceRoot = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd('\', '/')
$backupName = "Backup-$Version"
$backupPath = Join-Path $sourceRoot $backupName

if (Test-Path -LiteralPath $backupPath) {
    throw "Backup already exists and will not be overwritten: $backupPath"
}

$stagePath = Join-Path $sourceRoot ('.' + $backupName + '.partial-' + [Guid]::NewGuid().ToString('N'))
$sourcePrefix = $sourceRoot + [IO.Path]::DirectorySeparatorChar
$files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
$pending = New-Object 'System.Collections.Generic.Stack[string]'
$pending.Push($sourceRoot)

while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($entry in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
        $relativePath = $entry.FullName.Substring($sourcePrefix.Length)
        $topLevelName = ($relativePath -split '[\\/]')[0]

        # Source checkpoints must not copy credentials/hooks in Git metadata or
        # generated packages and abandoned staging directories into themselves.
        if ($topLevelName -in @('.git', 'dist') -or
            $topLevelName -like 'Backup-*' -or $topLevelName -like '.Backup-*.partial-*') {
            continue
        }

        if ($directory -eq $sourceRoot -and $entry.PSIsContainer -and $entry.Name -like 'Backup-*') {
            continue
        }

        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }

        if ($entry.PSIsContainer) {
            $pending.Push($entry.FullName)
        }
        elseif ($topLevelName -notlike 'Backup-*' -and $topLevelName -notlike '.Backup-*.partial-*') {
            $files.Add([System.IO.FileInfo]$entry)
        }
    }
}

$totalBytes = [Int64](($files | Measure-Object -Property Length -Sum).Sum)
$driveRoot = [IO.Path]::GetPathRoot($sourceRoot)
$drive = [IO.DriveInfo]::new($driveRoot)
if ($drive.AvailableFreeSpace -lt ($totalBytes + 20MB)) {
    throw ('Not enough free disk space. Required about {0:N2} GB, available {1:N2} GB.' -f ($totalBytes / 1GB), ($drive.AvailableFreeSpace / 1GB))
}

New-Item -ItemType Directory -Path $stagePath | Out-Null
$manifestRows = New-Object 'System.Collections.Generic.List[object]'
$index = 0
Import-Module (Join-Path $PSScriptRoot '..\Core\Progress.psd1') -ErrorAction Stop
$backupProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskBackup') -Total $files.Count -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')

try {
    foreach ($file in $files) {
        $index++
        $relativePath = $file.FullName.Substring($sourcePrefix.Length)
        Update-RemnexaProgress $backupProgress -CurrentItem $relativePath
        $destinationFile = Join-Path $stagePath $relativePath
        $destinationDirectory = Split-Path -Parent $destinationFile
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $destinationFile
        $backupHash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $backupHash) {
            throw "SHA-256 verification failed: $relativePath"
        }

        $manifestRows.Add([PSCustomObject]@{
            Path   = $relativePath
            Bytes  = $file.Length
            SHA256 = $sourceHash
        })

        Update-RemnexaProgress $backupProgress -Completed $index -CurrentItem $relativePath
    }

    $manifestPath = Join-Path $stagePath 'BACKUP-MANIFEST.csv'
    $manifestRows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8
    $backupInfo = @(
        "REMNEXA backup: $Version"
        ('Created UTC: ' + [DateTime]::UtcNow.ToString('o'))
        ('Source: ' + $sourceRoot)
        ('Files verified: ' + $manifestRows.Count)
        ('Payload bytes: ' + $totalBytes)
        'Integrity: SHA-256 verified for every copied file'
        'Top-level Git metadata, dist, backup/staging folders and reparse points are excluded.'
    )
    Set-Content -LiteralPath (Join-Path $stagePath 'BACKUP-INFO.txt') -Value $backupInfo -Encoding UTF8

    $manifestCheck = @(Import-Csv -LiteralPath $manifestPath)
    if ($manifestCheck.Count -ne $files.Count) {
        throw 'Manifest file count does not match the copied file list.'
    }

    Move-Item -LiteralPath $stagePath -Destination $backupPath
    Complete-RemnexaProgress $backupProgress
    [PSCustomObject]@{
        BackupPath       = $backupPath
        FilesVerified    = $manifestRows.Count
        PayloadBytes     = $totalBytes
        Manifest         = Join-Path $backupPath 'BACKUP-MANIFEST.csv'
        Result           = 'Backup created; every copied file passed SHA-256 verification.'
    }
}
catch {
    Complete-RemnexaProgress $backupProgress -Outcome Failed
    throw ("Backup stopped. Existing files were not overwritten. Inspectable staging copy: {0}. Cause: {1}" -f $stagePath, $_.Exception.Message)
}
