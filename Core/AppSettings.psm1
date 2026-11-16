Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-RemnexaLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$SupportedLanguages,
        [Parameter(Mandatory = $true)][string]$FallbackLanguage
    )

    if ($SupportedLanguages -notcontains $FallbackLanguage) {
        throw "Fallback language '$FallbackLanguage' is not supported."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $FallbackLanguage }

    try {
        $settings = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($null -eq $settings -or $settings -isnot [System.Collections.IDictionary]) { return $FallbackLanguage }
        $savedLanguage = [string]$settings['Language']
        foreach ($language in $SupportedLanguages) {
            if ($savedLanguage.Equals($language, [StringComparison]::OrdinalIgnoreCase)) { return $language }
        }
    }
    catch { return $FallbackLanguage }
    return $FallbackLanguage
}

function Save-RemnexaLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string[]]$SupportedLanguages
    )

    $canonicalLanguage = $null
    foreach ($supportedLanguage in $SupportedLanguages) {
        if ($Language.Equals($supportedLanguage, [StringComparison]::OrdinalIgnoreCase)) {
            $canonicalLanguage = $supportedLanguage
            break
        }
    }
    if ($null -eq $canonicalLanguage) { throw "Unsupported REMNEXA language '$Language'." }

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directory)) { throw 'Settings path has no parent directory.' }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($fullPath) + '.remnexa.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $temporaryPath + '.bak'
    $json = ConvertTo-Json -InputObject ([ordered]@{ Language = $canonicalLanguage }) -Compress
    $encoding = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, $encoding)
        $verified = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($verified['Language'] -cne $canonicalLanguage) { throw 'Staged settings did not pass read-back validation.' }

        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $fullPath, $backupPath)
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [IO.File]::Move($temporaryPath, $fullPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Get-RemnexaLanguage, Save-RemnexaLanguage
