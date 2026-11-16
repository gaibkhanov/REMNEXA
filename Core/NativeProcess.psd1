@{
    RootModule = 'NativeProcess.psm1'
    ModuleVersion = '1.0.0'
    GUID = '0e6c5f43-52fc-4bc2-992f-38121ae09312'
    Author = 'REMNEXA contributors'
    Description = 'Runs validated native executables without invoking a command shell.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('ConvertTo-RemnexaNativeArgument', 'Invoke-RemnexaNativeProcess')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
