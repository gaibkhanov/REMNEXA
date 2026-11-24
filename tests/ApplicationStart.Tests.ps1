Describe 'REMNEXA application startup in a redirected host' {
    It 'keeps the real home menu responsive with background work <Background>, Extras <Extras>, and cleans up on exit' -Tag Windows11Client -TestCases @(@{Background=$false;Extras=$false},@{Background=$true;Extras=$false},@{Background=$false;Extras=$true}) {
        param($Background,$Extras)
        $root = Split-Path -Parent $PSScriptRoot
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ApplicationStart-' + [guid]::NewGuid().ToString('N'))
        $process = [Diagnostics.Process]::new()
        $started = $false
        try {
            New-Item -ItemType Directory -Path $fixture | Out-Null
            $source=Join-Path $fixture 'app'
            New-Item -ItemType Directory -Path $source|Out-Null
            foreach($directory in @('Antivirus','Core','assets','config','locales')) { Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $source -Recurse }
            Copy-Item -LiteralPath (Join-Path $root 'REMNEXA.ps1') -Destination $source
            $configPath=Join-Path $source 'config/antivirus.json'
            $config=Get-Content -LiteralPath $configPath -Raw -Encoding utf8|ConvertFrom-Json
            $config.AutoCheckUpdates=[bool]$Background
            $engine=Join-Path $fixture 'engine'
            New-Item -ItemType Directory -Path $engine|Out-Null
            [IO.File]::WriteAllText((Join-Path $engine 'clamscan.exe'),'harmless non-executable fixture')
            $config.ClamAVPath=$engine
            $config|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $configPath -Encoding utf8
            # Replace the central metadata worker, keeping both cases isolated
            # from the network and preserving the real foreground startup path.
            $slow='param($ApplicationRoot,$StateDirectory,$Id,$ApplicationVersion,$PowerShellVersion); [void][IO.Directory]::CreateDirectory($StateDirectory); [IO.File]::WriteAllText((Join-Path $StateDirectory "worker-test.pid"),[string]$PID); Start-Sleep -Seconds 60'
            [IO.File]::WriteAllText((Join-Path $source 'Core/UpdateWorker.ps1'),$slow)
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
            foreach ($argument in @('-NoLogo','-NoProfile','-File',(Join-Path $source 'REMNEXA.ps1'),'-WorkspaceMode','Home','-NoElevation')) {
                [void]$process.StartInfo.ArgumentList.Add($argument)
            }
            [void]$process.Start()
            $started = $true
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $workerPid=0
            if($Background) {
                $context=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source.ToLowerInvariant()))).ToLowerInvariant()
                $marker=Join-Path $local ('REMNEXA/Updates/'+$context+'/worker-test.pid')
                $watch=[Diagnostics.Stopwatch]::StartNew()
                while(-not(Test-Path -LiteralPath $marker) -and $watch.Elapsed.TotalSeconds -lt 8) { Start-Sleep -Milliseconds 50 }
                if(-not(Test-Path -LiteralPath $marker)) { throw 'The isolated slow update worker did not start.' }
                $workerPid=[int][IO.File]::ReadAllText($marker)
                if(-not(Get-Process -Id $workerPid -ErrorAction SilentlyContinue)) { throw 'The worker was not running while the menu waited for input.' }
            }
            if ($Extras) {
                foreach ($answer in @('E','1','M','S','pdf','1','0','0','0')) { $process.StandardInput.WriteLine($answer) }
            }
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
            if($workerPid -gt 0 -and (Get-Process -Id $workerPid -ErrorAction SilentlyContinue)) { throw 'The background update worker survived application exit.' }
            # Use ASCII labels here: redirected Windows hosts can use a legacy output codepage.
            if($Extras -and ($output -notmatch 'Standardanwendungen' -or $output -notmatch 'Erweitert' -or $output -notmatch 'Windows-Zuordnung:')) {
                throw 'The real Extras navigation, advanced search or association detail screen was not reached.'
            }
            if($output -match 'AVUpdate|Updateprüfung|Update check') { throw 'Background updates displayed an unsolicited startup message.' }
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
