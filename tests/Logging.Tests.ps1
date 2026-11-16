Describe 'REMNEXA structured logging' {
    It 'writes a timestamped entry with level and component into the provided log store' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\Logging.psd1') -Force -ErrorAction Stop
        $logLines = New-Object 'System.Collections.Generic.List[string]'

        try {
            Write-RemnexaLogEntry -LogLines $logLines -Message 'isolated test entry' -Level Warning -Component 'Test/Logging'
            if ($logLines.Count -ne 1) { throw 'The log entry was not appended exactly once.' }
            if ($logLines[0] -notmatch '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[Warning\] \[Test/Logging\] isolated test entry$') {
                throw "Unexpected log entry format: $($logLines[0])"
            }
        }
        finally {
            Remove-Module Logging -ErrorAction SilentlyContinue
        }
    }
}
