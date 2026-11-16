Describe 'REMNEXA antivirus elevation flow' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $script:avElevationModule = New-Module -ArgumentList (Join-Path $projectRoot 'REMNEXA.ps1') -ScriptBlock {
            param($ApplicationPath)
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($ApplicationPath, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) { throw 'Application source did not parse.' }
            foreach ($name in @('Confirm-AdministratorRequest', 'Request-ElevationForRemoval', 'Request-ElevationForTool', 'Invoke-AntivirusMenu', 'ConvertTo-SingleQuotedLiteral')) {
                $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
                if ($null -eq $definition) { throw "Missing application function: $name" }
                . ([scriptblock]::Create($definition.Extent.Text))
            }
            $script:Admin = $false
            $script:NoElevation = $false
            $script:NoRestorePoint = $false
            $script:OverrideProtectedComponent = $false
            $script:InitializeCount = 0
            $script:ReadCount = 0
            $script:LaunchCount = 0
            $script:LaunchArguments = @()
            $script:LaunchVerb = ''
            $script:InputText = ''
            $script:InputQueue = New-Object 'System.Collections.Generic.Queue[string]'
            $script:Messages = New-Object 'System.Collections.Generic.List[string]'
            $script:HostLines = New-Object 'System.Collections.Generic.List[string]'
            $script:Events = New-Object 'System.Collections.Generic.List[string]'
            function Test-IsAdministrator { return $script:Admin }
            function Initialize-AntivirusModule { $script:InitializeCount++; return $true }
            function T { param($Key) return $Key }
            function Write-Status { param($Message, $Level) $script:Messages.Add($Message); $script:Events.Add($Message) }
            function Clear-Host { }
            function Show-BrandHeader { }
            function Write-Host { param($Object, $ForegroundColor) $script:HostLines.Add([string]$Object) }
            function Read-RemnexaInput {
                param($Prompt)
                $script:ReadCount++
                $script:Events.Add('ReadInput')
                if ($script:Admin) { return '0' }
                if ($script:InputQueue.Count -gt 0) { return $script:InputQueue.Dequeue() }
                return $script:InputText
            }
            function Start-Process {
                param($FilePath, $Verb, $ArgumentList, $WorkingDirectory)
                $script:LaunchCount++
                $script:LaunchVerb = $Verb
                $script:LaunchArguments = @($ArgumentList)
                $script:Events.Add('Launch')
                throw [ComponentModel.Win32Exception]::new(1223)
            }
            Export-ModuleMember -Function @() -Variable @()
        }
    }

    It 'requests Windows elevation before initializing or running the antivirus menu' {
        & $script:avElevationModule {
            $result = Invoke-AntivirusMenu
            if ($result -ne 'menu' -or $script:LaunchCount -ne 1 -or $script:LaunchVerb -ne 'RunAs') {
                throw 'The unelevated antivirus entry did not request a single Windows RunAs launch.'
            }
            if ($script:InitializeCount -ne 0 -or $script:ReadCount -ne 1) {
                throw 'The original process entered the antivirus menu after the UAC request was cancelled.'
            }
            if (-not $script:Messages.Contains('UacCancelled')) { throw 'UAC cancellation was not reported.' }
        }
    }

    It 'opens the antivirus menu directly when the current process is already elevated' {
        & $script:avElevationModule {
            $script:Admin = $true
            $result = Invoke-AntivirusMenu
            if ($result -ne 'menu' -or $script:LaunchCount -ne 0 -or $script:InitializeCount -ne 1 -or $script:ReadCount -ne 1) {
                throw 'An elevated process should open the menu without launching another process.'
            }
        }
    }

    It 'respects NoElevation and reports that administrator rights are required' {
        & $script:avElevationModule {
            $script:NoElevation = $true
            $result = Invoke-AntivirusMenu
            if ($result -ne 'menu' -or $script:LaunchCount -ne 0 -or $script:InitializeCount -ne 0) {
                throw 'NoElevation must not launch a process or open the antivirus menu.'
            }
            if (-not $script:Messages.Contains('AdminRequired')) { throw 'The blocked elevation request was not explained.' }
        }
    }

    It 'preserves the antivirus workspace and interactive continuation in the elevated launch' {
        & $script:avElevationModule {
            [void](Request-ElevationForTool -Mode Antivirus)
            $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:LaunchArguments[-1]))
            foreach ($expected in @("-ToolMode 'Antivirus'", '-WorkspaceMode Antivirus', '-ContinueInteractive')) {
                if (-not $command.Contains($expected)) { throw "The elevated launch lost its navigation context: $expected" }
            }
        }
    }

    It 'explains the correct reason before the Windows prompt for every elevated tool area' {
        & $script:avElevationModule {
            $cases = @(
                @{ Mode = 'Registry'; ItemId = ''; Reason = 'AdminReasonRegistry' },
                @{ Mode = 'Features'; ItemId = ''; Reason = 'AdminReasonFeatures' },
                @{ Mode = 'Privacy'; ItemId = ''; Reason = 'AdminReasonPrivacy' },
                @{ Mode = 'Antivirus'; ItemId = ''; Reason = 'AdminReasonAntivirus' },
                @{ Mode = 'Startup'; ItemId = 'item-id'; Reason = 'AdminReasonStartupDisable' },
                @{ Mode = 'Startup'; ItemId = 'restore:backup-id'; Reason = 'AdminReasonStartupRestore' }
            )
            foreach ($case in $cases) {
                $script:Messages.Clear(); $script:HostLines.Clear(); $script:Events.Clear()
                [void](Request-ElevationForTool -Mode $case.Mode -ItemId $case.ItemId)
                if ($script:Messages[0] -ne $case.Reason) { throw "Incorrect administrator explanation for $($case.Mode)." }
                if (-not $script:HostLines.Contains('AdminNoticeInstructions')) { throw 'Windows Yes/No guidance was not displayed.' }
                if ($script:Events.IndexOf($case.Reason) -ge $script:Events.IndexOf('ReadInput') -or $script:Events.IndexOf('ReadInput') -ge $script:Events.IndexOf('Launch')) {
                    throw 'The explanation was not acknowledged before launching the Windows prompt.'
                }
            }
        }
    }

    It 'distinguishes uninstalling from cleaning leftovers in the administrator explanation' {
        & $script:avElevationModule {
            foreach ($residual in @($false, $true)) {
                $script:Messages.Clear(); $script:Events.Clear()
                [void](Request-ElevationForRemoval -SearchName 'Fixture' -Program $null -IsResidualOnly $residual -ContinueSession $false -ProtectedOverride $false -ProvisionedAppx $false)
                $expected = if ($residual) { 'AdminReasonResidual' } else { 'AdminReasonRemoval' }
                if ($script:Messages[0] -ne $expected -or $script:Events.IndexOf('ReadInput') -ge $script:Events.IndexOf('Launch')) { throw 'The removal explanation was incorrect or displayed too late.' }
            }
        }
    }

    It 'returns without launching UAC when the user chooses Back at the explanation' {
        & $script:avElevationModule {
            $script:InputText = '0'
            if (Request-ElevationForTool -Mode Antivirus) { throw 'Returning from the explanation was treated as approval.' }
            if ($script:LaunchCount -ne 0 -or -not $script:Messages.Contains('SelectionCancelled')) { throw 'The Windows prompt opened after choosing Back.' }
            if (Request-ElevationForRemoval -SearchName 'Fixture' -Program $null) { throw 'The removal request ignored Back.' }
            if ($script:LaunchCount -ne 0) { throw 'The removal request opened UAC after Back.' }
        }
    }

    It 'rejects arbitrary input without opening UAC and keeps the Back option available' {
        & $script:avElevationModule {
            $script:InputQueue.Enqueue('unexpected input')
            $script:InputQueue.Enqueue('0')
            if (Request-ElevationForTool -Mode Registry) { throw 'Invalid input was accepted as administrator approval.' }
            if ($script:LaunchCount -ne 0 -or $script:ReadCount -ne 2 -or -not $script:Messages.Contains('AdminNoticeInvalid')) { throw 'Invalid notice input did not remain in the safe input loop.' }
        }
    }

    It 'does not repeat the administrator explanation for an already elevated process' {
        & $script:avElevationModule {
            $script:Admin = $true
            if (-not (Request-ElevationForTool -Mode Antivirus)) { throw 'An elevated process should remain usable.' }
            if (-not (Request-ElevationForRemoval -SearchName 'Fixture' -Program $null)) { throw 'An elevated removal request should remain usable.' }
            if ($script:LaunchCount -ne 0 -or $script:ReadCount -ne 0 -or $script:Messages.Count -ne 0) { throw 'The elevated process was unnecessarily prompted again.' }
        }
    }
}
