function Find-ClamAVInstallation {
    param([AllowNull()][object]$Config)

    if ($null -eq $Config) { $Config = Get-AVConfig }
    $configured = Expand-AVPath ([string]$Config.ClamAVPath)
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
    param([AllowEmptyString()][string]$DownloadUri)

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
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Cisco-Talos/clamav/releases/latest' -Headers @{ 'User-Agent' = 'REMNEXA-ClamAV' } -ErrorAction Stop
    $asset = @($release.assets | Where-Object { $_.name.EndsWith($architectureToken, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if ($null -eq $asset) { throw "Im aktuellen offiziellen ClamAV-Release wurde kein Windows-Paket '$architectureToken' gefunden." }
    return [PSCustomObject]@{
        Uri    = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
        Name   = [string]$asset.name
        Version = ([string]$release.tag_name -replace '^clamav-', '')
    }
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
