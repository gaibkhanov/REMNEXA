#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ApplicationRoot,[Parameter(Mandatory)][string]$StateDirectory,
      [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$Id,[string]$ApplicationVersion,[string]$PowerShellVersion)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
# Lower this owned worker's CPU, disk-I/O and memory priority. Foreground
# navigation and scan controls retain their normal scheduling priority.
try{
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RemnexaUpdatePriority {
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] private static extern bool SetPriorityClass(IntPtr process, uint priority);
    public static bool Begin() { return SetPriorityClass(GetCurrentProcess(), 0x00100000); }
}
'@ -ErrorAction Stop
    [void][RemnexaUpdatePriority]::Begin()
}catch{Write-Verbose 'Background process priority could not be lowered.'}
Import-Module (Join-Path $PSScriptRoot 'Updates.psm1') -Force
$module=Get-Module Updates
& $module {param($Root,$Directory,$Id,$AppVersion,$RuntimeVersion)Invoke-RemnexaComponentWorker $Root $Directory $Id $AppVersion $RuntimeVersion} $ApplicationRoot $StateDirectory $Id $ApplicationVersion $PowerShellVersion *> $null
