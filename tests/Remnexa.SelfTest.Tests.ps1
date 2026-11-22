Describe 'REMNEXA source-package self-test' {
    It 'passes when optional portable runtime and ClamAV engine are absent' -Tag Windows11Client {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-Pester-' + [guid]::NewGuid().ToString('N'))
        $appRoot = Join-Path $tempRoot 'app'
        $localAppData = Join-Path $tempRoot 'local-app-data'
        $previousLocalAppData = $env:LOCALAPPDATA

        try {
            New-Item -ItemType Directory -Path $appRoot, $localAppData -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $projectRoot 'REMNEXA.ps1') -Destination $appRoot
            foreach ($directory in @('Antivirus', 'assets', 'config', 'Core', 'locales')) {
                Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $appRoot -Recurse
            }

            if (Test-Path -LiteralPath (Join-Path $appRoot 'runtime\pwsh.exe')) {
                throw 'The isolated test package must not contain the optional portable runtime.'
            }
            if (Test-Path -LiteralPath (Join-Path $appRoot 'ClamAV\clamscan.exe')) {
                throw 'The isolated test package must not contain the optional ClamAV engine.'
            }

            $pwshPath = $env:REMNEXA_TEST_PWSH
            if ([string]::IsNullOrWhiteSpace($pwshPath)) {
                $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
                if ($pwshCommand) { $pwshPath = $pwshCommand.Source }
            }
            if ([string]::IsNullOrWhiteSpace($pwshPath) -or -not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
                throw 'PowerShell 7.5 or newer (pwsh.exe) is required to run the application self-test.'
            }

            $env:LOCALAPPDATA = $localAppData
            $output = & $pwshPath -NoLogo -NoProfile -File (Join-Path $appRoot 'REMNEXA.ps1') -SelfTest 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "REMNEXA -SelfTest returned exit code $exitCode. Output: $($output -join ' ')"
            }

            $outputText = $output -join [Environment]::NewLine
            $jsonStart = $outputText.IndexOf('{')
            $jsonEnd = $outputText.LastIndexOf('}')
            if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
                throw "REMNEXA -SelfTest did not return JSON. Output: $outputText"
            }
            $result = $outputText.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json -ErrorAction Stop
            if (-not $result.Passed) {
                $failed = @($result.Checks | Where-Object { -not $_.Passed } | ForEach-Object { $_.Name + ': ' + $_.Details }) -join '; '
                throw "REMNEXA self-test reported failures: $failed"
            }

            foreach ($checkName in @('Portable PowerShell-Laufzeit (optional)', 'ClamAV (optionale Engine)')) {
                $check = @($result.Checks | Where-Object { $_.Name -eq $checkName })
                if ($check.Count -ne 1 -or -not $check[0].Passed) {
                    throw "Expected a passing optional-component check named '$checkName'."
                }
            }

            $localizationCheck = @($result.Checks | Where-Object { $_.Name -eq 'Übersetzungen' })
            if ($localizationCheck.Count -ne 1 -or -not $localizationCheck[0].Passed) {
                $details = if ($localizationCheck.Count -eq 1) { $localizationCheck[0].Details } else { 'check missing' }
                throw "REMNEXA localization completeness check failed: $details"
            }
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'rejects missing, malformed and mismatched ClamAV archive digests' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-DigestTest-' + [guid]::NewGuid().ToString('N'))
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        $archivePath = Join-Path $tempRoot 'archive.zip'

        try {
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            Set-Content -LiteralPath $archivePath -Value 'isolated digest fixture' -Encoding UTF8
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            $module = Get-Module Antivirus
            if ($null -eq $module) { throw 'The Antivirus module did not load.' }

            $expectedHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $actualHash = & $module {
                param($digest, $path)
                Assert-ClamAVArchiveDigest -Digest $digest -ArchivePath $path
            } ('sha256:' + $expectedHash) $archivePath
            if ($actualHash -cne $expectedHash) { throw 'A valid archive digest was not accepted.' }

            foreach ($invalidDigest in @('', 'sha256:xyz', ('sha256:' + ('0' * 64)))) {
                $rejected = $false
                try {
                    & $module {
                        param($digest, $path)
                        Assert-ClamAVArchiveDigest -Digest $digest -ArchivePath $path
                    } $invalidDigest $archivePath | Out-Null
                }
                catch { $rejected = $true }
                if (-not $rejected) { throw "Invalid digest '$invalidDigest' was accepted." }
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'accepts HTTPS download URLs and rejects other schemes' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $module = Get-Module Antivirus
        if ($null -eq $module) { throw 'The Antivirus module did not load.' }

        try {
            $invokeUriCheck = {
                param($value)
                Assert-ClamAVDownloadUri -Uri $value
            }
            $validUri = & $module $invokeUriCheck 'https://example.com/clamav.zip'
            if ($validUri.Scheme -ne [uri]::UriSchemeHttps) { throw 'A valid HTTPS URL was not accepted.' }

            foreach ($invalidUri in @('http://example.com/clamav.zip', 'file:///C:/clamav.zip', 'not-a-uri', '')) {
                $rejected = $false
                try { & $module $invokeUriCheck $invalidUri | Out-Null }
                catch { $rejected = $true }
                if (-not $rejected) { throw "Unsupported download URL '$invalidUri' was accepted." }
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
        }
    }

    It 'requires trusted HTTPS and SHA-256 metadata for install and engine-update assets' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $module = Get-Module Antivirus
        if ($null -eq $module) { throw 'The Antivirus module did not load.' }

        try {
            $digest = 'sha256:' + ('a' * 64)
            $verifiedAsset = [PSCustomObject]@{ Uri = 'https://example.com/clamav.zip'; Digest = $digest }
            $verified = & $module {
                param($asset)
                Assert-ClamAVReleaseAsset -Asset $asset
            } $verifiedAsset
            if ($verified.Digest -cne $digest) { throw 'A valid release digest was changed.' }

            $directAsset = [PSCustomObject]@{ Uri = 'https://example.com/direct.zip'; Digest = '' }
            $direct = & $module {
                param($asset, $expected)
                Assert-ClamAVReleaseAsset -Asset $asset -ExpectedSha256 $expected
            } $directAsset ('b' * 64)
            if ($direct.Digest -cne ('sha256:' + ('b' * 64))) { throw 'A supplied direct-download digest was not applied.' }

            $invalidCases = @(
                [PSCustomObject]@{ Asset = [PSCustomObject]@{ Uri = 'https://example.com/direct.zip'; Digest = '' }; Expected = '' },
                [PSCustomObject]@{ Asset = [PSCustomObject]@{ Uri = 'http://example.com/direct.zip'; Digest = $digest }; Expected = '' },
                [PSCustomObject]@{ Asset = [PSCustomObject]@{ Uri = 'https://example.com/direct.zip'; Digest = $digest }; Expected = ('c' * 64) },
                [PSCustomObject]@{ Asset = [PSCustomObject]@{ Uri = 'https://example.com/direct.zip'; Digest = '' }; Expected = 'not-a-sha256' }
            )
            foreach ($case in $invalidCases) {
                $rejected = $false
                try {
                    & $module {
                        param($asset, $expected)
                        Assert-ClamAVReleaseAsset -Asset $asset -ExpectedSha256 $expected
                    } $case.Asset $case.Expected | Out-Null
                }
                catch { $rejected = $true }
                if (-not $rejected) { throw "Unsafe release asset '$($case.Asset.Uri)' was accepted." }
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Filesystem reparse-point safety' {
    It 'allows a normal path and blocks linked ancestors and uninspectable paths' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\PathSafety.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-PathSafety-' + [guid]::NewGuid().ToString('N'))
        $target = Join-Path $tempRoot 'target'
        $junction = Join-Path $tempRoot 'linked-target'
        $normalFile = Join-Path $target 'marker.txt'

        try {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Set-Content -LiteralPath $normalFile -Value 'isolated path fixture' -Encoding UTF8
            Import-Module -Name $modulePath -Force -ErrorAction Stop

            $normal = Get-RemnexaPathSafety -Path $normalFile
            if (-not $normal.IsSafe) { throw "A normal path was blocked: $($normal.Reason) $($normal.Error)" }

            $missing = Get-RemnexaPathSafety -Path (Join-Path $tempRoot 'missing\file.txt')
            if ($missing.IsSafe -or $missing.Reason -ne 'Uninspectable') {
                throw 'An uninspectable path was not blocked.'
            }

            New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop | Out-Null
            $linked = Get-RemnexaPathSafety -Path (Join-Path $junction 'marker.txt')
            if ($linked.IsSafe) { throw 'A path beneath a junction was not blocked.' }
            $junctionCheck = Get-RemnexaPathSafety -Path $junction
            if ($junctionCheck.IsSafe -or $junctionCheck.Reason -ne 'ReparsePoint') {
                throw 'The junction itself was not identified as a reparse point.'
            }
        }
        finally {
            Remove-Module PathSafety -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $junction) {
                Remove-Item -LiteralPath $junction -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}

Describe 'Transactional ClamAV installation' {
    It 'restores the previous target if configuration commit fails' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-InstallRollback-' + [guid]::NewGuid().ToString('N'))
        $sourceRoot = Join-Path $tempRoot 'package'
        $target = Join-Path $tempRoot 'ClamAV'
        $databasePath = Join-Path $target 'database'

        try {
            New-Item -ItemType Directory -Path $sourceRoot, $databasePath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sourceRoot 'clamscan.exe') -Value 'isolated test executable' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $sourceRoot 'freshclam.conf.sample') -Value 'Example' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target 'legacy.txt') -Value 'keep old install' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $databasePath 'daily.cvd') -Value 'keep signatures' -Encoding ASCII
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            $module = Get-Module Antivirus
            $commitFailure = { param($installedTarget, $installedDatabase) throw 'intentional isolated commit failure' }

            $rejected = $false
            try {
                & $module {
                    param($source, $destination, $database, $commit)
                    Install-ClamAVPayload -SourceRoot $source -TargetPath $destination -DatabasePath $database -CommitAction $commit -Force
                } $sourceRoot $target $databasePath $commitFailure | Out-Null
            }
            catch { $rejected = $_.Exception.Message -match 'intentional isolated commit failure' }

            if (-not $rejected) { throw 'A failing configuration commit was not surfaced.' }
            if (-not (Test-Path -LiteralPath (Join-Path $target 'legacy.txt') -PathType Leaf)) {
                throw 'The prior installation was not restored.'
            }
            if (Test-Path -LiteralPath (Join-Path $target 'clamscan.exe')) {
                throw 'The failed staged installation remained at the target.'
            }
            if (-not (Test-Path -LiteralPath (Join-Path $databasePath 'daily.cvd') -PathType Leaf)) {
                throw 'The prior signature database was not restored.'
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }

    It 'stages the package, preserves signatures, and retains a forced replacement backup' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-InstallSuccess-' + [guid]::NewGuid().ToString('N'))
        $sourceRoot = Join-Path $tempRoot 'package'
        $target = Join-Path $tempRoot 'ClamAV'
        $databasePath = Join-Path $target 'database'

        try {
            New-Item -ItemType Directory -Path $sourceRoot, $databasePath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sourceRoot 'clamscan.exe') -Value 'isolated test executable' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $sourceRoot 'freshclam.conf.sample') -Value 'Example' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target 'legacy.txt') -Value 'keep backup' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $databasePath 'daily.cvd') -Value 'keep signatures' -Encoding ASCII
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            $module = Get-Module Antivirus
            $commitSuccess = { param($installedTarget, $installedDatabase) }

            $result = & $module {
                param($source, $destination, $database, $commit)
                Install-ClamAVPayload -SourceRoot $source -TargetPath $destination -DatabasePath $database -CommitAction $commit -Force
            } $sourceRoot $target $databasePath $commitSuccess

            if (-not (Test-Path -LiteralPath (Join-Path $target 'clamscan.exe') -PathType Leaf)) {
                throw 'The staged engine was not installed at the target.'
            }
            if (-not (Test-Path -LiteralPath (Join-Path $target 'database\daily.cvd') -PathType Leaf)) {
                throw 'The existing signature database was not carried into the staged install.'
            }
            if (-not $result.BackupPath -or -not (Test-Path -LiteralPath (Join-Path $result.BackupPath 'legacy.txt') -PathType Leaf)) {
                throw 'The replaced target was not retained as a backup.'
            }
            if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $target) ('.' + (Split-Path -Leaf $target) + '.install.*'))) {
                throw 'A temporary staging directory was left behind.'
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
}

Describe 'Atomic antivirus configuration updates' {
    It 'replaces the config from a same-directory UTF-8 staging file and cleans up the stage' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        $sourceConfig = Join-Path $projectRoot 'config\antivirus.json'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ConfigAtomic-' + [guid]::NewGuid().ToString('N'))
        $fixtureConfig = Join-Path $tempRoot 'antivirus.json'
        $fixtureLocalAppData = Join-Path $tempRoot 'local-app-data'
        $previousLocalAppData = $env:LOCALAPPDATA

        try {
            New-Item -ItemType Directory -Path $tempRoot, $fixtureLocalAppData -Force | Out-Null
            Copy-Item -LiteralPath $sourceConfig -Destination $fixtureConfig
            $env:LOCALAPPDATA = $fixtureLocalAppData
            Import-Module -Name $modulePath -Force -ErrorAction Stop

            Set-AVConfig -Path $fixtureConfig -Values @{ IncludePUA = $true } -Confirm:$false | Out-Null
            $saved = Get-AVConfig -Path $fixtureConfig
            if (-not $saved.IncludePUA) { throw 'The config value was not written.' }
            if (-not (Test-Path -LiteralPath $fixtureConfig -PathType Leaf)) { throw 'The original config path was not preserved.' }
            $temporaryFiles = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.remnexa.*.tmp' -Force)
            if ($temporaryFiles.Count -gt 0) { throw 'A configuration staging file was left behind.' }
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
            Remove-Module Antivirus -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
}

Describe 'Privacy backup validation' {
    It 'accepts known snapshots and rejects arbitrary or incomplete restore data' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\PrivacyBackupValidation.psd1'
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $module = Get-Module PrivacyBackupValidation
        if ($null -eq $module) { throw 'The privacy backup validation module did not load.' }

        try {
            $allowed = @(
                [PSCustomObject]@{ Path = 'HKCU:\Software\REMNEXA\Test'; Name = 'Enabled'; Type = 'DWord' },
                [PSCustomObject]@{ Path = 'HKCU:\Software\REMNEXA\Test'; Name = 'OriginallyMissing'; Type = 'DWord' }
            )
            $backup = [PSCustomObject]@{
                Timestamp = [DateTimeOffset]::Now.ToString('o')
                Registry = @(
                    [PSCustomObject]@{ Path = 'HKCU:\Software\REMNEXA\Test'; Name = 'Enabled'; Existed = $true; Value = 1; Type = 'DWord' },
                    [PSCustomObject]@{ Path = 'HKCU:\Software\REMNEXA\Test'; Name = 'OriginallyMissing'; Existed = $false; Value = $null; Type = 'DWord' }
                )
                DiagTrack = [PSCustomObject]@{ Exists = $false; StartMode = ''; State = '' }
            }
            $valid = & $module {
                param($candidate, $changes)
                Assert-RemnexaPrivacyBackup -Backup $candidate -AllowedChanges $changes
            } $backup $allowed
            if (-not $valid) { throw 'A complete allowlisted privacy backup was rejected.' }

            $invalidBackups = @()
            $pathTampered = $backup.PSObject.Copy()
            $pathTampered.Registry = @($backup.Registry | ForEach-Object { $_.PSObject.Copy() })
            $pathTampered.Registry[0].Path = 'HKLM:\Software\Unrelated'
            $invalidBackups += $pathTampered

            $incomplete = $backup.PSObject.Copy()
            $incomplete.Registry = @($backup.Registry[0].PSObject.Copy())
            $invalidBackups += $incomplete

            $invalidValue = $backup.PSObject.Copy()
            $invalidValue.Registry = @($backup.Registry | ForEach-Object { $_.PSObject.Copy() })
            $invalidValue.Registry[0].Value = 'not-a-number'
            $invalidBackups += $invalidValue

            foreach ($invalidBackup in $invalidBackups) {
                $rejected = $false
                try {
                    & $module {
                        param($candidate, $changes)
                        Assert-RemnexaPrivacyBackup -Backup $candidate -AllowedChanges $changes
                    } $invalidBackup $allowed | Out-Null
                }
                catch { $rejected = $true }
                if (-not $rejected) { throw 'Tampered privacy restore data was accepted.' }
            }
        }
        finally {
            Remove-Module PrivacyBackupValidation -ErrorAction SilentlyContinue
        }
    }
}
