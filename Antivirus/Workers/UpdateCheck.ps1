#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$StatePath,[switch]$Force)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
try {
    Import-Module (Join-Path $PSScriptRoot '../Antivirus.psd1') -ErrorAction Stop
    & (Get-Module Antivirus) {
        param($ConfigPath,$StatePath,$Force)
        Set-RemnexaProgressRendering -Enabled $false
        try { $lease=Enter-AVUpdateLease $StatePath }
        catch { return }
        try { [void](Invoke-AVUpdateMetadataCheck -ConfigPath $ConfigPath -StatePath $StatePath -Force:$Force) }
        finally { $lease.Dispose() }
    } $ConfigPath $StatePath ([bool]$Force)
}
catch { exit 1 }
