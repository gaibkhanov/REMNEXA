function Initialize-AVScanSupport {
    if(-not ('Remnexa.Scan.Inventory' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ScanInventory.cs') -ErrorAction Stop }
}

function Enter-AVScanLease {
    param($Config)
    $name='Global\REMNEXA.ClamAV.Scan.'+(Get-AVUpdateContext $Config)
    $mutex=[Threading.Mutex]::new($false,$name)
    $acquired=$false
    try {
        try { $acquired=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired=$true }
        if(-not $acquired) { throw (Get-RemnexaProgressText 'AVScanBusy') }
        return $mutex
    } catch { $mutex.Dispose();throw }
}

function Get-AVScanResources {
    Initialize-AVScanSupport
    [Remnexa.Scan.Resources]::Measure()
}
