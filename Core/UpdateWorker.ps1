#Requires -Version 7.5
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ApplicationRoot,[Parameter(Mandatory)][string]$StateDirectory,
      [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$Id,[string]$ApplicationVersion,[string]$PowerShellVersion)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Updates.psm1') -Force
$module=Get-Module Updates
& $module {param($Root,$Directory,$Id,$AppVersion,$RuntimeVersion)Invoke-RemnexaComponentWorker $Root $Directory $Id $AppVersion $RuntimeVersion} $ApplicationRoot $StateDirectory $Id $ApplicationVersion $PowerShellVersion *> $null
