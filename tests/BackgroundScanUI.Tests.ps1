Describe 'Background scan navigation and live controls' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        $script:bgUI=New-Module -ArgumentList $root -ScriptBlock {
            param($Root)
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'REMNEXA.ps1'),[ref]$tokens,[ref]$errors)
            foreach($name in @('Read-RemnexaInput','Format-HistoryTimestamp','Show-AVBackgroundSummary','Show-AVBackgroundManager','Show-AVScanHistoryEntries','Show-AVScanHistorySummary','Show-AVScanHistoryScreen','Invoke-AVScanWithUpdatePrompt')){
                $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
                . ([scriptblock]::Create($node.Extent.Text))
            }
            $script:Queue=[Collections.Generic.Queue[string]]::new();$script:Lines=[Collections.Generic.List[string]]::new();$script:Actions=[Collections.Generic.List[string]]::new()
            $script:Language='de';$script:Starts=0;$script:SyncScans=0
            $script:Locale=[IO.File]::ReadAllText((Join-Path $Root 'locales/de.json'))|ConvertFrom-Json -AsHashtable
            function T {param($Key,[object[]]$Values=@())$text=$script:Locale[$Key];if($Values.Count){$text -f $Values}else{$text}}
            function Read-Host {param($Prompt)if(-not $script:Queue.Count){throw 'Unexpected UI prompt.'};$script:Queue.Dequeue()}
            function Write-Host {param($Object,$ForegroundColor)$script:Lines.Add([string]$Object)}
            function Clear-RemnexaScreen {}
            function Write-Status {param($Message,$Level)$script:Lines.Add([string]$Message)}
            function Get-ClamAVBackgroundScan {param([switch]$IncludeResults)$script:Scan}
            $script:History=@()
            function Get-ClamAVScanHistory {param($First)@($script:History|Select-Object -First $First)}
            function Start-ClamAVBackgroundScan {param($ScanType,$Path,$Language)$script:Starts++;$script:Scan=$script:Prototype}
            function Set-ClamAVBackgroundScan {param($Action)$script:Actions.Add($Action);switch($Action){'Pause'{$script:Scan.State='Paused'};'Resume'{$script:Scan.State='Running'};'Cancel'{$script:Scan.State='Cancelled'}}}
            function Get-ClamAVUpdateState {[pscustomobject]@{engine=[pscustomobject]@{updateAvailable=$false;canUpdate=$false;isStale=$true};signatures=[pscustomobject]@{status='unknown';canUpdate=$false;isStale=$true}}}
            function Invoke-ClamAVScan {param($ScanType,$Path)$script:SyncScans++}
            $script:Scan=$null
            $script:Prototype=[pscustomobject]@{State='Running';Phase='Scanning';Mode='Balanced';Error='';Files=3;Total=10;Findings=1;Omitted=0;ElapsedSeconds=4;ActiveSeconds=3;Evidence=@('fixture: Harmless FOUND');Results=@()}
        }
    }
    AfterEach {Remove-Module $script:bgUI -ErrorAction SilentlyContinue}
    It 'starts an interactive scan in the background and does not call the synchronous scan' {
        & $script:bgUI {Invoke-AVScanWithUpdatePrompt -ScanType Quick -Background|Out-Null;if($script:Starts -ne 1 -or $script:SyncScans){throw 'Interactive scan still blocked navigation.'}}
    }
    It 'opens the scan manager from another input prompt and returns to that same prompt' {
        & $script:bgUI {
            $script:Scan=$script:Prototype
            foreach($inputValue in @('/scan','P','R','C','0','2')){$script:Queue.Enqueue($inputValue)}
            $answer=Read-RemnexaInput 'fixture'
            if($answer -ne '2' -or ($script:Actions -join ',') -ne 'Pause,Resume,Cancel' -or $script:Queue.Count){throw 'Scan manager lost the original navigation or a control action.'}
        }
    }
    It 'does not offer pause or cancellation for a finished scan and never invents an unknown percentage' {
        & $script:bgUI {
            $script:Scan=$script:Prototype;$script:Scan.State='Completed';$script:Scan.Total=-1
            $script:Queue.Enqueue('0');Show-AVBackgroundManager
            $lines=$script:Lines -join "`n"
            if($lines -match '\[P\]|\[C\]|-1|100%'){throw 'Finished/unknown state displayed invalid controls or totals.'}
        }
    }
    It 'keeps a historical cancelled scan out of every input footer while retaining live controls for an active scan' {
        & $script:bgUI {
            $script:Scan=$script:Prototype;$script:Scan.State='Cancelled'
            $script:Queue.Enqueue('2');[void](Read-RemnexaInput fixture)
            if(($script:Lines -join "`n") -match 'Abgebrochen|Dateien 3/10|/scan:'){throw 'An old scan is still advertised as live.'}
            $script:Scan.State='Running';Show-AVBackgroundSummary
            if(($script:Lines -join "`n") -notmatch '/scan:'){throw 'Active scan controls disappeared.'}
        }
    }
    It 'labels saved zero-file results as history and does not advertise a completed clean scan' {
        & $script:bgUI {
            $script:History=@([pscustomobject]@{Id='fixture';State='Cancelled';ScanType='Unknown';Files=0;Total=189161;Findings=0;ElapsedSeconds=300;RecordedAtUtc='2026-11-22T06:43:44Z';StartedAtUtc=$null;CompletedAtUtc=$null;IsLegacy=$true})
            $script:Queue.Enqueue('0');Show-AVScanHistoryScreen
            $lines=$script:Lines -join "`n"
            if($lines -notmatch 'keine Live-Anzeige' -or $lines -notmatch 'Zuletzt' -or $lines -notmatch '2026-11-22' -or $lines -notmatch '0/189161' -or $lines -notmatch 'Keine Datei abschließend' -or $lines -notmatch 'letzten gespeicherten Stand'){throw 'Saved scan context is missing.'}
            if($lines -match '\[N\]|\[P\]|\[C\]|100%'){throw 'Invalid navigation or scan controls in historical results.'}
        }
    }
    It 'shows pagination only when the corresponding history page exists' {
        & $script:bgUI {
            $script:History=@(1..6|ForEach-Object{[pscustomobject]@{Id=[string]$_;State='Completed';ScanType='Quick';Files=1;Total=1;Findings=0;ElapsedSeconds=1;RecordedAtUtc='2026-11-22T06:43:44Z';StartedAtUtc=$null;CompletedAtUtc=$null;IsLegacy=$false}})
            $script:Queue.Enqueue('0');Show-AVScanHistoryScreen
            if(($script:Lines -join "`n") -notmatch '\[N\]' -or ($script:Lines -join "`n") -match '\[P\]'){throw 'First page navigation is invalid.'}
            $script:Lines.Clear();foreach($choice in @('N','0')){$script:Queue.Enqueue($choice)};Show-AVScanHistoryScreen
            $last=$script:Lines -join "`n"
            if($last -notmatch '\[P\]' -or $script:Lines[-4..-1] -match '\[N\]'){throw 'Last page navigation is invalid.'}
        }
    }
    It 'opens history with /scans and returns to the original prompt' {
        & $script:bgUI {foreach($choice in @('/scans','0','2')){$script:Queue.Enqueue($choice)};$answer=Read-RemnexaInput fixture;if($answer -ne '2' -or $script:Queue.Count){throw 'History shortcut lost the calling prompt.'}}
    }
}
