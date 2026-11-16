Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertFrom-RemnexaMenuChoice {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][string]$InputText,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100000)][int]$Maximum
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) { return $null }
    $answer = $InputText.Trim()
    if ($answer -eq '0') { return 0 }

    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Maximum) {
        return $number
    }

    return $null
}

function Get-RemnexaPageState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$ItemCount,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$PageSize,
        [int]$PageIndex = 0
    )

    $pageCount = [int][Math]::Max(1, [Math]::Ceiling($ItemCount / [double]$PageSize))
    $current = [int][Math]::Max(0, [Math]::Min($PageIndex, $pageCount - 1))
    return [PSCustomObject]@{
        PageIndex = $current
        PageCount = $pageCount
        HasNext = ($current + 1 -lt $pageCount)
        HasPrevious = ($current -gt 0)
    }
}

Export-ModuleMember -Function ConvertFrom-RemnexaMenuChoice, Get-RemnexaPageState
