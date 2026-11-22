Set-StrictMode -Version 2.0
$script:ProgressLanguage = 'de'
$script:ProgressResources = @{}
$script:ProgressRendering = $true
$script:ProgressNextId = 1000
$script:ProgressActive = [Collections.Generic.List[object]]::new()

function Set-RemnexaProgressLanguage {
    param([string]$LanguageCode = 'de')
    $script:ProgressLanguage = if ($LanguageCode -in @('de','en','es','fr','ru','tr')) { $LanguageCode } else { 'de' }
}

function Set-RemnexaProgressRendering {
    param([bool]$Enabled)
    $script:ProgressRendering = $Enabled
}

function Get-RemnexaProgressText {
    param([Parameter(Mandatory)][string]$Key)
    foreach ($code in @($script:ProgressLanguage, 'de') | Select-Object -Unique) {
        if (-not $script:ProgressResources.ContainsKey($code)) {
            $file = Join-Path $PSScriptRoot ('..\locales\' + $code + '.json')
            try { $script:ProgressResources[$code] = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable }
            catch { $script:ProgressResources[$code] = @{} }
        }
        $resource = $script:ProgressResources[$code]
        if ($resource.Contains($Key) -and -not [string]::IsNullOrWhiteSpace($resource[$Key])) { return [string]$resource[$Key] }
    }
    return $Key
}

function Get-RemnexaActiveProgress {
    if ($script:ProgressActive.Count) { return $script:ProgressActive[$script:ProgressActive.Count - 1] }
    return $null
}

function Add-RemnexaProgressNotice {
    param([ValidateSet('Warning','Error')][string]$Level = 'Warning')
    foreach ($state in $script:ProgressActive) { if ($state.NoticeLevel -ne 'Error') { $state.NoticeLevel=$Level } }
}

function Get-RemnexaProgressFrame {
    param([Parameter(Mandatory)][object]$Progress)
    $percent = -1
    if ($Progress.Total -gt 0) { $percent = [int][Math]::Min(100, [Math]::Floor(100.0 * $Progress.Completed / $Progress.Total)) }
    elseif ($Progress.Outcome -in @('Completed','Warning')) { $percent = 100 }
    $color = switch ($Progress.Outcome) { 'Completed' { 'Green' }; 'Warning' { 'Yellow' }; 'Failed' { 'Red' }; 'Cancelled' { 'Yellow' }; default { if ($Progress.Waiting) { 'Yellow' } else { 'Cyan' } } }
    $label = if ($Progress.Waiting) { Get-RemnexaProgressText 'ProgressWaiting' } elseif ($Progress.Outcome -ne 'Running') { Get-RemnexaProgressText ('ProgressOutcome' + $Progress.Outcome) } else { Get-RemnexaProgressText 'ProgressRunning' }
    $bar = if ($percent -ge 0) { ('#' * [int][Math]::Floor($percent / 5.0)).PadRight(20, '.') } else { ('.' * ([int]$Progress.Watch.Elapsed.TotalSeconds % 20) + '|').PadRight(20, '.') }
    $measure = if ($percent -ge 0) { '{0,3}%' -f $percent } else { Get-RemnexaProgressText 'ProgressUnknown' }
    $count = if ($Progress.Total -ge 0) { '{0}/{1} {2}' -f $Progress.Completed, $Progress.Total, $Progress.Unit } elseif ($Progress.Completed -gt 0) { '{0} {1}' -f $Progress.Completed, $Progress.Unit } else { '' }
    $elapsed = [TimeSpan]::FromSeconds([Math]::Floor($Progress.Watch.Elapsed.TotalSeconds)).ToString('hh\:mm\:ss')
    $line = '[{0}] {1} | {2} | {3} | {4} {5}' -f $bar, $measure, $Progress.Activity, $label, $count, $elapsed
    if ($Progress.Status) { $line += ' | ' + $Progress.Status }
    if ($Progress.CurrentItem) { $line += ' | ' + $Progress.CurrentItem }
    $line = [regex]::Replace($line, '[\p{Cc}\p{Cf}]', ' ')
    [PSCustomObject]@{ Percent=$percent; Color=$color; Text=$line; Outcome=$Progress.Outcome; Completed=$Progress.Completed; Total=$Progress.Total }
}

function Test-RemnexaInteractiveProgress {
    try { return $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected }
    catch { return $false }
}

function Write-RemnexaProgressFrame {
    param([object]$Progress, [switch]$Force)
    if (-not $script:ProgressRendering) { return }
    if (-not $Force -and ($Progress.Watch.ElapsedMilliseconds - $Progress.LastRendered) -lt 1000) { return }
    $frame = Get-RemnexaProgressFrame $Progress
    $Progress.LastRendered = $Progress.Watch.ElapsedMilliseconds
    $interactiveConsole = Test-RemnexaInteractiveProgress
    if ($interactiveConsole) {
        # One native progress record, with compact text rather than another bar
        # embedded inside PowerShell's bar. Nested operations share this slot.
        try {
            if ($Progress.Outcome -ne 'Running' -or $Progress.Waiting) {
                Write-Progress -Id 999 -Activity $Progress.Activity -Completed
            } else {
                $status = if ($Progress.Status) { $Progress.Status } else { Get-RemnexaProgressText 'ProgressRunning' }
                if ($Progress.Total -ge 0) { $status += ' | {0}/{1} {2}' -f $Progress.Completed, $Progress.Total, $Progress.Unit }
                if ($Progress.CurrentItem) { $status += ' | ' + $Progress.CurrentItem }
                $status = [regex]::Replace($status, '[\p{Cc}\p{Cf}]', ' ')
                if ($status.Length -gt 180) { $status = $status.Substring(0,177) + '...' }
                Write-Progress -Id 999 -Activity $Progress.Activity -Status $status -PercentComplete $frame.Percent
            }
        } catch { Write-Verbose $_.Exception.Message }
        # Keep a single final summary for the whole operation, not every nested
        # status probe. Force means refresh, not append another console line.
        if ($Progress.ParentId -lt 0 -and $Progress.Outcome -ne 'Running') { Write-Host $frame.Text -ForegroundColor $frame.Color }
    } elseif ($Progress.ParentId -lt 0 -or $Progress.Outcome -in @('Failed','Cancelled')) {
        if ($Force -or $Progress.Outcome -ne 'Running' -or $Progress.Watch.ElapsedMilliseconds-$Progress.LastFallback -ge 5000) {
            Write-Host $frame.Text -ForegroundColor $frame.Color
            $Progress.LastFallback = $Progress.Watch.ElapsedMilliseconds
        }
    }
}

function New-RemnexaProgress {
    param([Parameter(Mandatory)][string]$Activity, [long]$Total = -1, [string]$Unit = '')
    if ($Total -lt -1) { throw 'Progress total cannot be negative except -1 for unknown work.' }
    $script:ProgressNextId++
    $parent = if ($script:ProgressActive.Count) { $script:ProgressActive[$script:ProgressActive.Count - 1].Id } else { -1 }
    $state = [PSCustomObject]@{ Id=$script:ProgressNextId; ParentId=$parent; Activity=$Activity; Total=$Total; Completed=[long]0; Unit=$Unit; Status=''; CurrentItem=''; Outcome='Running'; NoticeLevel=''; Waiting=$false; Watch=[Diagnostics.Stopwatch]::StartNew(); LastRendered=[long]-1000; LastFallback=[long]-5000 }
    $script:ProgressActive.Add($state)
    Write-RemnexaProgressFrame $state -Force
    return $state
}

function Update-RemnexaProgress {
    param([Parameter(Mandatory)][object]$Progress, [long]$Completed = -1, [long]$Total = -2, [string]$Status, [string]$CurrentItem, [switch]$Force)
    if ($Progress.Outcome -ne 'Running') { throw 'A finished progress operation cannot be updated.' }
    if ($Total -lt -2 -or $Completed -lt -1) { throw 'Invalid progress counts.' }
    $effectiveTotal = if ($Total -ne -2) { $Total } else { $Progress.Total }
    $effectiveCompleted = if ($Completed -ge 0) { $Completed } else { $Progress.Completed }
    if ($effectiveCompleted -lt $Progress.Completed -or ($effectiveTotal -ge 0 -and $effectiveCompleted -gt $effectiveTotal)) { throw 'Progress counts cannot go backwards or exceed the known total.' }
    $Progress.Total = $effectiveTotal; $Progress.Completed = $effectiveCompleted
    if ($PSBoundParameters.ContainsKey('Status')) { $Progress.Status = $Status }
    if ($PSBoundParameters.ContainsKey('CurrentItem')) { $Progress.CurrentItem = $CurrentItem }
    Write-RemnexaProgressFrame $Progress -Force:$Force
}

function Complete-RemnexaProgress {
    param([Parameter(Mandatory)][object]$Progress, [ValidateSet('Completed','Warning','Failed','Cancelled')][string]$Outcome = 'Completed', [string]$Status = '')
    if ($Progress.Outcome -ne 'Running') { return }
    if ($Outcome -eq 'Completed' -and $Progress.NoticeLevel) { $Outcome = if ($Progress.NoticeLevel -eq 'Error') { 'Failed' } else { 'Warning' } }
    if ($Outcome -eq 'Completed' -and $Progress.Total -ge 0 -and $Progress.Completed -lt $Progress.Total) { throw 'Known work cannot be marked complete before all items are processed.' }
    $Progress.Outcome = $Outcome; $Progress.Waiting = $false
    if ($Status) { $Progress.Status = $Status }
    Write-RemnexaProgressFrame $Progress -Force
    $Progress.Watch.Stop()
    [void]$script:ProgressActive.Remove($Progress)
    $parent = Get-RemnexaActiveProgress
    if ($parent) { Write-RemnexaProgressFrame $parent -Force:(Test-RemnexaInteractiveProgress) }
}

function Suspend-RemnexaProgress {
    foreach ($state in $script:ProgressActive) { $state.Waiting=$true; Write-RemnexaProgressFrame $state -Force }
}

function Resume-RemnexaProgress {
    foreach ($state in $script:ProgressActive) { $state.Waiting=$false; Write-RemnexaProgressFrame $state -Force }
}

Export-ModuleMember -Function New-RemnexaProgress,Update-RemnexaProgress,Complete-RemnexaProgress,Get-RemnexaProgressFrame,Get-RemnexaProgressText,Set-RemnexaProgressLanguage,Set-RemnexaProgressRendering,Suspend-RemnexaProgress,Resume-RemnexaProgress,Get-RemnexaActiveProgress,Add-RemnexaProgressNotice
