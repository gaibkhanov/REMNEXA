Describe 'REMNEXA system snapshot' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\SystemSnapshot.psd1') -Force -ErrorAction Stop
    }

    AfterEach { Remove-Module SystemSnapshot -ErrorAction SilentlyContinue }

    It 'converts explicitly provided Windows, CPU, memory and disk records' {
        $os = [PSCustomObject]@{
            Caption = 'Microsoft Windows 11 Pro'
            Version = '10.0'
            BuildNumber = '26100'
            OSArchitecture = '64-bit'
            TotalVisibleMemorySize = 8388608
            FreePhysicalMemory = 2097152
        }
        $processors = @([PSCustomObject]@{ LoadPercentage = 25 }, [PSCustomObject]@{ LoadPercentage = 75 })
        $disks = @(
            [PSCustomObject]@{ DeviceID = 'c:'; DriveType = 3; Size = 1000000; FreeSpace = 250000 },
            [PSCustomObject]@{ DeviceID = 'D:'; DriveType = 5; Size = 1000000; FreeSpace = 900000 },
            [PSCustomObject]@{ DeviceID = 'E:'; DriveType = 3; Size = 1000; FreeSpace = 1200 }
        )

        $snapshot = ConvertFrom-RemnexaCimSnapshot -OperatingSystem $os -Processors $processors -LogicalDisks $disks
        if ($snapshot.SchemaVersion -ne 1 -or $snapshot.WindowsCaption -ne $os.Caption) { throw 'Windows identity was not preserved.' }
        if ($snapshot.CpuLoadPercent -ne 50 -or $snapshot.MemoryUsedPercent -ne 75) { throw 'CPU or memory metrics were calculated incorrectly.' }
        if ($snapshot.Volumes.Count -ne 1 -or $snapshot.Volumes[0].Drive -ne 'C:' -or $snapshot.Volumes[0].UsedPercent -ne 75) {
            throw 'Only valid fixed-drive metrics should be returned.'
        }
        if ([DateTimeOffset]::Parse($snapshot.CollectedAtUtc).Offset -ne [TimeSpan]::Zero) { throw 'Snapshot timestamp is not UTC.' }
    }

    It 'rejects incomplete OS data and impossible memory values' {
        $incomplete = $false
        try { ConvertFrom-RemnexaCimSnapshot -OperatingSystem ([PSCustomObject]@{ Caption = ''; Version = '' }) }
        catch { $incomplete = $true }
        if (-not $incomplete) { throw 'An incomplete operating-system record was accepted.' }

        $invalidMemory = $false
        $os = [PSCustomObject]@{ Caption = 'Windows'; Version = '10'; TotalVisibleMemorySize = 100; FreePhysicalMemory = 101 }
        try { ConvertFrom-RemnexaCimSnapshot -OperatingSystem $os }
        catch { $invalidMemory = $true }
        if (-not $invalidMemory) { throw 'Free memory larger than total memory was accepted.' }
    }
}
