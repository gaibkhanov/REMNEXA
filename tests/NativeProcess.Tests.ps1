Describe 'REMNEXA native process execution' {
    It 'quotes Windows command-line arguments with trailing backslashes' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\NativeProcess.psd1') -Force -ErrorAction Stop

        try {
            $actual = ConvertTo-RemnexaNativeArgument 'C:\Apps With Space\REMNEXA\'
            $expected = '"C:\Apps With Space\REMNEXA\\"'
            if ($actual -cne $expected) { throw "Unexpected quoted argument: $actual" }
        }
        finally {
            Remove-Module NativeProcess -ErrorAction SilentlyContinue
        }
    }

    It 'starts a native process without a command shell and captures output' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\NativeProcess.psd1') -Force -ErrorAction Stop
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) { throw 'The test PowerShell executable was not found.' }

        try {
            $code = '[Console]::Out.Write("native-out"); [Console]::Error.Write("native-err")'
            $result = Invoke-RemnexaNativeProcess -FilePath $pwshPath -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $code) -TimeoutSeconds 20
            if ($result.ExitCode -ne 0) { throw "Native child exited with $($result.ExitCode): $($result.StandardError)" }
            if ($result.StandardOutput -cne 'native-out') { throw "Unexpected stdout: '$($result.StandardOutput)'" }
            if ($result.StandardError -cne 'native-err') { throw "Unexpected stderr: '$($result.StandardError)'" }
            if ($result.TimedOut) { throw 'A successful native process was marked as timed out.' }
        }
        finally {
            Remove-Module NativeProcess -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a missing executable before launching a process' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\NativeProcess.psd1') -Force -ErrorAction Stop
        try {
            $rejected = $false
            try { Invoke-RemnexaNativeProcess -FilePath (Join-Path ([IO.Path]::GetTempPath()) 'REMNEXA-missing-executable.exe') -ArgumentList @() }
            catch { $rejected = $true }
            if (-not $rejected) { throw 'A missing executable was accepted.' }
        }
        finally {
            Remove-Module NativeProcess -ErrorAction SilentlyContinue
        }
    }

    It 'keeps the Antivirus process API compatible through the shared core service' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $antivirusModule = Join-Path $projectRoot 'Antivirus\Antivirus.psd1'
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
        Import-Module -Name $antivirusModule -Force -ErrorAction Stop
        $module = Get-Module Antivirus

        try {
            $code = '[Console]::Out.Write("antivirus-wrapper-ok")'
            $result = & $module {
                param($file, $scriptText)
                Invoke-AVNativeProcess -FilePath $file -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $scriptText) -TimeoutSeconds 20
            } $pwshPath $code
            if ($result.ExitCode -ne 0 -or $result.StandardOutput -cne 'antivirus-wrapper-ok') {
                throw 'The Antivirus compatibility wrapper did not use the shared process service correctly.'
            }
        }
        finally {
            Remove-Module Antivirus -ErrorAction SilentlyContinue
        }
    }
}
