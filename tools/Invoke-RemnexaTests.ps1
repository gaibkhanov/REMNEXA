[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "REMNEXA test directory not found: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
Import-Module Pester -MinimumVersion 3.4.0 -ErrorAction Stop
$pesterVersion = (Get-Module Pester).Version

Write-Host ("Running REMNEXA tests with Pester {0} from {1}" -f $pesterVersion, $resolvedPath)

if ($pesterVersion.Major -ge 5) {
    $result = Invoke-Pester -Path $resolvedPath -PassThru
}
else {
    $result = Invoke-Pester -Script $resolvedPath -PassThru
}

if ($null -eq $result -or $null -eq $result.PSObject.Properties['FailedCount']) {
    throw 'Pester did not return a test result with a failure count; treating the run as unsuccessful.'
}

$passedCount = [int]$result.PassedCount
$failedCount = [int]$result.FailedCount
$skippedCount = if ($result.PSObject.Properties['SkippedCount']) { [int]$result.SkippedCount } else { 0 }
Write-Host ("REMNEXA test result: {0} passed, {1} failed, {2} skipped." -f $passedCount, $failedCount, $skippedCount)

if ($failedCount -gt 0) {
    exit 1
}

exit 0
