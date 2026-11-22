#Requires -Version 7.5

function Test-RemnexaWindowsVersion {
    param([Parameter(Mandatory)][version]$Version,
          [Parameter(Mandatory)][AllowEmptyString()][string]$ProductType)
    # Windows 11 reports NT 10.0; ProductName can still contain "Windows 10".
    # Server builds can exceed 22000 too, so require the client product type.
    return $ProductType -eq 'WinNT' -and $Version -ge [version]'10.0.22000'
}

function Get-RemnexaPlatformSupport {
    $version = [Environment]::OSVersion.Version
    $productType = ''
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $key = $null
        try {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\ProductOptions', $false)
            if ($key) { $productType = [string]$key.GetValue('ProductType', '') }
        } catch { Write-Verbose 'Windows client product type could not be read.' }
        finally { if ($key) { $key.Dispose() } }
    }
    [pscustomobject]@{
        Supported = Test-RemnexaWindowsVersion -Version $version -ProductType $productType
        Version = $version.ToString()
        MinimumVersion = '10.0.22000'
        ProductType = $productType
    }
}

Export-ModuleMember -Function Test-RemnexaWindowsVersion, Get-RemnexaPlatformSupport
