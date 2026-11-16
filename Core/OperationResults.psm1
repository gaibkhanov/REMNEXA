Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function New-RemnexaOperationResult {
    [CmdletBinding()]
    param(
        [guid]$OperationId = [guid]::Empty,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OperationName,
        [Parameter(Mandatory = $true)][ValidateSet('Started', 'Completed', 'Partial', 'DryRun', 'Cancelled', 'Failed')][string]$Status,
        [DateTimeOffset]$StartedAtUtc = [DateTimeOffset]::UtcNow,
        [DateTimeOffset]$CompletedAtUtc = [DateTimeOffset]::UtcNow,
        [ValidateRange(0, [int]::MaxValue)][int]$FoundCount = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$RemovedCount = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$FailedCount = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$RemainingCount = 0,
        [ValidateRange(0, [long]::MaxValue)][long]$FreedBytes = 0,
        [AllowEmptyString()][string]$LogPath = '',
        [AllowEmptyString()][string]$ErrorMessage = ''
    )

    if ($OperationId -eq [guid]::Empty) { $OperationId = [guid]::NewGuid() }
    if ($CompletedAtUtc -lt $StartedAtUtc) { throw 'Operation completion time cannot be earlier than its start time.' }
    if ($RemovedCount -gt $FoundCount) { throw 'Removed count cannot exceed the number of findings.' }

    return [PSCustomObject][ordered]@{
        SchemaVersion = 1
        OperationId = $OperationId.ToString('D')
        OperationName = $OperationName.Trim()
        Status = $Status
        StartedAtUtc = $StartedAtUtc.ToUniversalTime().ToString('o')
        CompletedAtUtc = $CompletedAtUtc.ToUniversalTime().ToString('o')
        FoundCount = $FoundCount
        RemovedCount = $RemovedCount
        FailedCount = $FailedCount
        RemainingCount = $RemainingCount
        FreedBytes = $FreedBytes
        LogPath = $LogPath
        ErrorMessage = $ErrorMessage
    }
}

function Test-RemnexaOperationResult {
    [CmdletBinding()]
    param([AllowNull()][object]$Result)

    if ($null -eq $Result) { return $false }
    $requiredProperties = @(
        'SchemaVersion', 'OperationId', 'OperationName', 'Status', 'StartedAtUtc', 'CompletedAtUtc',
        'FoundCount', 'RemovedCount', 'FailedCount', 'RemainingCount', 'FreedBytes', 'LogPath', 'ErrorMessage'
    )
    foreach ($propertyName in $requiredProperties) {
        if ($null -eq $Result.PSObject.Properties[$propertyName]) { return $false }
    }

    if ([int]$Result.SchemaVersion -ne 1) { return $false }
    if ([string]$Result.Status -notin @('Started', 'Completed', 'Partial', 'DryRun', 'Cancelled', 'Failed')) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Result.OperationName)) { return $false }
    foreach ($countName in @('FoundCount', 'RemovedCount', 'FailedCount', 'RemainingCount', 'FreedBytes')) {
        if ([long]$Result.$countName -lt 0) { return $false }
    }
    if ([long]$Result.RemovedCount -gt [long]$Result.FoundCount) { return $false }
    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse([string]$Result.OperationId, [ref]$parsedId)) { return $false }
    $started = [DateTimeOffset]::MinValue
    $completed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Result.StartedAtUtc, [ref]$started)) { return $false }
    if (-not [DateTimeOffset]::TryParse([string]$Result.CompletedAtUtc, [ref]$completed)) { return $false }
    return ($completed -ge $started)
}

Export-ModuleMember -Function New-RemnexaOperationResult, Test-RemnexaOperationResult
