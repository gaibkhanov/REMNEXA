@{
    RootModule = 'AppSettings.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b73381d1-23b6-4a90-a217-cd62574548d0'
    Author = 'REMNEXA contributors'
    Description = 'Reads and atomically persists validated REMNEXA application settings.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('Get-RemnexaLanguage', 'Save-RemnexaLanguage')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
