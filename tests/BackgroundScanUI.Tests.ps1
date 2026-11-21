Describe 'Background scan navigation and live controls' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        $script:bgUI=New-Module -ArgumentList $root -ScriptBlock {
            param($Root)
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'REMNEXA.ps1'),[ref]$tokens,[ref]$errors)
            foreach($name in @('Read-RemnexaInput','Show-AVBackgroundSummary','Show-AVBackgroundManager','Invoke-AVScanWithUpdatePrompt')){
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
}
