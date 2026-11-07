function ConvertTo-AVNativeArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
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

function Invoke-AVNativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$ArgumentList = @(),
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600,
        [AllowEmptyString()][string]$WorkingDirectory = ''
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Ausfuehrbare Datei nicht gefunden: '$FilePath'."
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
        # Windows PowerShell 5.1 besitzt noch keine ProcessStartInfo.ArgumentList.
        # Jedes Array-Element wird deshalb einzeln nach den Windows-Quoting-Regeln maskiert.
        $startInfo.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-AVNativeArgument ([string]$_) }) -join ' ')
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Prozess '$FilePath' konnte nicht gestartet werden." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            try { $process.WaitForExit() } catch { }
            throw "Zeitlimit von $TimeoutSeconds Sekunden fuer '$FilePath' ueberschritten; der Prozess wurde beendet."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [PSCustomObject]@{
            FilePath   = $FilePath
            Arguments  = @($ArgumentList)
            ExitCode   = [int]$process.ExitCode
            StandardOutput = [string]$stdout
            StandardError  = [string]$stderr
            TimedOut   = $false
        }
    }
    finally {
        $process.Dispose()
    }
}
