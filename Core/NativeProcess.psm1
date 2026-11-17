Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-RemnexaNativeArgument {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Argument)

    if ($Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append((('\' * (($backslashes * 2) + 1)) -join ''))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append((('\' * $backslashes) -join ''))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append((('\' * ($backslashes * 2)) -join '')) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-RemnexaNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$ArgumentList = @(),
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600,
        [AllowEmptyString()][string]$WorkingDirectory = '',
        [scriptblock]$OnOutput,
        [scriptblock]$OnHeartbeat,
        [scriptblock]$CaptureFilter,
        [ValidateRange(1024, 67108864)][int]$MaxCapturedCharacters = 16777216,
        [ValidateSet('Idle','BelowNormal','Normal')][string]$ProcessPriority='Normal',
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Executable not found: '$FilePath'."
    }

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $ArgumentList) { [void]$startInfo.ArgumentList.Add([string]$argument) }
    }
    else {
        # Windows PowerShell 5.1 does not expose ProcessStartInfo.ArgumentList.
        $startInfo.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-RemnexaNativeArgument ([string]$_) }) -join ' ')
    }

    if ($OnOutput -or $OnHeartbeat -or $CaptureFilter -or $CancellationToken.CanBeCanceled -or $ProcessPriority -ne 'Normal') {
        return Invoke-RemnexaObservedProcess -StartInfo $startInfo -TimeoutSeconds $TimeoutSeconds -OnOutput $OnOutput -OnHeartbeat $OnHeartbeat -CaptureFilter $CaptureFilter -MaxCapturedCharacters $MaxCapturedCharacters -Arguments $ArgumentList -ProcessPriority $ProcessPriority -CancellationToken $CancellationToken
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        if (-not $process.Start()) { throw "Could not start process '$FilePath'." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                # PowerShell 7.5+ supports terminating the owned process tree.
                $process.Kill($true)
                if (-not $process.WaitForExit(5000)) { throw 'The parent process did not exit within the cleanup window.' }
            }
            catch {
                throw "Process '$FilePath' exceeded the $TimeoutSeconds second timeout; cleanup could not be confirmed: $($_.Exception.Message)"
            }
            throw "Process '$FilePath' exceeded the $TimeoutSeconds second timeout; process-tree termination was requested."
        }
        # A child inheriting redirected pipes must not cause an unbounded read
        # after its parent exits. The deadline covers output draining as well.
        $remaining = [int][Math]::Max(0, ($TimeoutSeconds * 1000) - $deadline.ElapsedMilliseconds)
        $streams = [Threading.Tasks.Task[]]@($stdoutTask, $stderrTask)
        if (-not [Threading.Tasks.Task]::WaitAll($streams, $remaining)) {
            throw "Process '$FilePath' exited, but its output streams did not close within the $TimeoutSeconds second timeout."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [PSCustomObject]@{
            FilePath = $FilePath
            Arguments = @($ArgumentList)
            ExitCode = [int]$process.ExitCode
            StandardOutput = [string]$stdout
            StandardError = [string]$stderr
            TimedOut = $false
        }
    }
    finally {
        $process.Dispose()
    }
}

Export-ModuleMember -Function ConvertTo-RemnexaNativeArgument, Invoke-RemnexaNativeProcess

function Invoke-RemnexaObservedProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo, [int]$TimeoutSeconds, [scriptblock]$OnOutput, [scriptblock]$OnHeartbeat, [scriptblock]$CaptureFilter, [int]$MaxCapturedCharacters, [string[]]$Arguments,
        [string]$ProcessPriority='Normal',[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $StartInfo
    $started = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $output = @{ Stdout=[Text.StringBuilder]::new(); Stderr=[Text.StringBuilder]::new() }
    $captured = 0
    $lastHeartbeat = [long]-1000
    try {
        $CancellationToken.ThrowIfCancellationRequested()
        $started = $process.Start()
        if (-not $started) { throw 'The native process could not start.' }
        try { $process.PriorityClass=[Diagnostics.ProcessPriorityClass]::$ProcessPriority } catch { Write-Verbose $_.Exception.Message }
        $readers = @{ Stdout=$process.StandardOutput; Stderr=$process.StandardError }
        $pending = @{ Stdout=$readers.Stdout.ReadLineAsync(); Stderr=$readers.Stderr.ReadLineAsync() }
        while ($pending.Count -gt 0 -or -not $process.HasExited) {
            $CancellationToken.ThrowIfCancellationRequested()
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "Process '$($StartInfo.FileName)' exceeded the $TimeoutSeconds second timeout." }
            foreach ($streamName in @($pending.Keys)) {
                # Bound each batch so stderr, heartbeats and the deadline cannot
                # be starved by a process continuously producing stdout.
                $batch = 0
                while ($pending.ContainsKey($streamName) -and $pending[$streamName].IsCompleted -and $batch -lt 100) {
                    $line = $pending[$streamName].GetAwaiter().GetResult()
                    if ($null -eq $line) { $pending.Remove($streamName); break }
                    if ($OnOutput) { & $OnOutput $line $streamName | Out-Null }
                    $capture = if ($CaptureFilter) { [bool](& $CaptureFilter $line $streamName) } else { $true }
                    if ($capture) {
                        $captured += $line.Length + [Environment]::NewLine.Length
                        if ($captured -gt $MaxCapturedCharacters) { throw 'Native output exceeded the capture limit; the operation was stopped rather than discarding results.' }
                        [void]$output[$streamName].AppendLine($line)
                    }
                    $pending[$streamName] = $readers[$streamName].ReadLineAsync()
                    $batch++
                }
            }
            if ($OnHeartbeat -and ($watch.ElapsedMilliseconds - $lastHeartbeat) -ge 1000) {
                & $OnHeartbeat ([PSCustomObject]@{ ElapsedSeconds=$watch.Elapsed.TotalSeconds; ProcessId=$process.Id }) | Out-Null
                $lastHeartbeat = $watch.ElapsedMilliseconds
            }
            $ready = @($pending.Values | Where-Object IsCompleted).Count -gt 0
            # Wake as soon as either redirected stream has data. A fixed 50 ms
            # sleep per asynchronous read throttles fast scanners unnecessarily.
            if (-not $ready -and $pending.Count -gt 0) { [void][Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($pending.Values),50) }
            elseif (-not $ready -and -not $process.HasExited) { [void]$process.WaitForExit(50) }
        }
        return [PSCustomObject]@{ FilePath=$StartInfo.FileName; Arguments=@($Arguments); ExitCode=[int]$process.ExitCode; StandardOutput=$output.Stdout.ToString(); StandardError=$output.Stderr.ToString(); TimedOut=$false }
    }
    finally {
        $cleanupFailure=$null
        if ($started -and -not $process.HasExited) {
            try {
                $process.Kill($true)
                if (-not $process.WaitForExit(5000)) { throw 'The owned process did not exit within the cleanup window.' }
            }
            catch { $cleanupFailure=$_.Exception }
        }
        $process.Dispose()
        if($cleanupFailure){
            $failure=[InvalidOperationException]::new('Native process cleanup could not be confirmed.',$cleanupFailure)
            $failure.Data['NativeCleanupFailed']=$true
            throw $failure
        }
    }
}
