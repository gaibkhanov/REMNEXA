Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AllowedSystemFactKeys = @('WindowsVersion', 'CpuPercent', 'MemoryPercent', 'StartupNames', 'DiagnosticNotes')

function ConvertTo-RemnexaBoundedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][ValidateRange(1, 32768)][int]$MaximumLength,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [switch]$AllowEmpty
    )

    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) { throw "$FieldName cannot be empty." }
    if ($Value.Length -gt $MaximumLength) { throw "$FieldName exceeds the $MaximumLength character limit." }
    if ($Value -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { throw "$FieldName contains unsupported control characters." }
    return $Value
}

function New-RemnexaAiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [System.Collections.IDictionary]$SystemFacts = [ordered]@{}
    )

    $questionText = ConvertTo-RemnexaBoundedText -Value $Question -MaximumLength 2000 -FieldName 'Question'
    if ($null -eq $SystemFacts) { throw 'System facts must be a dictionary.' }
    $facts = [ordered]@{}
    foreach ($key in $SystemFacts.Keys) {
        if ([Array]::IndexOf($script:AllowedSystemFactKeys, [string]$key) -lt 0) {
            throw "System fact '$key' is not in the AI input allowlist."
        }
        switch -CaseSensitive ([string]$key) {
            'WindowsVersion' {
                if ($SystemFacts[$key] -isnot [string]) { throw 'WindowsVersion must be a string.' }
                $facts[$key] = ConvertTo-RemnexaBoundedText -Value $SystemFacts[$key] -MaximumLength 80 -FieldName $key
            }
            'CpuPercent' {
                if ($SystemFacts[$key] -isnot [int] -and $SystemFacts[$key] -isnot [long]) { throw 'CpuPercent must be an integer.' }
                if ([long]$SystemFacts[$key] -lt 0 -or [long]$SystemFacts[$key] -gt 100) { throw 'CpuPercent must be between 0 and 100.' }
                $facts[$key] = [int]$SystemFacts[$key]
            }
            'MemoryPercent' {
                if ($SystemFacts[$key] -isnot [int] -and $SystemFacts[$key] -isnot [long]) { throw 'MemoryPercent must be an integer.' }
                if ([long]$SystemFacts[$key] -lt 0 -or [long]$SystemFacts[$key] -gt 100) { throw 'MemoryPercent must be between 0 and 100.' }
                $facts[$key] = [int]$SystemFacts[$key]
            }
            'StartupNames' {
                $items = @($SystemFacts[$key])
                if ($items.Count -gt 100) { throw 'StartupNames cannot contain more than 100 entries.' }
                $validated = New-Object System.Collections.Generic.List[string]
                foreach ($item in $items) {
                    if ($item -isnot [string]) { throw 'Every StartupNames entry must be a string.' }
                    $name = ConvertTo-RemnexaBoundedText -Value $item -MaximumLength 160 -FieldName 'StartupNames entry'
                    if ($name -match '[/\\:]') { throw 'StartupNames accepts display names only, not paths or commands.' }
                    $validated.Add($name)
                }
                $facts[$key] = $validated.ToArray()
            }
            'DiagnosticNotes' {
                $items = @($SystemFacts[$key])
                if ($items.Count -gt 30) { throw 'DiagnosticNotes cannot contain more than 30 entries.' }
                $validated = New-Object System.Collections.Generic.List[string]
                foreach ($item in $items) {
                    if ($item -isnot [string]) { throw 'Every DiagnosticNotes entry must be a string.' }
                    $validated.Add((ConvertTo-RemnexaBoundedText -Value $item -MaximumLength 800 -FieldName 'DiagnosticNotes entry'))
                }
                $facts[$key] = $validated.ToArray()
            }
        }
    }

    $request = [PSCustomObject][ordered]@{
        SchemaVersion = 1
        CreatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        Question = $questionText
        SystemFacts = $facts
    }
    $serialized = ConvertTo-Json -InputObject $request -Depth 8 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($serialized) -gt 32768) { throw 'AI request exceeds the 32 KiB payload limit.' }
    return $request
}

function ConvertFrom-RemnexaAiResponse {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InputJson)

    if ([Text.Encoding]::UTF8.GetByteCount($InputJson) -gt 16384) { throw 'AI response exceeds the 16 KiB payload limit.' }
    try { $data = ConvertFrom-Json -InputObject $InputJson -AsHashtable -ErrorAction Stop }
    catch { throw "AI response is not valid JSON: $($_.Exception.Message)" }
    if ($data -isnot [System.Collections.IDictionary]) { throw 'AI response must be a JSON object.' }

    $requiredKeys = @('Summary', 'Observations', 'Recommendations')
    foreach ($key in $data.Keys) {
        if ([Array]::IndexOf($requiredKeys, [string]$key) -lt 0) { throw "AI response contains unsupported field '$key'." }
    }
    foreach ($key in $requiredKeys) {
        if (-not $data.Contains($key)) { throw "AI response is missing required field '$key'." }
    }

    if ($data['Summary'] -isnot [string]) { throw 'AI response Summary must be a string.' }
    $summary = ConvertTo-RemnexaBoundedText -Value $data['Summary'] -MaximumLength 4000 -FieldName 'Summary'
    if ($data['Observations'] -isnot [System.Array]) { throw 'AI response Observations must be an array.' }
    if ($data['Observations'].Count -gt 5) { throw 'AI response cannot contain more than five observations.' }
    $observations = New-Object System.Collections.Generic.List[string]
    foreach ($observation in $data['Observations']) {
        if ($observation -isnot [string]) { throw 'Every AI observation must be a string.' }
        $observations.Add((ConvertTo-RemnexaBoundedText -Value $observation -MaximumLength 800 -FieldName 'Observation'))
    }

    if ($data['Recommendations'] -isnot [System.Array]) { throw 'AI response Recommendations must be an array.' }
    if ($data['Recommendations'].Count -gt 5) { throw 'AI response cannot contain more than five recommendations.' }
    $recommendations = New-Object System.Collections.Generic.List[object]
    foreach ($recommendation in $data['Recommendations']) {
        if ($recommendation -isnot [System.Collections.IDictionary]) { throw 'Every recommendation must be a JSON object.' }
        $allowedKeys = @('Title', 'Explanation', 'RiskLevel')
        foreach ($key in $recommendation.Keys) {
            if ([Array]::IndexOf($allowedKeys, [string]$key) -lt 0) { throw "Recommendation contains unsupported field '$key'." }
        }
        foreach ($key in $allowedKeys) {
            if (-not $recommendation.Contains($key)) { throw "Recommendation is missing required field '$key'." }
            if ($recommendation[$key] -isnot [string]) { throw "Recommendation field '$key' must be a string." }
        }
        $risk = [string]$recommendation['RiskLevel']
        if ($risk -notin @('Low', 'Medium', 'High', 'Unknown')) { throw "Unsupported recommendation risk level '$risk'." }
        $recommendations.Add([PSCustomObject][ordered]@{
            Title = ConvertTo-RemnexaBoundedText -Value $recommendation['Title'] -MaximumLength 120 -FieldName 'Recommendation title'
            Explanation = ConvertTo-RemnexaBoundedText -Value $recommendation['Explanation'] -MaximumLength 1000 -FieldName 'Recommendation explanation'
            RiskLevel = $risk
        })
    }

    return [PSCustomObject][ordered]@{
        SchemaVersion = 1
        Summary = $summary
        Observations = $observations.ToArray()
        Recommendations = $recommendations.ToArray()
        IsAdvisoryOnly = $true
    }
}

Export-ModuleMember -Function New-RemnexaAiRequest, ConvertFrom-RemnexaAiResponse
