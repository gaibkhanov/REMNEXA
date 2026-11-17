Describe 'REMNEXA measured progress and terminal states' {
    BeforeEach {
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Core\Progress.psd1') -Force
        Set-RemnexaProgressRendering -Enabled $false
        Set-RemnexaProgressLanguage -LanguageCode en
    }

    It 'computes percentages from processed items and reserves green for completion' {
        $state = New-RemnexaProgress -Activity fixture -Total 4 -Unit files
        foreach ($count in @(0,1,2,3,4)) {
            Update-RemnexaProgress $state -Completed $count
            $frame = Get-RemnexaProgressFrame $state
            if ($frame.Percent -ne ($count * 25) -or $frame.Color -ne 'Cyan') { throw 'Measured work was presented incorrectly.' }
        }
        Complete-RemnexaProgress $state
        $frame = Get-RemnexaProgressFrame $state
        if ($frame.Percent -ne 100 -or $frame.Color -ne 'Green') { throw 'Verified completion is not green.' }
    }

    It 'keeps unknown work indeterminate and strips terminal control characters' {
        $state = New-RemnexaProgress -Activity fixture
        Update-RemnexaProgress $state -Completed 7 -CurrentItem ("unsafe" + [char]27 + '[2J')
        $frame = Get-RemnexaProgressFrame $state
        if ($frame.Percent -ne -1 -or $frame.Text.Contains([string][char]27)) { throw 'Unknown work or untrusted terminal text was mishandled.' }
        Complete-RemnexaProgress $state
    }

    It 'rejects backwards counts, overflowing totals and premature success' {
        $state = New-RemnexaProgress -Activity fixture -Total 4
        Update-RemnexaProgress $state -Completed 2
        foreach ($kind in @('backwards','overflow','early')) {
            $rejected = $false
            try {
                switch ($kind) {
                    backwards { Update-RemnexaProgress $state -Completed 1 }
                    overflow { Update-RemnexaProgress $state -Completed 5 }
                    early { Complete-RemnexaProgress $state }
                }
            }
            catch { $rejected=$true }
            if (-not $rejected) { throw 'Invalid progress was accepted.' }
        }
        Complete-RemnexaProgress $state -Outcome Cancelled
    }

    It 'keeps errors red, partial work yellow and propagates notices to parents' {
        $parent=New-RemnexaProgress -Activity parent
        $child=New-RemnexaProgress -Activity child -Total 1
        if ($child.ParentId -ne $parent.Id) { throw 'Nested task parent was lost.' }
        Add-RemnexaProgressNotice -Level Warning
        Update-RemnexaProgress $child -Completed 1
        Complete-RemnexaProgress $child
        if ((Get-RemnexaProgressFrame $child).Color -ne 'Yellow') { throw 'A partial result was green.' }
        Add-RemnexaProgressNotice -Level Error
        Complete-RemnexaProgress $parent
        if ((Get-RemnexaProgressFrame $parent).Color -ne 'Red') { throw 'An error was green.' }
        if ($null -ne (Get-RemnexaActiveProgress)) { throw 'Finished tasks remained active.' }
    }

    It 'marks user input as waiting without changing the measured counts' {
        $state=New-RemnexaProgress -Activity fixture -Total 10
        Update-RemnexaProgress $state -Completed 3
        Suspend-RemnexaProgress
        if ((Get-RemnexaProgressFrame $state).Color -ne 'Yellow' -or $state.Completed -ne 3) { throw 'User wait was shown as processing.' }
        Resume-RemnexaProgress
        if ((Get-RemnexaProgressFrame $state).Color -ne 'Cyan' -or $state.Completed -ne 3) { throw 'Resume changed the counter.' }
        Complete-RemnexaProgress $state -Outcome Cancelled
    }

    It 'retains the actual fraction when incomplete work ends with a warning' {
        $state=New-RemnexaProgress -Activity fixture -Total 10
        Update-RemnexaProgress $state -Completed 3
        Complete-RemnexaProgress $state -Outcome Warning
        $frame=Get-RemnexaProgressFrame $state
        if($frame.Percent -ne 30 -or $frame.Completed -ne 3 -or $frame.Color -ne 'Yellow'){throw 'Partial completion inflated the processed count or percentage.'}
        if(Get-RemnexaActiveProgress){throw 'Partial completion remained active.'}
    }

    It 'provides progress text in six languages with a German fallback' {
        foreach ($code in @('de','en','es','fr','ru','tr')) {
            Set-RemnexaProgressLanguage -LanguageCode $code
            foreach ($key in @('ProgressRunning','ProgressUnknown','ProgressWaiting','ProgressTaskScan','ProgressScanCoverage')) {
                if ((Get-RemnexaProgressText $key) -eq $key) { throw 'A progress translation is missing.' }
            }
        }
        Set-RemnexaProgressLanguage -LanguageCode unknown
        if ((Get-RemnexaProgressText ProgressRunning) -ne 'Wird verarbeitet') { throw 'German fallback failed.' }
    }
}

Describe 'REMNEXA live native-process observation' {
    BeforeEach { Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Core\NativeProcess.psd1') -Force }

    It 'reports output before exit and emits heartbeats while retaining only selected lines' {
        $events=[Collections.Generic.List[object]]::new()
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $state=[pscustomobject]@{Ticks=0}
        $onOutput={param($Line,$Stream)$events.Add([pscustomobject]@{Text=$Line;At=$watch.ElapsedMilliseconds;Stream=$Stream})}.GetNewClosure()
        $pulse={param($Event)$state.Ticks++}.GetNewClosure()
        $filter={param($Line,$Stream)return ($Line -eq 'kept')}
        $result=Invoke-RemnexaNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-Command','[Console]::Out.WriteLine("first"); Start-Sleep -Milliseconds 2200; [Console]::Out.WriteLine("kept")') -TimeoutSeconds 10 -OnOutput $onOutput -OnHeartbeat $pulse -CaptureFilter $filter
        if ($events.Count -ne 2 -or $events[0].Text -ne 'first' -or $events[0].At -ge $events[1].At -or $state.Ticks -lt 2) { throw 'Output arrived only after exit or no heartbeat was emitted.' }
        if ($result.StandardOutput.Trim() -ne 'kept') { throw 'Capture filtering lost a selected result.' }
    }

    It 'stops its owned process when a progress observer fails' {
        $state=[pscustomobject]@{Child=0}
        $observer={param($Line,$Stream)$state.Child=[int]$Line;throw 'Observer fixture failure'}.GetNewClosure()
        $rejected=$false
        try { Invoke-RemnexaNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-Command','[Console]::Out.WriteLine([Environment]::ProcessId); Start-Sleep -Seconds 60') -TimeoutSeconds 10 -OnOutput $observer|Out-Null }
        catch { $rejected=$true }
        if (-not $rejected -or $state.Child -le 0) { throw 'The observer fixture did not run.' }
        if (Get-Process -Id $state.Child -ErrorAction SilentlyContinue) { throw 'The owned child was left running.' }
    }

    It 'fails instead of discarding results when the capture budget is exceeded' {
        $rejected=$false
        try { Invoke-RemnexaNativeProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-Command','[Console]::Out.WriteLine((''a'' * 2000))') -TimeoutSeconds 10 -OnHeartbeat {} -MaxCapturedCharacters 1024|Out-Null }
        catch { $rejected=$_.Exception.Message -match 'capture limit' }
        if (-not $rejected) { throw 'Excess output was silently discarded.' }
    }
}
