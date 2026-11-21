Describe 'Explicit exit choices for a running antivirus scan' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        $script:exitChoice=New-Module -ArgumentList $root -ScriptBlock {
            param($Root)
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'REMNEXA.ps1'),[ref]$tokens,[ref]$errors)
            foreach($name in @('Read-RemnexaInput','Confirm-RemnexaExit')){
                $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
                . ([scriptblock]::Create($node.Extent.Text))
            }
            $script:Inputs=[Collections.Generic.Queue[string]]::new();$script:Lines=[Collections.Generic.List[string]]::new()
            $script:Scan=[pscustomobject]@{State='Running'};$script:ExitScanDecision='';$script:Cancelled=0;$script:Detached=0;$script:Resumed=$false;$script:Closed=0;$script:Fail=$false
            $script:Locale=[IO.File]::ReadAllText((Join-Path $Root 'locales/de.json'))|ConvertFrom-Json -AsHashtable
            function T {param($Key,[object[]]$Values=@())$text=$script:Locale[$Key];if($Values.Count){$text -f $Values}else{$text}}
            function Read-Host {param($Prompt)if(-not $script:Inputs.Count){throw 'Extra exit question.'};$script:Inputs.Dequeue()}
            function Write-Host {param($Object,$ForegroundColor)$script:Lines.Add([string]$Object)}
            function Write-Status {param($Message,$Level)$script:Lines.Add([string]$Message)}
            function Get-ClamAVBackgroundScan {$script:Scan}
            function Stop-ClamAVBackgroundScan {if($script:Fail){throw 'Fixture cleanup pending'};$script:Cancelled++;$script:Scan.State='Cancelled'}
            function Disconnect-ClamAVBackgroundScan {param([switch]$Resume)$script:Detached++;$script:Resumed=[bool]$Resume}
            function Stop-RemnexaApplication {if(Confirm-RemnexaExit){$script:Closed++}}
        }
    }
    AfterEach {Remove-Module $script:exitChoice -ErrorAction SilentlyContinue}
    It 'requires no extra exit question without an active scan' {
        & $script:exitChoice {$script:Scan=$null;if(-not(Confirm-RemnexaExit) -or $script:Cancelled -or $script:Detached){throw 'Idle exit changed scan ownership.'}}
    }
    It 'returns to the application without changing a paused scan' {
        & $script:exitChoice {$script:Scan.State='Paused';$script:Inputs.Enqueue('0');if((Confirm-RemnexaExit) -or $script:Scan.State -ne 'Paused' -or $script:Cancelled -or $script:Detached){throw 'Back affected the scan.'}}
    }
    It 'explicitly resumes and detaches on continue and asks only once' {
        & $script:exitChoice {$script:Scan.State='Paused';$script:Inputs.Enqueue('1');if(-not(Confirm-RemnexaExit) -or -not(Confirm-RemnexaExit) -or $script:Detached -ne 1 -or -not $script:Resumed -or $script:Cancelled){throw 'Continue cancelled or duplicated the choice.'}}
    }
    It 'cancels only after the user selects cancel-and-exit' {
        & $script:exitChoice {$script:Inputs.Enqueue('2');if(-not(Confirm-RemnexaExit) -or $script:Cancelled -ne 1 -or $script:Detached){throw 'Cancel choice was not respected.'}}
    }
    It 'keeps the original prompt usable after cancelling an X exit request' {
        & $script:exitChoice {foreach($value in @('x','0','5')){$script:Inputs.Enqueue($value)};if((Read-RemnexaInput 'fixture') -ne '5' -or $script:Closed -or $script:Cancelled -or $script:Detached){throw 'Cancelled exit did not return to the same prompt.'}}
    }
    It 'checks zero-exit menus and never recursively exits from the confirmation itself' {
        & $script:exitChoice {foreach($value in @('0','x','7')){$script:Inputs.Enqueue($value)};if((Read-RemnexaInput 'fixture' -ExitOptionAlreadyShown) -ne '7' -or $script:Closed -or $script:Cancelled){throw 'Exit confirmation recursed or swallowed navigation.'}}
    }
    It 'keeps REMNEXA open if cancellation cleanup is not confirmed' {
        & $script:exitChoice {$script:Fail=$true;$script:Inputs.Enqueue('2');if((Confirm-RemnexaExit) -or $script:ExitScanDecision -or $script:Detached){throw 'Unconfirmed cleanup allowed exit.'}}
    }
    It 'does not offer continuation for an already cancelling scan and has all six translations' {
        & $script:exitChoice {$script:Scan.State='Cancelling';$script:Inputs.Enqueue('0');[void](Confirm-RemnexaExit);if(($script:Lines -join "`n") -match '\[1\]'){throw 'An irreversible cancellation offered resume.'}}
        $root=Split-Path -Parent $PSScriptRoot
        $reference=[IO.File]::ReadAllText((Join-Path $root 'locales/de.json'))|ConvertFrom-Json -AsHashtable
        foreach($code in @('de','en','es','fr','ru','tr')){
            $locale=[IO.File]::ReadAllText((Join-Path $root ('locales/'+$code+'.json')))|ConvertFrom-Json -AsHashtable
            foreach($key in @($reference.Keys|Where-Object{$_ -like 'AVExit*' -or $_ -like 'AVSession*'})){
                if(-not $locale.Contains($key) -or -not $locale[$key]){throw 'Missing exit/session translation.'}
                if((([regex]::Matches($reference[$key],'\{\d+\}').Value|Sort-Object)-join ',') -ne (([regex]::Matches($locale[$key],'\{\d+\}').Value|Sort-Object)-join ',')){throw 'Exit translation placeholders differ.'}
            }
        }
    }
}
