Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AVModuleRoot = $PSScriptRoot
$script:AVConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\antivirus.json'
Import-Module (Join-Path $PSScriptRoot '..\Core\Progress.psd1') -ErrorAction Stop
$script:AVDiscoveryProgress = $null
$script:AVDiscoverySkipped = 0
$script:AVCancellation = $null
$script:AVUpdateWorker = $null
$script:AVPrivateWorker = $null
$script:AVPrivateFailure = $null
$ExecutionContext.SessionState.Module.OnRemove = { try{Stop-ClamAVUpdateCheck}finally{Stop-ClamAVScanEngine} }

foreach ($folder in @('Private', 'Public')) {
    $folderPath = Join-Path $PSScriptRoot $folder
    foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object Name)) {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-AVConfig',
    'Set-AVConfig',
    'Initialize-ClamAV',
    'Update-ClamAVEngine',
    'Update-ClamAVSignature',
    'Get-ClamAVStatus',
    'Get-ClamAVScanPerformance',
    'Get-ClamAVScanEngineState','Stop-ClamAVScanEngine',
    'Invoke-ClamAVScan',
    'Invoke-ClamAVTargetedScan',
    'Get-ClamAVScanResult',
    'Get-ClamAVQuarantine',
    'Restore-FromClamAVQuarantine',
    'Start-ClamAVUpdateCheck', 'Stop-ClamAVUpdateCheck', 'Get-ClamAVUpdateState',
    'Invoke-ClamAVUpdateCheck', 'Invoke-ClamAVManagedUpdate'
)
