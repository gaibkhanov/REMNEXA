Describe 'ClamAV smart-update console workflows' {
    BeforeEach {
        $root=Split-Path -Parent $PSScriptRoot
        $script:smartUI=New-Module -ArgumentList $root -ScriptBlock {
            param($Root)
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText((Join-Path $Root 'REMNEXA.ps1')),[ref]$tokens,[ref]$errors)
            foreach($name in @('Get-AVUpdateStatusText','Show-AVUpdateSummary','Invoke-AVConfirmedUpdate','Invoke-AVUpdateMenu','Invoke-AVScanWithUpdatePrompt','Invoke-AntivirusMenu')) {
                $definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
                . ([scriptblock]::Create($definition.Extent.Text))
            }
            $script:InputQueue=[Collections.Generic.Queue[string]]::new()
            $script:HostLines=[Collections.Generic.List[string]]::new()
            $script:Events=[Collections.Generic.List[string]]::new()
            $script:Scans=0;$script:Updates=0;$script:Checks=0;$script:Forced=$false;$script:FailUpdate=$false;$script:Component=''
            $script:UIState=[pscustomobject]@{
                status='update_available';isChecking=$false;isStale=$false;lastSuccessfulCheckUtc=[DateTimeOffset]::UtcNow.ToString('o')
                engine=[pscustomobject]@{installedVersion='1.5.4';availableVersion='1.5.4';status='current';updateAvailable=$false;canUpdate=$false;isStale=$false}
                signatures=[pscustomobject]@{status='update_available';canUpdate=$true;recommended=$true;isStale=$false;databases=@()}
            }
            $script:Translations=[IO.File]::ReadAllText((Join-Path $Root 'locales/de.json'))|ConvertFrom-Json -AsHashtable
            function T {param($Key,[object[]]$Values=@())$value=if($script:Translations.ContainsKey($Key)){$script:Translations[$Key]}else{$Key};if($Values.Count){return ($value -f $Values)};return $value}
            function Write-Host {param($Object,$ForegroundColor)$script:HostLines.Add([string]$Object)}
            function Write-Status {param($Message,$Level)$script:HostLines.Add([string]$Message)}
            function Write-LogEntry {param($Message,$Level,$Component)}
            function Read-RemnexaInput {param($Prompt)if(-not $script:InputQueue.Count){throw 'Unexpected extra prompt.'};$script:InputQueue.Dequeue()}
            function Get-ClamAVUpdateState {return $script:UIState}
            function Invoke-ClamAVUpdateCheck {param([switch]$Force)$script:Checks++;$script:Forced=[bool]$Force;return $script:UIState}
            function Invoke-ClamAVManagedUpdate {param($Component,[bool]$Confirm)$script:Updates++;$script:Component=$Component;$script:Events.Add('update');if($script:FailUpdate){throw 'fixture failure'};[pscustomobject]@{Ready=$true}}
            function Invoke-ClamAVScan {param($ScanType,$Path)$script:Scans++;$script:Events.Add('scan');[pscustomobject]@{Status='Clean';Severity='None';Signature='';Path='fixture'}}
            function Invoke-ClamAVTargetedScan {param($Path)Invoke-ClamAVScan -ScanType Custom -Path $Path}
            function Format-HistoryTimestamp {param($Timestamp)$Timestamp}
            function Request-ElevationForTool {param($Mode)return $true}
            function Initialize-AntivirusModule {return $true}
            function Clear-RemnexaScreen {}
            function Show-BrandHeader {}
            function Get-ClamAVStatus {[pscustomobject]@{Installed=$true;Ready=$true;Version='1.5.4'}}
        }
    }
    AfterEach {Remove-Module $script:smartUI -ErrorAction SilentlyContinue}

    It 'updates on confirmation and then resumes the original quick scan exactly once' {
        & $script:smartUI {
            $script:InputQueue.Enqueue('J')
            Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null
            if($script:Updates -ne 1 -or $script:Scans -ne 1 -or ($script:Events -join ',') -ne 'update,scan' -or $script:Component -ne 'Signatures'){throw 'Confirmed scan sequence failed.'}
        }
    }
    It 'scans directly with existing signatures when the user declines' {
        & $script:smartUI {$script:InputQueue.Enqueue('N');Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Updates -or $script:Scans -ne 1){throw 'Declining did not preserve the scan.'}}
    }
    It 'shows information without creating a second update or losing a custom scan path' {
        & $script:smartUI {$script:InputQueue.Enqueue('I');$script:InputQueue.Enqueue('J');Invoke-AVScanWithUpdatePrompt -ScanType Custom -Path 'fixture'|Out-Null;if($script:Updates -ne 1 -or $script:Scans -ne 1 -or $script:InputQueue.Count){throw 'Information flow duplicated a prompt or action.'}}
    }
    It 'requires separate consent to scan after an update failure' {
        & $script:smartUI {$script:FailUpdate=$true;$script:InputQueue.Enqueue('J');$script:InputQueue.Enqueue('0');Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Updates -ne 1 -or $script:Scans){throw 'A failed update silently started a scan.'}}
    }
    It 'continues with the existing scan only after explicit post-failure approval' {
        & $script:smartUI {$script:FailUpdate=$true;$script:InputQueue.Enqueue('J');$script:InputQueue.Enqueue('J');Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Updates -ne 1 -or $script:Scans -ne 1){throw 'Failure continuation was not bounded and explicit.'}}
    }
    It 'returns without updating or scanning when Back is selected' {
        & $script:smartUI {$script:InputQueue.Enqueue('0');Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Updates -or $script:Scans){throw 'Back performed an action.'}}
    }
    It 'does not force an update or extra question when offline or cached information is stale' {
        & $script:smartUI {$script:UIState.status='offline';$script:UIState.isStale=$true;$script:UIState.engine.isStale=$true;$script:UIState.signatures.isStale=$true;Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Updates -or $script:Scans -ne 1 -or $script:Checks){throw 'Offline scanning required a network operation.'}}
    }
    It 'selects a combined update only when both components are supported and pending' {
        & $script:smartUI {$script:UIState.engine.updateAvailable=$true;$script:UIState.engine.canUpdate=$true;$script:InputQueue.Enqueue('J');Invoke-AVScanWithUpdatePrompt -ScanType Quick|Out-Null;if($script:Component -ne 'Both'){throw 'Combined update selection failed.'}}
    }
    It 'does not offer an engine update with an unverifiable download' {
        & $script:smartUI {$script:UIState.engine.updateAvailable=$true;$script:UIState.engine.canUpdate=$false;$script:InputQueue.Enqueue('0');Invoke-AVUpdateMenu;if(@($script:HostLines|Where-Object{$_ -match '\[2\]|\[3\]'}).Count){throw 'An unsupported engine action was displayed.'}}
    }
    It 'routes U to a forced check and retains all seven existing numbered choices' {
        & $script:smartUI {
            foreach($value in @('u','1','J','0')){$script:InputQueue.Enqueue($value)}
            [void](Invoke-AntivirusMenu)
            if($script:Checks -ne 1 -or -not $script:Forced -or $script:Updates -ne 1){throw 'U did not perform the requested manual flow.'}
            foreach($number in 1..7){if(@($script:HostLines|Where-Object{$_ -match ('\['+$number+'\]')}).Count -eq 0){throw 'An existing numbered option disappeared.'}}
            if(@($script:HostLines|Where-Object{$_ -match '\[U\]'}).Count -eq 0){throw 'Manual updates are not visible.'}
        }
    }
    It 'keeps existing read-only status and Back actions reachable' {
        & $script:smartUI {foreach($value in @('1','1','0')){$script:InputQueue.Enqueue($value)};[void](Invoke-AntivirusMenu);if($script:Updates -or $script:Checks -or $script:Scans){throw 'Existing status navigation performed another action.'}}
    }
    It 'contains all new translated messages and matching format placeholders in six languages' {
        $root=Split-Path -Parent $PSScriptRoot
        $reference=[IO.File]::ReadAllText((Join-Path $root 'locales/de.json'))|ConvertFrom-Json -AsHashtable
        $keys=@($reference.Keys|Where-Object{$_ -like 'AVUpdate*'})
        foreach($code in @('de','en','es','fr','ru','tr')) {
            $messages=[IO.File]::ReadAllText((Join-Path $root ('locales/'+$code+'.json')))|ConvertFrom-Json -AsHashtable
            foreach($key in $keys){if(-not $messages.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($messages[$key])){throw 'A new update translation is missing.'};$expected=([regex]::Matches($reference[$key],'\{\d+\}').Value|Sort-Object)-join ',';$actual=([regex]::Matches($messages[$key],'\{\d+\}').Value|Sort-Object)-join ',';if($actual -ne $expected){throw 'Translation placeholders differ.'}}
        }
    }
}
