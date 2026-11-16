Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Import-RemnexaLocalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$LanguageCodes,
        [Parameter(Mandatory = $true)][string]$FallbackLanguage
    )

    if ($LanguageCodes.Count -eq 0 -or @($LanguageCodes | Select-Object -Unique).Count -ne $LanguageCodes.Count) {
        throw 'Localization language codes must be non-empty and unique.'
    }
    if ($LanguageCodes -notcontains $FallbackLanguage) {
        throw "Fallback language '$FallbackLanguage' is not in the supported language list."
    }
    foreach ($code in $LanguageCodes) {
        if ($code -notmatch '^[a-z]{2}$') { throw "Invalid locale code '$code'." }
    }

    $resources = @{}
    foreach ($code in $LanguageCodes) {
        $path = Join-Path $Root ($code + '.json')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            if ($code -eq $FallbackLanguage) { throw "Fallback locale resource is missing: '$path'." }
            $resources[$code] = [ordered]@{}
            continue
        }

        try {
            $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
            $resource = ConvertFrom-Json -InputObject $json -AsHashtable -ErrorAction Stop
            if ($resource -isnot [System.Collections.IDictionary]) {
                throw "Locale resource '$path' must contain a JSON object."
            }
            foreach ($key in $resource.Keys) {
                if ([string]::IsNullOrWhiteSpace([string]$key) -or $resource[$key] -isnot [string]) {
                    throw "Locale resource '$path' contains an invalid key or non-string value."
                }
            }
            $resources[$code] = $resource
        }
        catch {
            if ($code -eq $FallbackLanguage) { throw "Could not load fallback locale '$path': $($_.Exception.Message)" }
            $resources[$code] = [ordered]@{}
        }
    }

    $fallback = $resources[$FallbackLanguage]
    if ($fallback.Count -eq 0) { throw "Fallback locale '$FallbackLanguage' contains no text keys." }
    foreach ($key in $fallback.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$fallback[$key])) {
            throw "Fallback locale contains empty text for '$key'."
        }
    }
    foreach ($code in $LanguageCodes) {
        if ($code -eq $FallbackLanguage) { continue }
        foreach ($key in $resources[$code].Keys) {
            if (-not $fallback.Contains($key)) {
                throw "Locale '$code' contains key '$key' absent from fallback locale '$FallbackLanguage'."
            }
        }
    }

    $texts = [ordered]@{}
    foreach ($key in $fallback.Keys) {
        $translations = [System.Array]::CreateInstance([string], $LanguageCodes.Count)
        for ($index = 0; $index -lt $LanguageCodes.Count; $index++) {
            $resource = $resources[$LanguageCodes[$index]]
            if ($resource.Contains($key)) { $translations[$index] = [string]$resource[$key] }
            else { $translations[$index] = '' }
        }
        $texts[$key] = $translations
    }
    return $texts
}

function Get-RemnexaText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Texts,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$LanguageCode,
        [Parameter(Mandatory = $true)][string[]]$LanguageCodes,
        [Parameter(Mandatory = $true)][string]$FallbackLanguage
    )

    if (-not $Texts.Contains($Key)) { return $Key }
    $fallbackIndex = [Array]::IndexOf($LanguageCodes, $FallbackLanguage)
    if ($fallbackIndex -lt 0) { throw "Fallback language '$FallbackLanguage' is not in the supported language list." }
    $index = [Array]::IndexOf($LanguageCodes, $LanguageCode)
    if ($index -lt 0) { $index = $fallbackIndex }
    $translations = @($Texts[$Key])
    if ($index -ge $translations.Count -or [string]::IsNullOrWhiteSpace([string]$translations[$index])) {
        $index = $fallbackIndex
    }
    $text = if ($index -lt $translations.Count) { [string]$translations[$index] } else { '' }
    if ([string]::IsNullOrWhiteSpace($text)) { return $Key }
    return $text
}

Export-ModuleMember -Function Import-RemnexaLocalization, Get-RemnexaText
