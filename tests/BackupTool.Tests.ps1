Describe 'REMNEXA backup tool' {
    It 'excludes Git metadata, generated packages and abandoned staging content' {
        $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\New-RemnexaBackup.ps1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-BackupExclusions-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            foreach ($folder in @('.git','dist','.Backup-1.0.0.partial-test')) {
                $path = Join-Path $tempRoot $folder
                New-Item -ItemType Directory -Path $path | Out-Null
                Set-Content -LiteralPath (Join-Path $path 'private.txt') -Value 'excluded fixture'
            }
            Set-Content -LiteralPath (Join-Path $tempRoot 'active.txt') -Value 'active fixture'
            $result = & $scriptPath -SourcePath $tempRoot -Version '1.2.3'
            if ($result.FilesVerified -ne 1) { throw 'Generated or private metadata entered the source checkpoint.' }
            $entries = @(Import-Csv -LiteralPath $result.Manifest)
            if ($entries.Count -ne 1 -or $entries[0].Path -ne 'active.txt') { throw 'Unexpected backup manifest.' }
        }
        finally {
            $resolved = [IO.Path]::GetFullPath($tempRoot)
            if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'REMNEXA-BackupExclusions-*' -and (Test-Path -LiteralPath $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
        }
    }

    It 'copies active files, excludes historical backups and verifies the manifest' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $scriptPath = Join-Path $projectRoot 'tools\New-RemnexaBackup.ps1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-BackupTool-' + [guid]::NewGuid().ToString('N'))
        $backupPath = Join-Path $tempRoot 'Backup-1.2.3'

        try {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'nested') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'Backup-0.9.0') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot 'root.txt') -Value 'root fixture' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $tempRoot 'nested\child.txt') -Value 'nested fixture' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $tempRoot 'Backup-0.9.0\old.txt') -Value 'historical fixture' -Encoding UTF8

            $result = & $scriptPath -SourcePath $tempRoot -Version '1.2.3'
            if ($result.FilesVerified -ne 2) { throw 'The backup did not contain exactly the active fixture files.' }

            $manifest = @(Import-Csv -LiteralPath (Join-Path $backupPath 'BACKUP-MANIFEST.csv'))
            if ($manifest.Count -ne 2) { throw 'The manifest did not contain exactly two active files.' }
            if (Test-Path -LiteralPath (Join-Path $backupPath 'Backup-0.9.0')) { throw 'A historical backup was copied into the new backup.' }
            foreach ($entry in $manifest) {
                $copiedPath = Join-Path $backupPath $entry.Path
                if (-not (Test-Path -LiteralPath $copiedPath -PathType Leaf)) { throw "A manifest file is missing: $($entry.Path)" }
                if ((Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "A manifest hash is wrong: $($entry.Path)" }
            }
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }

    It 'refuses to overwrite an existing backup' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $scriptPath = Join-Path $projectRoot 'tools\New-RemnexaBackup.ps1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-BackupNoOverwrite-' + [guid]::NewGuid().ToString('N'))
        $backupPath = Join-Path $tempRoot 'Backup-1.2.3'

        try {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            $sentinel = Join-Path $backupPath 'keep.txt'
            Set-Content -LiteralPath $sentinel -Value 'preserve this file' -Encoding UTF8
            $before = (Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
            $rejected = $false
            try { & $scriptPath -SourcePath $tempRoot -Version '1.2.3' | Out-Null }
            catch { $rejected = $true }
            if (-not $rejected) { throw 'The backup tool did not reject an existing destination.' }
            if ((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ne $before) { throw 'The existing backup was changed.' }
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
}
