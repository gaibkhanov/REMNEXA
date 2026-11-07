function Get-ClamAVStatus {
    <#
    .SYNOPSIS
    Liefert den lokalen ClamAV- und Signaturstatus.

    .DESCRIPTION
    Ermittelt Installationspfad, Programmversion, Signaturdatum, ungefaehre
    Signaturanzahl sowie das Alter der Datenbank. Das Ergebnis ist flach und
    kann direkt in einer Tabelle oder einem WPF-DataGrid angezeigt werden.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .EXAMPLE
    Get-ClamAVStatus | Format-List
    #>
    [CmdletBinding()]
    param([string]$ConfigPath = $script:AVConfigPath)

    $config = Get-AVConfig -Path $ConfigPath
    $root = Find-ClamAVInstallation -Config $config
    if (-not $root) {
        return [PSCustomObject]@{
            Installed          = $false
            Ready              = $false
            Version            = $null
            SignatureDate      = $null
            SignatureAgeDays   = $null
            Signatures         = $null
            SignaturesOutdated = $true
            ClamScanPath       = Join-Path (Expand-AVPath ([string]$config.ClamAVPath)) 'clamscan.exe'
            FreshClamPath      = Join-Path (Expand-AVPath ([string]$config.ClamAVPath)) 'freshclam.exe'
            DatabasePath       = Expand-AVPath ([string]$config.DatabasePath)
        }
    }

    $paths = [PSCustomObject]@{
        ClamScan  = Join-Path $root 'clamscan.exe'
        FreshClam = Join-Path $root 'freshclam.exe'
        SigTool   = Join-Path $root 'sigtool.exe'
        Database  = Expand-AVPath ([string]$config.DatabasePath)
    }
    $version = $null
    try {
        $versionRun = Invoke-AVNativeProcess -FilePath $paths.ClamScan -ArgumentList @('--version') -TimeoutSeconds 30
        $versionText = ($versionRun.StandardOutput + "`n" + $versionRun.StandardError).Trim()
        if ($versionText -match '(?i)ClamAV\s+([^\s/]+)') { $version = $Matches[1] } else { $version = $versionText }
    }
    catch { Write-AVLog -Message $_.Exception.Message -Level 'Warning' -Event 'Status' }

    $databaseFiles = if (Test-Path -LiteralPath $paths.Database -PathType Container) {
        @(Get-ChildItem -LiteralPath $paths.Database -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.cvd', '.cld', '.cud') })
    }
    else { @() }
    $signatureDate = @($databaseFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    $ageDays = if ($null -ne $signatureDate) { [math]::Floor(((Get-Date).ToUniversalTime() - $signatureDate).TotalDays) } else { $null }

    [int64]$signatureCount = 0
    $hasCount = $false
    if (Test-Path -LiteralPath $paths.SigTool -PathType Leaf) {
        foreach ($databaseFile in $databaseFiles) {
            try {
                $info = Invoke-AVNativeProcess -FilePath $paths.SigTool -ArgumentList @('--info', $databaseFile.FullName) -TimeoutSeconds 30
                if (($info.StandardOutput + "`n" + $info.StandardError) -match '(?im)^Signatures:\s*(\d+)\s*$') {
                    $signatureCount += [int64]$Matches[1]
                    $hasCount = $true
                }
            }
            catch { Write-AVLog -Message $_.Exception.Message -Level 'Warning' -Event 'Status' }
        }
    }

    $maxAge = if ($null -ne $config.SignatureMaxAgeDays) { [int]$config.SignatureMaxAgeDays } else { 7 }
    return [PSCustomObject]@{
        Installed          = $true
        Ready              = ($databaseFiles.Count -gt 0)
        Version            = $version
        SignatureDate      = if ($null -ne $signatureDate) { [DateTime]$signatureDate } else { $null }
        SignatureAgeDays   = $ageDays
        Signatures         = if ($hasCount) { $signatureCount } else { $null }
        SignaturesOutdated = ($null -eq $ageDays -or $ageDays -gt $maxAge)
        ClamScanPath       = $paths.ClamScan
        FreshClamPath      = $paths.FreshClam
        DatabasePath       = $paths.Database
    }
}
