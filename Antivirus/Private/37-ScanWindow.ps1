function New-AVScanWindow {
    param([switch]$InputOnly)
    try {
        if([Console]::IsInputRedirected -or [Console]::IsOutputRedirected){return $null}
        if(-not ('Remnexa.ConsoleUi.ScanWindow' -as [type])){Add-Type -Path (Join-Path $script:AVModuleRoot 'Private/ScanWindow.cs') -ErrorAction Stop}
        return [Remnexa.ConsoleUi.ScanWindow]::new([bool]$InputOnly)
    }catch{Write-Verbose ('Console view unavailable: '+$_.Exception.Message);return $null}
}
