function Get-ClamAVScanResult {
    <#
    .SYNOPSIS
    Wandelt die Textausgabe von clamscan.exe in strukturierte Objekte um.

    .DESCRIPTION
    Erkennt Fundzeilen im Format "Pfad: Signatur FOUND" von rechts nach links.
    Dadurch werden Laufwerksbuchstaben und weitere Doppelpunkte im Pfad korrekt
    behandelt. Auch ClamAV-Fehlerzeilen werden als flache Ergebnisobjekte geliefert.

    .PARAMETER InputObject
    Eine oder mehrere Ausgabezeilen von clamscan.exe.

    .PARAMETER ExitCode
    Exit-Code des zugehoerigen clamscan-Aufrufs.

    .PARAMETER ScanType
    Scanart, die in die Ergebnisobjekte uebernommen wird.

    .EXAMPLE
    'C:\Temp\a.exe: Win.Test FOUND' | Get-ClamAVScanResult -ExitCode 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][AllowEmptyString()][string[]]$InputObject,
        [ValidateSet(0, 1, 2)][int]$ExitCode = 0,
        [ValidateSet('Quick', 'Full', 'Custom', 'Targeted')][string]$ScanType = 'Custom'
    )
    begin { $lines = New-Object 'System.Collections.Generic.List[string]' }
    process {
        foreach ($value in $InputObject) {
            foreach ($line in @([string]$value -split "`r?`n")) { $lines.Add($line) }
        }
    }
    end {
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^(?<Path>.+):\s+(?<Signature>.+)\s+FOUND\s*$') {
                $signature = [string]$Matches.Signature
                [PSCustomObject]@{
                    Path          = [string]$Matches.Path
                    Signature     = $signature
                    Severity      = if ($signature.StartsWith('PUA.', [StringComparison]::OrdinalIgnoreCase)) { 'PotentiallyUnwanted' } else { 'Malware' }
                    Status        = 'Infected'
                    ExitCode      = $ExitCode
                    ScanType      = $ScanType
                    Quarantined   = $false
                    QuarantineId  = $null
                    Message       = $trimmed
                }
                continue
            }
            if ($trimmed -match '^(?<Path>.+):\s+(?<Message>.+)\s+ERROR\s*$') {
                [PSCustomObject]@{
                    Path          = [string]$Matches.Path
                    Signature     = $null
                    Severity      = 'Error'
                    Status        = 'Error'
                    ExitCode      = 2
                    ScanType      = $ScanType
                    Quarantined   = $false
                    QuarantineId  = $null
                    Message       = [string]$Matches.Message
                }
            }
        }
    }
}
