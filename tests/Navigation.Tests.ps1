Describe 'REMNEXA conditional pagination and exit options' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $script:navigationModule = New-Module -ArgumentList $projectRoot -ScriptBlock {
            param($ProjectRoot)
            Import-Module (Join-Path $ProjectRoot 'Core\Progress.psd1') -Force
            Set-RemnexaProgressRendering -Enabled $false
            Import-Module (Join-Path $ProjectRoot 'Core\MenuChoices.psd1') -Force
            $script:Texts = Get-Content -LiteralPath (Join-Path $ProjectRoot 'locales\en.json') -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectRoot 'REMNEXA.ps1'), [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw 'Application source did not parse.' }
            $names = @('Read-RemnexaInput','Show-PageNavigation','Select-ProgramPaged','Invoke-StartupList','Invoke-ActiveServicesScreen','Show-HomeMenu','Read-AfterOperationChoice','Read-ExplicitConfirmation','Read-RemovalConfirmation','Read-AppxRemovalScope','Read-MainOrExitChoice','Show-LanguageMenu','Show-AdvancedToolsMenu','Invoke-LogCleanupMenu')
            foreach ($name in $names) {
                $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
                if ($null -eq $definition) { throw "Missing function: $name" }
                . ([scriptblock]::Create($definition.Extent.Text))
            }
            $script:Lines = New-Object 'System.Collections.Generic.List[string]'
            $script:Frames = New-Object 'System.Collections.Generic.List[string]'
            $script:Messages = New-Object 'System.Collections.Generic.List[string]'
            $script:Inputs = New-Object 'System.Collections.Generic.Queue[string]'
            $script:Items = @()
            $script:ExitRequested = $false
            $script:LastRunLogPath = ''
            $script:Language = 'en'
            $script:LogRoot = 'FixtureOnly'
            function T { param($Key, $Values) return ($script:Texts[$Key] -f $Values) }
            function Write-Host { param($Object, $ForegroundColor) $script:Lines.Add([string]$Object) }
            function Write-Status { param($Message, $Level) $script:Messages.Add([string]$Message) }
            function Read-Host {
                param($Prompt)
                $script:Frames.Add(($script:Lines -join "`n"))
                $script:Lines.Clear()
                if ($script:Inputs.Count -eq 0) { throw 'Unexpected extra prompt.' }
                return $script:Inputs.Dequeue()
            }
            function Clear-RemnexaScreen { }
            function Confirm-RemnexaExit { return $true }
            function Show-BrandHeader { }
            function Start-Sleep { param($Milliseconds) }
            function Get-OptionalPropertyValue { param($InputObject, $PropertyName) return '' }
            function Get-StartupItems { return $script:Items }
            function Get-CimInstance { param($ClassName, $ErrorAction) return $script:Items }
            function Get-LanguageDisplayName { param($Code) return $Code }
            function Test-Path { param($LiteralPath) return $false }
            function Start-FixtureList {
                param([string]$Mode, [int]$Count, [string[]]$Answers)
                $script:Lines.Clear(); $script:Frames.Clear(); $script:Messages.Clear(); $script:Inputs.Clear()
                foreach ($answer in $Answers) { $script:Inputs.Enqueue($answer) }
                $script:Items = @(for ($index=1; $index -le $Count; $index++) {
                    [PSCustomObject]@{
                        DisplayName = ('App {0:D3}' -f $index); DisplayVersion = ''; SourceLabel = 'Fixture'; Publisher = 'Fixture'; CanUninstall = $true
                        Name = ('Item{0:D3}' -f $index); Command = 'Fixture'; SourceType = 'Fixture'; Scope = 'User'; IsProtected = $false; RequiresAdmin = $false
                        State = 'Running'; StartMode = 'Manual'; ProcessId = $index
                    }
                })
                switch ($Mode) {
                    'Programs' { [void](Select-ProgramPaged -Programs $script:Items -Title 'Fixture programs') }
                    'Startup' { [void](Invoke-StartupList) }
                    'Services' { [void](Invoke-ActiveServicesScreen) }
                    default { throw 'Unknown fixture list.' }
                }
            }
            Export-ModuleMember -Function @() -Variable @()
        }
    }

    It 'computes valid navigation at empty exact-boundary first middle last and resumed pages' {
        & $script:navigationModule {
            foreach ($case in @(
                @(0,18,0,1,0,$false,$false), @(1,18,0,1,0,$false,$false), @(18,18,0,1,0,$false,$false),
                @(19,18,0,2,0,$true,$false), @(37,18,1,3,1,$true,$true), @(37,18,2,3,2,$false,$true),
                @(1,18,99,1,0,$false,$false), @(37,18,-1,3,0,$true,$false)
            )) {
                $state = Get-RemnexaPageState -ItemCount $case[0] -PageSize $case[1] -PageIndex $case[2]
                if ($state.PageCount -ne $case[3] -or $state.PageIndex -ne $case[4] -or $state.HasNext -ne $case[5] -or $state.HasPrevious -ne $case[6]) {
                    throw ('Invalid page state: ' + ($case -join ','))
                }
            }
        }
    }

    It 'shows neither navigation command for single-page lists in all three areas' {
        & $script:navigationModule {
            foreach ($mode in @('Programs','Startup','Services')) {
                $pageSize = if ($mode -eq 'Services') { 20 } else { 18 }
                foreach ($count in @(0,1,$pageSize)) {
                    Start-FixtureList -Mode $mode -Count $count -Answers @('0')
                    foreach ($frame in $script:Frames) {
                        if ($frame -match 'Next page|Previous page') { throw "Single-page $mode list offered unavailable navigation." }
                    }
                }
            }
        }
    }

    It 'renders next and previous only where a page really exists in every list' {
        & $script:navigationModule {
            foreach ($mode in @('Programs','Startup','Services')) {
                $pageSize = if ($mode -eq 'Services') { 20 } else { 18 }
                $next = if ($mode -eq 'Services') { '1' } else { '-1' }
                $previous = if ($mode -eq 'Services') { '2' } else { '-2' }
                Start-FixtureList -Mode $mode -Count (2*$pageSize+1) -Answers @($next,$next,$previous,$previous,'0')
                if ($script:Frames.Count -ne 5) { throw "Unexpected prompt count in $mode." }
                $expected = @(@($true,$false),@($true,$true),@($false,$true),@($true,$true),@($true,$false))
                for ($index=0; $index -lt $expected.Count; $index++) {
                    if (($script:Frames[$index] -match 'Next page') -ne $expected[$index][0] -or ($script:Frames[$index] -match 'Previous page') -ne $expected[$index][1]) {
                        throw "Wrong navigation offered in $mode at prompt $index."
                    }
                }
            }
        }
    }

    It 'explains unavailable page commands and stays at the boundary in every list' {
        & $script:navigationModule {
            foreach ($mode in @('Programs','Startup','Services')) {
                $pageSize = if ($mode -eq 'Services') { 20 } else { 18 }
                $next = if ($mode -eq 'Services') { '1' } else { '-1' }
                $previous = if ($mode -eq 'Services') { '2' } else { '-2' }
                Start-FixtureList -Mode $mode -Count ($pageSize+1) -Answers @($previous,$next,$next,'0')
                if (-not $script:Messages.Contains($script:Texts.PagePreviousUnavailable) -or -not $script:Messages.Contains($script:Texts.PageNextUnavailable)) {
                    throw "Unavailable page command had no explanation in $mode."
                }
                if ($script:Frames[0] -notmatch 'Next page' -or $script:Frames[1] -notmatch 'Next page' -or $script:Frames[2] -notmatch 'Previous page' -or $script:Frames[3] -notmatch 'Previous page') {
                    throw "An unavailable command moved outside the page range in $mode."
                }
            }
        }
    }

    It 'recomputes navigation when a program or service filter reduces the list to one page or zero hits' {
        & $script:navigationModule {
            foreach ($mode in @('Programs','Services')) {
                $next = if ($mode -eq 'Services') { '1' } else { '-1' }
                $search = if ($mode -eq 'Services') { '3' } else { '-3' }
                foreach ($query in @('App 001','NoMatch')) {
                    Start-FixtureList -Mode $mode -Count 41 -Answers @($next,$search,$query,'0')
                    $final = $script:Frames[$script:Frames.Count-1]
                    if ($final -match 'Next page|Previous page') { throw "Filtered $mode offered a nonexistent page." }
                }
            }
        }
    }

    It 'omits X wherever zero already exits and preserves the existing zero choice' {
        & $script:navigationModule {
            foreach ($menu in @('Show-HomeMenu','Read-AfterOperationChoice','Read-ExplicitConfirmation','Read-RemovalConfirmation','Read-AppxRemovalScope','Read-MainOrExitChoice','Invoke-LogCleanupMenu')) {
                $script:Frames.Clear(); $script:Lines.Clear(); $script:Inputs.Clear(); $script:Inputs.Enqueue('0')
                $result = switch ($menu) {
                    'Read-ExplicitConfirmation' { Read-ExplicitConfirmation -WarningText 'Fixture' -ActionText 'Preview only' }
                    'Read-RemovalConfirmation' { Read-RemovalConfirmation -ProgramName 'Fixture' }
                    default { & $menu }
                }
                if ($script:Frames.Count -ne 1 -or $script:Frames[0] -match '\[X\]') { throw "Duplicate exit option in $menu." }
                if ([string]$result -notin @('0','exit')) { throw "Zero no longer exits $menu." }
            }
            Start-FixtureList -Mode Programs -Count 1 -Answers @('0')
            if ($script:Frames[0] -match '\[X\]' -or -not $script:ExitRequested) { throw 'The program list exit choice was duplicated or lost.' }
        }
    }

    It 'keeps X when zero means Back including list submenus and filter input' {
        & $script:navigationModule {
            foreach ($mode in @('Startup','Services')) {
                Start-FixtureList -Mode $mode -Count 1 -Answers @('0')
                if ($script:Frames[0] -notmatch '\[X\]') { throw "The direct exit option disappeared from $mode." }
            }
            foreach ($menu in @('Show-LanguageMenu','Show-AdvancedToolsMenu')) {
                $script:Frames.Clear(); $script:Lines.Clear(); $script:Inputs.Clear(); $script:Inputs.Enqueue('0')
                [void](& $menu)
                if ($script:Frames[0] -notmatch '\[X\]') { throw "The direct exit option disappeared from $menu." }
            }
            Start-FixtureList -Mode Programs -Count 1 -Answers @('-3','0','0')
            if ($script:Frames[1] -notmatch '\[X\]' -or $script:Frames[2] -match '\[X\]') { throw 'Text entry and menu exit semantics were confused.' }
        }
    }

    It 'marks every zero-exit prompt without hiding X from Back prompts in mixed workflows' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'REMNEXA.ps1'),[ref]$tokens,[ref]$errors)
        $expected=@{
            'Select-ProgramPaged'=2; 'Show-HomeMenu'=1; 'Read-AfterOperationChoice'=1; 'Read-MainOrExitChoice'=1
            'Read-ExplicitConfirmation'=1; 'Invoke-PrivacyMenu'=1; 'Invoke-LogCleanupMenu'=1
            'Read-RemovalConfirmation'=1; 'Read-AppxRemovalScope'=1; 'Invoke-RemovalOperationCore'=1
            'Show-AVBackgroundManager'=2
            'Confirm-RemnexaExit'=1
        }
        $found=@{}
        foreach($command in $ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Read-RemnexaInput'},$true)) {
            $hasFlag=@($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'ExitOptionAlreadyShown' }).Count -gt 0
            if (-not $hasFlag) { continue }
            $owner=$command.Parent
            while($null -ne $owner -and $owner -isnot [Management.Automation.Language.FunctionDefinitionAst]){$owner=$owner.Parent}
            if ($owner.Name -notin $expected.Keys) { throw "Exit option hidden in unexpected context: $($owner.Name)" }
            if($owner.Name -eq 'Show-AVBackgroundManager' -and @([regex]::Matches($owner.Extent.Text,'\[X\].*ExitApplication')).Count -ne 2){throw 'The scan manager must explicitly show exit in both views.'}
            if($owner.Name -eq 'Confirm-RemnexaExit' -and $command.Extent.Text -notmatch 'ExitDecisionContext'){throw 'An exit decision must not recurse through the exit wrapper.'}
            $found[$owner.Name]++
        }
        foreach($name in $expected.Keys) { if($found[$name] -ne $expected[$name]) { throw "Wrong zero-exit prompt coverage in $name." } }
    }
}
