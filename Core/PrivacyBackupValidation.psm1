Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-RemnexaPrivacyBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Backup,
        [Parameter(Mandatory = $true)][object[]]$AllowedChanges
    )

    foreach ($propertyName in @('Timestamp', 'Registry', 'DiagTrack')) {
        if ($null -eq $Backup.PSObject.Properties[$propertyName]) {
            throw "Datenschutz-Sicherung ist unvollstaendig: '$propertyName' fehlt."
        }
    }

    $timestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Backup.Timestamp, [ref]$timestamp)) {
        throw 'Datenschutz-Sicherung enthaelt keinen gueltigen Zeitstempel.'
    }

    $expected = @{}
    foreach ($change in $AllowedChanges) {
        if ($null -eq $change.Path -or $null -eq $change.Name -or $null -eq $change.Type) {
            throw 'Die Datenschutz-Allowlist enthaelt einen unvollstaendigen Eintrag.'
        }
        $key = ([string]$change.Path).TrimEnd([char]'\') + '|' + [string]$change.Name
        if ($expected.ContainsKey($key)) { throw 'Die Datenschutz-Allowlist enthaelt doppelte Eintraege.' }
        $expected[$key] = $change
    }

    $snapshots = @($Backup.Registry)
    if ($snapshots.Count -ne $expected.Count) {
        throw 'Datenschutz-Sicherung enthaelt nicht genau die erwarteten Registry-Eintraege.'
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($snapshot in $snapshots) {
        foreach ($propertyName in @('Path', 'Name', 'Existed', 'Value', 'Type')) {
            if ($null -eq $snapshot.PSObject.Properties[$propertyName]) {
                throw "Datenschutz-Sicherung enthaelt einen Eintrag ohne '$propertyName'."
            }
        }
        if ($snapshot.Existed -isnot [bool]) { throw 'Datenschutz-Sicherung enthaelt einen ungueltigen Existed-Wert.' }

        $key = ([string]$snapshot.Path).TrimEnd([char]'\') + '|' + [string]$snapshot.Name
        if (-not $expected.ContainsKey($key)) {
            throw "Datenschutz-Sicherung enthaelt ein nicht erlaubtes Registry-Ziel: '$($snapshot.Path)\$($snapshot.Name)'."
        }
        if (-not $seen.Add($key)) { throw "Datenschutz-Sicherung enthaelt den Registry-Eintrag doppelt: '$key'." }

        if (-not $snapshot.Existed) {
            if ([string]$snapshot.Type -cne [string]$expected[$key].Type -or $null -ne $snapshot.Value) {
                throw "Nicht vorhandener Registry-Eintrag '$key' besitzt ungueltige Sicherungsdaten."
            }
            continue
        }

        try { $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$snapshot.Type, $true) }
        catch { throw "Registry-Sicherung '$key' besitzt einen ungueltigen Werttyp." }
        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Unknown) {
            throw "Registry-Sicherung '$key' verwendet einen nicht unterstuetzten Werttyp."
        }

        switch ($kind.ToString()) {
            { $_ -in @('DWord', 'QWord') } {
                if ($snapshot.Value -is [bool]) { throw "Registry-Sicherung '$key' enthaelt keinen numerischen Wert." }
                try {
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { [void][int]$snapshot.Value }
                    else { [void][long]$snapshot.Value }
                }
                catch { throw "Registry-Sicherung '$key' enthaelt einen ungueltigen numerischen Wert." }
            }
            { $_ -in @('String', 'ExpandString') } {
                if ($snapshot.Value -isnot [string]) { throw "Registry-Sicherung '$key' enthaelt keinen Textwert." }
            }
            'MultiString' {
                foreach ($value in @($snapshot.Value)) {
                    if ($value -isnot [string]) { throw "Registry-Sicherung '$key' enthaelt eine ungueltige Zeichenfolgenliste." }
                }
            }
            { $_ -in @('Binary', 'None') } {
                foreach ($value in @($snapshot.Value)) {
                    $byteValue = 0
                    if ($value -is [bool] -or -not [byte]::TryParse([string]$value, [ref]$byteValue)) {
                        throw "Registry-Sicherung '$key' enthaelt ungueltige Binärdaten."
                    }
                }
            }
            default { throw "Registry-Sicherung '$key' verwendet einen nicht unterstuetzten Werttyp '$kind'." }
        }
    }

    foreach ($key in $expected.Keys) {
        if (-not $seen.Contains([string]$key)) { throw "Registry-Sicherung laesst den erwarteten Eintrag '$key' aus." }
    }

    $service = $Backup.DiagTrack
    foreach ($propertyName in @('Exists', 'StartMode', 'State')) {
        if ($null -eq $service.PSObject.Properties[$propertyName]) {
            throw "Datenschutz-Sicherung fuer den Dienst ist unvollstaendig: '$propertyName' fehlt."
        }
    }
    if ($service.Exists -isnot [bool]) { throw 'Datenschutz-Sicherung enthaelt einen ungueltigen Dienststatus.' }
    if ($service.Exists) {
        if ([string]$service.StartMode -notin @('Auto', 'Manual', 'Disabled') -or
            [string]$service.State -notin @('Running', 'Stopped')) {
            throw 'Datenschutz-Sicherung enthaelt ungueltige DiagTrack-Einstellungen.'
        }
    }
    elseif (-not [string]::IsNullOrEmpty([string]$service.StartMode) -or -not [string]::IsNullOrEmpty([string]$service.State)) {
        throw 'Nicht vorhandener DiagTrack-Dienst enthaelt unerwartete Sicherungsdaten.'
    }

    return $true
}

Export-ModuleMember -Function Assert-RemnexaPrivacyBackup
