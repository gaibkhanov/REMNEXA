Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AVModuleRoot = $PSScriptRoot
$script:AVConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\antivirus.json'

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
    'Invoke-ClamAVScan',
    'Invoke-ClamAVTargetedScan',
    'Get-ClamAVScanResult',
    'Get-ClamAVQuarantine',
    'Restore-FromClamAVQuarantine'
)
