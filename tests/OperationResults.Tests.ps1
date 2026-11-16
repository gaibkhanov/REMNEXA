Describe 'REMNEXA typed operation results' {
    It 'creates a stable schema with a generated identity and UTC timestamps' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\OperationResults.psd1') -Force -ErrorAction Stop

        try {
            $result = New-RemnexaOperationResult -OperationName 'Uninstall Example' -Status Completed -FoundCount 3 -RemovedCount 3 -RemainingCount 0 -FreedBytes 4096
            if (-not (Test-RemnexaOperationResult -Result $result)) { throw 'The generated result did not validate.' }
            if ($result.SchemaVersion -ne 1 -or $result.Status -ne 'Completed' -or $result.FoundCount -ne 3) {
                throw 'The generated result fields do not match the requested outcome.'
            }
            if ([string]::IsNullOrWhiteSpace($result.OperationId)) { throw 'An operation identity was not generated.' }
            if (([DateTimeOffset]::Parse($result.StartedAtUtc).Offset -ne [TimeSpan]::Zero) -or
                ([DateTimeOffset]::Parse($result.CompletedAtUtc).Offset -ne [TimeSpan]::Zero)) {
                throw 'Result times are not normalized to UTC.'
            }
        }
        finally { Remove-Module OperationResults -ErrorAction SilentlyContinue }
    }

    It 'rejects impossible counts and invalid completion ordering' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\OperationResults.psd1') -Force -ErrorAction Stop
        $thrown = $false
        try { New-RemnexaOperationResult -OperationName 'Invalid' -Status Completed -FoundCount 1 -RemovedCount 2 }
        catch { $thrown = $true }
        if (-not $thrown) { throw 'An impossible removed count was accepted.' }

        $thrown = $false
        try {
            New-RemnexaOperationResult -OperationName 'Invalid' -Status Completed `
                -StartedAtUtc ([DateTimeOffset]::UtcNow) -CompletedAtUtc ([DateTimeOffset]::UtcNow.AddMinutes(-1))
        }
        catch { $thrown = $true }
        if (-not $thrown) { throw 'A completion time before the start time was accepted.' }
        Remove-Module OperationResults -ErrorAction SilentlyContinue
    }

    It 'rejects records with missing fields, invalid status, or tampered counts' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\OperationResults.psd1') -Force -ErrorAction Stop

        try {
            if (Test-RemnexaOperationResult -Result ([PSCustomObject]@{ Status = 'Completed' })) {
                throw 'A partial result record passed schema validation.'
            }
            $result = New-RemnexaOperationResult -OperationName 'Cleanup' -Status Partial -FoundCount 3 -RemovedCount 1 -FailedCount 1 -RemainingCount 1
            $result.RemovedCount = 5
            if (Test-RemnexaOperationResult -Result $result) { throw 'A result with tampered counts passed validation.' }
        }
        finally { Remove-Module OperationResults -ErrorAction SilentlyContinue }
    }
}
