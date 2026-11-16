@{
    RootModule = 'PrivacyBackupValidation.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f46243d1-58f9-4a23-9373-282bf5051392'
    Author = 'REMNEXA'
    Description = 'Validates privacy restore backups against the fixed application registry allowlist.'
    PowerShellVersion = '7.5'
    FunctionsToExport = @('Assert-RemnexaPrivacyBackup')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
