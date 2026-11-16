Describe 'REMNEXA permissions service' {
    It 'reports administrator membership as a boolean from the current Windows token' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\Permissions.psd1') -Force -ErrorAction Stop
        try {
            $result = Test-RemnexaAdministrator
            if ($result -isnot [bool]) { throw 'Administrator membership did not return a boolean result.' }
        }
        finally {
            Remove-Module Permissions -ErrorAction SilentlyContinue
        }
    }
}
