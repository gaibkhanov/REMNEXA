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
    # A clamscan process is single-job. Do not invent MaxThreads support or
    # launch multiple copies of the multi-gigabyte signature database.
    [pscustomobject]@{Mode=$Mode;Backend='clamscan';MaxConcurrentScans=1;ProcessPriority=$priority;LogicalCores=[Environment]::ProcessorCount;AvailableMemoryBytes=$memory;CpuLoadPercent=$load;ResourceConstrained=$limited;CanStart=($null -eq $memory -or $memory -ge 2GB);DiskType=$disk}
}
