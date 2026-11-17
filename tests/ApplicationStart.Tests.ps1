Describe 'REMNEXA application startup in a redirected host' {
    It 'opens the real home menu and exits with zero without requiring cursor APIs' {
        $root = Split-Path -Parent $PSScriptRoot
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ApplicationStart-' + [guid]::NewGuid().ToString('N'))
        $process = [Diagnostics.Process]::new()
        $started = $false
        try {
            New-Item -ItemType Directory -Path $fixture | Out-Null
            $process.StartInfo = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.CreateNoWindow = $true
            $process.StartInfo.RedirectStandardOutput = $true
            $process.StartInfo.RedirectStandardError = $true
            $process.StartInfo.RedirectStandardInput = $true
            $local = Join-Path $fixture 'local-app-data'
            $programData = Join-Path $fixture 'program-data'
            New-Item -ItemType Directory -Path $local, $programData | Out-Null
            $process.StartInfo.Environment['LOCALAPPDATA'] = $local
            $process.StartInfo.Environment['ProgramData'] = $programData
            foreach ($argument in @('-NoLogo','-NoProfile','-File',(Join-Path $root 'REMNEXA.ps1'),'-WorkspaceMode','Home','-NoElevation')) {
                [void]$process.StartInfo.ArgumentList.Add($argument)
            }
            [void]$process.Start()
            $started = $true
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.WriteLine('0')
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(15000)) {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
                throw 'Application startup fixture timed out.'
            }
            $streams = [Threading.Tasks.Task[]]@($stdout, $stderr)
            if (-not [Threading.Tasks.Task]::WaitAll($streams, 5000)) { throw 'Application output did not close.' }
            $output = $stdout.GetAwaiter().GetResult()
            $errorOutput = $stderr.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0 -or $output -notmatch 'REMNEXA\s+2\.2\.0' -or $errorOutput) {
                throw "Home/exit failed (exit $($process.ExitCode)): $output $errorOutput"
            }
        }
        finally {
            if ($started -and -not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(5000) }
            $process.Dispose()
            $resolved = [IO.Path]::GetFullPath($fixture)
            if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
                (Split-Path -Leaf $resolved) -like 'REMNEXA-ApplicationStart-*' -and (Test-Path -LiteralPath $resolved)) {
                Remove-Item -LiteralPath $resolved -Recurse -Force
            }
        }
    }
}
