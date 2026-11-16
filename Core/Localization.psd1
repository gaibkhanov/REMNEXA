@{
    RootModule = 'Localization.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9025e52a-1f38-4a9b-a47a-415ddc93f105'
    Author = 'REMNEXA contributors'
    Description = 'Loads keyed REMNEXA locale resources with German fallback.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('Import-RemnexaLocalization', 'Get-RemnexaText')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
