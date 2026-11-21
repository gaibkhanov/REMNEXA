@{
    RootModule        = 'Antivirus.psm1'
    ModuleVersion     = '1.5.0'
    GUID              = 'f278a362-25f0-4704-ae32-2a99692a9f65'
    Author            = 'REMNEXA contributors'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 REMNEXA contributors.'
    Description       = 'Optionale ClamAV-Integration fuer lokale On-Demand-Scans und Quarantaene.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
        'Get-AVConfig',
        'Set-AVConfig',
        'Initialize-ClamAV',
        'Update-ClamAVEngine',
        'Update-ClamAVSignature',
        'Get-ClamAVStatus',
        'Get-ClamAVScanPerformance',
        'Get-ClamAVScanEngineState','Stop-ClamAVScanEngine',
        'Invoke-ClamAVScan',
        'Start-ClamAVBackgroundScan','Get-ClamAVBackgroundScan','Set-ClamAVBackgroundScan','Stop-ClamAVBackgroundScan',
        'Invoke-ClamAVTargetedScan',
        'Get-ClamAVScanResult',
        'Get-ClamAVQuarantine',
        'Restore-FromClamAVQuarantine',
        'Start-ClamAVUpdateCheck', 'Stop-ClamAVUpdateCheck', 'Get-ClamAVUpdateState',
        'Invoke-ClamAVUpdateCheck', 'Invoke-ClamAVManagedUpdate'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('ClamAV', 'Antivirus', 'Windows', 'Security')
            ProjectUri = 'https://www.clamav.net/'
        }
    }
}
