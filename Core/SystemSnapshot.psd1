@{
    RootModule = 'SystemSnapshot.psm1'
    ModuleVersion = '1.0.0'
    GUID = '94b61bb8-494f-43b4-a7e4-6afca7dd8796'
    Author = 'REMNEXA contributors'
    Description = 'Collects an on-demand, read-only Windows health snapshot.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('ConvertFrom-RemnexaCimSnapshot', 'Get-RemnexaSystemSnapshot')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
