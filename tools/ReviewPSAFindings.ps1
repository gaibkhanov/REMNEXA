param([string]$ProjectRoot, [string]$ModuleRoot)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$ModuleRoot;$env:PSModulePath"
Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Force
$files = Get-ChildItem -Path $ProjectRoot -Recurse -File -Include *.ps1,*.psm1,*.psd1 | Where-Object { $_.FullName -notmatch '[\\/]Backup-[^\\/]+[\\/]|[\\/]runtime[\\/]|[\\/]ClamAV[\\/]|[\\/]tools[\\/]' }
$results = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName })
$results | Where-Object RuleName -eq 'PSUseShouldProcessForStateChangingFunctions' | Select-Object @{n='File';e={$_.Path.Substring($ProjectRoot.Length+1)}},Line,Message | Format-List
