Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-RemnexaAdministrator {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        throw "Could not determine the current Windows administrator role: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Test-RemnexaAdministrator
