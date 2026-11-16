param([string]$ProjectRoot, [string]$ModuleRoot)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$ModuleRoot;$env:PSModulePath"
Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Force -ErrorAction Stop
$files = Get-ChildItem -Path $ProjectRoot -Recurse -File -Include *.ps1,*.psm1,*.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]Backup-[^\\/]+[\\/]|[\\/]runtime[\\/]|[\\/]ClamAV[\\/]|[\\/]tools[\\/]Modules[\\/]' }
$results = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName })
$errorCount = @($results | Where-Object Severity -eq 'Error').Count
$warningCount = @($results | Where-Object Severity -eq 'Warning').Count
$informationCount = @($results | Where-Object Severity -eq 'Information').Count
Write-Output "AnalyzerVersion=$((Get-Module PSScriptAnalyzer).Version)"
Write-Output "AnalyzedFiles=$($files.Count)"
Write-Output "FindingCount=$($results.Count)"
Write-Output "ErrorCount=$errorCount"
Write-Output "WarningCount=$warningCount"
Write-Output "InformationCount=$informationCount"
$results | Group-Object Severity,RuleName | Sort-Object Name | Select-Object Name,Count | Format-Table -AutoSize
if ($results.Count -gt 0) { $results | Select-Object @{n='File';e={$_.Path.Substring($ProjectRoot.Length+1)}},Line,Severity,RuleName,Message | Format-List }
if ($errorCount -gt 0) { exit 1 }
exit 0
