Describe 'REMNEXA application settings' {
    It 'saves and replaces the language setting atomically' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\AppSettings.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-AppSettings-' + [guid]::NewGuid().ToString('N'))
        $settingsPath = Join-Path $tempRoot 'settings.json'
        $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')

        try {
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            Save-RemnexaLanguage -Path $settingsPath -Language 'en' -SupportedLanguages $languages
            if ((Get-RemnexaLanguage -Path $settingsPath -SupportedLanguages $languages -FallbackLanguage 'de') -ne 'en') {
                throw 'The saved language could not be read back.'
            }

            Save-RemnexaLanguage -Path $settingsPath -Language 'TR' -SupportedLanguages $languages
            if ((Get-RemnexaLanguage -Path $settingsPath -SupportedLanguages $languages -FallbackLanguage 'de') -ne 'tr') {
                throw 'The replaced language setting was not canonicalized.'
            }

            if (@(Get-ChildItem -LiteralPath $tempRoot -Filter '*.remnexa.*.tmp*' -Force).Count -gt 0) {
                throw 'A settings staging file was left behind.'
            }

            $beforeRejectedWrite = [IO.File]::ReadAllText($settingsPath)
            $rejected = $false
            try { Save-RemnexaLanguage -Path $settingsPath -Language 'xx' -SupportedLanguages $languages }
            catch { $rejected = $true }
            if (-not $rejected) { throw 'An unsupported language was saved.' }
            if ([IO.File]::ReadAllText($settingsPath) -cne $beforeRejectedWrite) {
                throw 'Rejecting an unsupported language changed the existing settings file.'
            }
        }
        finally {
            Remove-Module AppSettings -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }

    It 'uses the configured fallback for missing and malformed settings' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\AppSettings.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-AppSettingsFallback-' + [guid]::NewGuid().ToString('N'))
        $settingsPath = Join-Path $tempRoot 'settings.json'
        $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')

        try {
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            if ((Get-RemnexaLanguage -Path $settingsPath -SupportedLanguages $languages -FallbackLanguage 'de') -ne 'de') {
                throw 'A missing settings file did not use the fallback language.'
            }

            Set-Content -LiteralPath $settingsPath -Value '{ invalid json' -Encoding UTF8
            if ((Get-RemnexaLanguage -Path $settingsPath -SupportedLanguages $languages -FallbackLanguage 'de') -ne 'de') {
                throw 'Malformed settings did not use the fallback language.'
            }
        }
        finally {
            Remove-Module AppSettings -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
}
