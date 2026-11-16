Set-StrictMode -Version 2.0

function Get-RemnexaAntivirusAssessment {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Defender,
        [bool]$DefenderAvailable = $false,
        [AllowEmptyCollection()][object[]]$RegisteredProducts = @(),
        [bool]$SecurityCenterAvailable = $false
    )

    $names = @($RegisteredProducts | ForEach-Object {
        if ($null -ne $_ -and $null -ne $_.PSObject.Properties['displayName']) {
            $name = [string]$_.displayName
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -notmatch '(?i)(Microsoft|Windows).*Defender') { $name.Trim() }
        }
    } | Sort-Object -Unique)
    $defenderActive = $DefenderAvailable -and $null -ne $Defender -and
        $null -ne $Defender.PSObject.Properties['AntivirusEnabled'] -and
        $null -ne $Defender.PSObject.Properties['RealTimeProtectionEnabled'] -and
        [bool]$Defender.AntivirusEnabled -and [bool]$Defender.RealTimeProtectionEnabled

    $key = 'SecurityProtectionUnknown'
    $severity = 'Warning'
    if ($defenderActive) { $key = 'SecurityDefenderActive'; $severity = 'Info' }
    elseif ($names.Count -gt 0) { $key = 'SecurityOtherRegistered'; $severity = 'Info' }
    elseif ($DefenderAvailable -and $SecurityCenterAvailable) { $key = 'SecurityNoActiveConfirmed' }

    # Registration is evidence of registration only. productState is retained by
    # the collector, never decoded into an unsupported "protected" assertion.
    return [PSCustomObject]@{
        MessageKey = $key
        Severity = $severity
        ProductNames = @($names)
        DefenderActive = [bool]$defenderActive
        ProtectionConfirmed = [bool]$defenderActive
    }
}

Export-ModuleMember -Function Get-RemnexaAntivirusAssessment
