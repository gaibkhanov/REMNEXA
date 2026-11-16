Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-RemnexaLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$LogLines,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info',
        [string]$Component = 'REMNEXA'
    )

    $LogLines.Add(('[{0:yyyy-MM-dd HH:mm:ss}] [{1}] [{2}] {3}' -f (Get-Date), $Level, $Component, $Message))
}

Export-ModuleMember -Function Write-RemnexaLogEntry
