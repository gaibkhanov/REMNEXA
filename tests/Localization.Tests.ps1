Describe 'REMNEXA localization resources' {
    It 'loads all supported languages with complete keyed resources' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\Localization.psd1'
        $localeRoot = Join-Path $projectRoot 'locales'
        $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')

        Import-Module -Name $modulePath -Force -ErrorAction Stop
        try {
            $texts = Import-RemnexaLocalization -Root $localeRoot -LanguageCodes $languages -FallbackLanguage 'de'
            $reference=[IO.File]::ReadAllText((Join-Path $localeRoot 'de.json'))|ConvertFrom-Json -AsHashtable
            if ($texts.Count -ne $reference.Count -or $texts.Count -lt 359) { throw "Locale keys were dropped: found $($texts.Count)." }
            foreach ($key in $texts.Keys) {
                $values = @($texts[$key])
                if ($values.Count -ne $languages.Count) { throw "Translation '$key' has an incorrect language count." }
                if (@($values | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
                    throw "Translation '$key' is empty in a supported language."
                }
            }
            if ((Get-RemnexaText -Texts $texts -Key 'MainQuestion' -LanguageCode 'de' -LanguageCodes $languages -FallbackLanguage 'de') -ne 'Was möchtest du tun?') {
                throw 'The German resource did not load the expected UI text.'
            }
            if ((Get-RemnexaText -Texts $texts -Key 'MainQuestion' -LanguageCode 'en' -LanguageCodes $languages -FallbackLanguage 'de') -ne 'What would you like to do?') {
                throw 'The English resource did not load the expected UI text.'
            }
            foreach ($language in $languages) {
                foreach ($status in @('Completed', 'Partial', 'DryRun', 'Cancelled', 'Failed')) {
                    $key = 'OperationStatus' + $status
                    if ([string]::IsNullOrWhiteSpace((Get-RemnexaText -Texts $texts -Key $key -LanguageCode $language -LanguageCodes $languages -FallbackLanguage 'de'))) {
                        throw "Operation result status '$key' is empty in $language."
                    }
                }
            }
        }
        finally {
            Remove-Module Localization -ErrorAction SilentlyContinue
        }
    }

    It 'provides the system overview labels and formatting placeholders in every language' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\Localization.psd1') -Force -ErrorAction Stop
        try {
            $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')
            $texts = Import-RemnexaLocalization -Root (Join-Path $projectRoot 'locales') -LanguageCodes $languages -FallbackLanguage 'de'
            $expected = @{
                SystemSnapshotOS = '0,1'
                SystemSnapshotBuild = '0,1'
                SystemSnapshotCpu = '0'
                SystemSnapshotMemory = '0,1,2'
                SystemSnapshotDrive = '0,1,2,3'
                SystemSnapshotError = '0'
                AVRestoreWarning = '0,1'
                ManagedTraceCount = '0'
                TraceAccessDenied = '0'
                SecurityOtherRegistered = '0'
                OptionalCheckFailed = '0'
                TraceCoveredCount = '0'
            }

            foreach ($language in $languages) {
                if ([string]::IsNullOrWhiteSpace((Get-RemnexaText -Texts $texts -Key 'Home9' -LanguageCode $language -LanguageCodes $languages -FallbackLanguage 'de'))) {
                    throw "The system overview menu label is empty in $language."
                }
                foreach ($key in $expected.Keys) {
                    $value = Get-RemnexaText -Texts $texts -Key $key -LanguageCode $language -LanguageCodes $languages -FallbackLanguage 'de'
                    $indexes = @([regex]::Matches($value, '\{(\d+)\}') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique) -join ','
                    if ($indexes -ne $expected[$key]) { throw "Translation '$key' has invalid format placeholders in ${language}: $indexes." }
                }
            }
        }
        finally {
            Remove-Module Localization -ErrorAction SilentlyContinue
        }
    }

    It 'uses German text when a translation or language is unavailable' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\Localization.psd1') -Force -ErrorAction Stop
        $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')
        $texts = [ordered]@{ Greeting = [string[]]@('Guten Tag', '', 'Hola', 'Bonjour', 'Privet', 'Merhaba') }
        $missingTranslation = Get-RemnexaText -Texts $texts -Key 'Greeting' -LanguageCode 'en' -LanguageCodes $languages -FallbackLanguage 'de'
        $unknownLanguage = Get-RemnexaText -Texts $texts -Key 'Greeting' -LanguageCode 'xx' -LanguageCodes $languages -FallbackLanguage 'de'
        $unknownKey = Get-RemnexaText -Texts $texts -Key 'MissingKey' -LanguageCode 'en' -LanguageCodes $languages -FallbackLanguage 'de'

        if ($missingTranslation -ne 'Guten Tag') { throw 'A missing translation did not fall back to German.' }
        if ($unknownLanguage -ne 'Guten Tag') { throw 'An unsupported language did not fall back to German.' }
        if ($unknownKey -ne 'MissingKey') { throw 'An unknown localization key did not remain diagnosable.' }
        Remove-Module Localization -ErrorAction SilentlyContinue
    }

    It 'remains usable with a malformed non-fallback locale and reports empty translations to self-test' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $projectRoot 'Core\Localization.psd1'
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-LocaleFallback-' + [guid]::NewGuid().ToString('N'))
        $languages = @('de', 'en', 'es', 'fr', 'ru', 'tr')
        $previousModule = Get-Module Localization

        try {
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $projectRoot 'locales\de.json') -Destination (Join-Path $tempRoot 'de.json')
            Set-Content -LiteralPath (Join-Path $tempRoot 'en.json') -Value '{ invalid json' -Encoding UTF8
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            $texts = Import-RemnexaLocalization -Root $tempRoot -LanguageCodes $languages -FallbackLanguage 'de'
            $english = Get-RemnexaText -Texts $texts -Key 'MainQuestion' -LanguageCode 'en' -LanguageCodes $languages -FallbackLanguage 'de'
            if ($english -ne 'Was möchtest du tun?') { throw 'A malformed optional locale prevented German fallback.' }
            if (-not [string]::IsNullOrWhiteSpace([string]$texts['MainQuestion'][1])) {
                throw 'A malformed locale was hidden from the completeness check.'
            }
        }
        finally {
            Remove-Module Localization -ErrorAction SilentlyContinue
            if ($previousModule) { Import-Module -Name $modulePath -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
}
