function Get-ClamAVScanPerformance {
    [CmdletBinding()]
    param([ValidateSet('Eco','Balanced','Fast')][string]$Mode='Balanced')
    $memory=$null;$load=$null;$disk='Unknown'
    try {
        $snapshot=Get-AVScanResources
        $memory=$snapshot.AvailableMemoryBytes
        $load=$snapshot.CpuLoadPercent
    } catch { Write-Verbose $_.Exception.Message }
    $limited=($null -ne $memory -and $memory -lt 3GB) -or ($null -ne $load -and $load -ge 80)
    $priority=if($Mode -eq 'Eco' -or $limited){'Idle'}elseif($Mode -eq 'Fast'){'Normal'}else{'BelowNormal'}
    # One scan job owns the installation lease. Private-engine threads are
    # selected separately; actual backend metadata is returned by each scan.
    [pscustomobject]@{Mode=$Mode;Backend='selected-per-scan';MaxConcurrentScans=1;ProcessPriority=$priority;LogicalCores=[Environment]::ProcessorCount;AvailableMemoryBytes=$memory;CpuLoadPercent=$load;ResourceConstrained=$limited;CanStart=($null -eq $memory -or $memory -ge 2GB);DiskType=$disk}
}
