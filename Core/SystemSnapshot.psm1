Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-RemnexaRecordField {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Record,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Record) { return $null }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertFrom-RemnexaCimSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$OperatingSystem,
        [AllowEmptyCollection()][object[]]$Processors = @(),
        [AllowEmptyCollection()][object[]]$LogicalDisks = @()
    )

    $caption = [string](Get-RemnexaRecordField -Record $OperatingSystem -Name 'Caption')
    $version = [string](Get-RemnexaRecordField -Record $OperatingSystem -Name 'Version')
    $build = [string](Get-RemnexaRecordField -Record $OperatingSystem -Name 'BuildNumber')
    $architecture = [string](Get-RemnexaRecordField -Record $OperatingSystem -Name 'OSArchitecture')
    if ([string]::IsNullOrWhiteSpace($caption) -or [string]::IsNullOrWhiteSpace($version)) {
        throw 'Windows identity data is incomplete; a system snapshot cannot be created.'
    }

    $totalMemoryKb = [decimal](Get-RemnexaRecordField -Record $OperatingSystem -Name 'TotalVisibleMemorySize')
    $freeMemoryKb = [decimal](Get-RemnexaRecordField -Record $OperatingSystem -Name 'FreePhysicalMemory')
    if ($totalMemoryKb -lt 0 -or $freeMemoryKb -lt 0 -or ($totalMemoryKb -gt 0 -and $freeMemoryKb -gt $totalMemoryKb)) {
        throw 'Windows memory data is outside the expected range.'
    }
    $totalMemoryBytes = [long][decimal]::Round($totalMemoryKb * 1024, 0, [MidpointRounding]::AwayFromZero)
    $freeMemoryBytes = [long][decimal]::Round($freeMemoryKb * 1024, 0, [MidpointRounding]::AwayFromZero)
    $memoryUsedPercent = $null
    if ($totalMemoryKb -gt 0) {
        $memoryUsedPercent = [double][decimal]::Round((($totalMemoryKb - $freeMemoryKb) * 100 / $totalMemoryKb), 1, [MidpointRounding]::AwayFromZero)
    }

    $cpuSamples = New-Object System.Collections.Generic.List[decimal]
    foreach ($processor in @($Processors)) {
        $load = Get-RemnexaRecordField -Record $processor -Name 'LoadPercentage'
        if ($null -eq $load) { continue }
        $loadValue = [decimal]$load
        if ($loadValue -ge 0 -and $loadValue -le 100) { $cpuSamples.Add($loadValue) }
    }
    $cpuLoadPercent = $null
    if ($cpuSamples.Count -gt 0) {
        $cpuLoadPercent = [int][decimal]::Round(($cpuSamples | Measure-Object -Average).Average, 0, [MidpointRounding]::AwayFromZero)
    }

    $volumes = New-Object System.Collections.Generic.List[object]
    foreach ($disk in @($LogicalDisks)) {
        $drive = [string](Get-RemnexaRecordField -Record $disk -Name 'DeviceID')
        $size = [decimal](Get-RemnexaRecordField -Record $disk -Name 'Size')
        $free = [decimal](Get-RemnexaRecordField -Record $disk -Name 'FreeSpace')
        $driveType = Get-RemnexaRecordField -Record $disk -Name 'DriveType'
        if ($null -ne $driveType -and [int]$driveType -ne 3) { continue }
        if ($drive -notmatch '^[A-Za-z]:$' -or $size -le 0 -or $free -lt 0 -or $free -gt $size) { continue }
        $usedPercent = [double][decimal]::Round((($size - $free) * 100 / $size), 1, [MidpointRounding]::AwayFromZero)
        $volumes.Add([PSCustomObject][ordered]@{
            Drive = $drive.ToUpperInvariant()
            TotalBytes = [long]$size
            FreeBytes = [long]$free
            UsedPercent = $usedPercent
        })
    }

    return [PSCustomObject][ordered]@{
        SchemaVersion = 1
        CollectedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        WindowsCaption = $caption
        WindowsVersion = $version
        BuildNumber = $build
        Architecture = $architecture
        CpuLoadPercent = $cpuLoadPercent
        TotalMemoryBytes = $totalMemoryBytes
        FreeMemoryBytes = $freeMemoryBytes
        MemoryUsedPercent = $memoryUsedPercent
        Volumes = @($volumes.ToArray() | Sort-Object Drive)
    }
}

function Get-RemnexaSystemSnapshot {
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'REMNEXA system snapshots are supported only on Windows.'
    }
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    $logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
    return ConvertFrom-RemnexaCimSnapshot -OperatingSystem $operatingSystem -Processors $processors -LogicalDisks $logicalDisks
}

Export-ModuleMember -Function ConvertFrom-RemnexaCimSnapshot, Get-RemnexaSystemSnapshot
