@{
    RootModule = 'PathSafety.psm1'
    ModuleVersion = '1.0.0'
    GUID = '7c852cab-e7b9-4fb1-b978-46d255c1e203'
    Author = 'REMNEXA contributors'
    Description = 'Fail-closed filesystem path and reparse-point validation.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('Get-RemnexaPathSafety', 'Test-RemnexaWindowsManagedPath')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
