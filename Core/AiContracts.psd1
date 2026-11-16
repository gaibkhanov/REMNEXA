@{
    RootModule = 'AiContracts.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'e9091252-b30e-4f84-8b0f-6d8da6ca18b1'
    Author = 'REMNEXA contributors'
    Description = 'Validates explicit local-AI input and advisory-only response data.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('New-RemnexaAiRequest', 'ConvertFrom-RemnexaAiResponse')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
