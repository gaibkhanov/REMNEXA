Describe 'REMNEXA protected leftovers and optional completion checks' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $script:completionModule = New-Module -ArgumentList $projectRoot -ScriptBlock {
            param($ProjectRoot)
            Import-Module (Join-Path $ProjectRoot 'Core\Progress.psd1') -Force
            Set-RemnexaProgressRendering -Enabled $false
            Import-Module (Join-Path $ProjectRoot 'Core\PathSafety.psd1') -Force
            Import-Module (Join-Path $ProjectRoot 'Core\SecurityAssessment.psd1') -Force
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectRoot 'REMNEXA.ps1'), [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw 'Application source did not parse.' }
            foreach ($name in @('Remove-Traces', 'Remove-RegistryTrace', 'New-RestorePointIfPossible', 'Test-SystemIntegrity', 'Invoke-RemovalOperationCore', 'Invoke-PostRemovalIntegrityCheck')) {
                $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
                if ($null -eq $definition) { throw "Missing application function: $name" }
                . ([scriptblock]::Create($definition.Extent.Text))
            }
            $script:InteractiveSession = $false
            $script:NoRestorePoint = $true
            $script:IncludeUserFiles = $false
            $script:RemoveProvisionedAppx = $false
            $script:OverrideProtectedComponent = $false
            $script:ProvisionedRemovedCount = 0
            $script:RestartRequired = $false
            $script:LastRunSummary = $null
            $script:LastOperationResult = $null
            $script:LastRunLogPath = ''
            $script:Events = New-Object 'System.Collections.Generic.List[string]'
            $script:Messages = New-Object 'System.Collections.Generic.List[string]'
            $script:Traces = @()
            $script:RemoveCount = 0
            $script:DenyRemove = $false
            $script:RegistryCalls = New-Object 'System.Collections.Generic.List[string]'
            $script:DenyParent = $false
            $script:NativeExit = 0
            $script:LASTEXITCODE = 0
            $script:RestoreConfirmed = $false
            $script:RestoreDescription = ''
            $script:ServiceState = 'Stopped'
            $script:ServiceStart = 'Manual'
            $script:DefenderAvailable = $true
            $script:SecurityCenterAvailable = $true
            $script:DefenderStatus = [PSCustomObject]@{ AntivirusEnabled = $false; RealTimeProtectionEnabled = $false }
            $script:Products = @([PSCustomObject]@{ displayName = 'Panda Dome'; productState = 0; timestamp = 'fixture' })
            $script:RunOptionalCheck = $false
            function T { param($Key, $Values) return ($Key + $(if ($Values) { '|' + ($Values -join ',') } else { '' })) }
            function Write-Status { param($Message, $Level) $script:Messages.Add([string]$Message) }
            function Write-Host { param($Object, $ForegroundColor) }
            function Test-Path { param($LiteralPath) return $true }
            function Test-ProtectedFilePath { param($Path) return $false }
            function Test-ProtectedRegistryKey { param($RegistryPath) return $false }
            function Remove-Item {
                param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
                $script:RemoveCount++
                if ($script:DenyRemove) { throw [UnauthorizedAccessException]::new('Fixture access denied.') }
            }
            function reg.exe { $script:LASTEXITCODE = $script:NativeExit }
            function Checkpoint-Computer { param($Description, $RestorePointType, $ErrorAction, $WarningAction) $script:RestoreDescription = $Description }
            function Get-ComputerRestorePoint {
                param($ErrorAction)
                if ($script:RestoreConfirmed) { [PSCustomObject]@{ Description = $script:RestoreDescription } }
                else { [PSCustomObject]@{ Description = 'Older unrelated restore point' } }
            }
            function Get-CimInstance {
                param($ClassName, $Namespace, $Filter, $ErrorAction)
                if ($ClassName -eq 'AntivirusProduct') {
                    if (-not $script:SecurityCenterAvailable) { throw 'Fixture SecurityCenter unavailable.' }
                    return $script:Products
                }
                if ($ClassName -ne 'Win32_Service') { throw 'Unexpected fixture query.' }
                return [PSCustomObject]@{ State = $script:ServiceState; StartMode = $script:ServiceStart }
            }
            function Get-MpComputerStatus {
                param($ErrorAction)
                if (-not $script:DefenderAvailable) { throw 'Fixture Defender unavailable.' }
                return $script:DefenderStatus
            }
            function Confirm-ProtectedComponentOverride { param($Program, $SearchName) return $true }
            function Get-IdentityInfo { param($SearchName, $Program) return [PSCustomObject]@{ Aliases = @('fixture') } }
            function Find-AllTraces { param($Identity, $Program, $WithUserFiles) return $script:Traces }
            function Show-TraceSummary { param($Traces, [switch]$ShowAll) }
            function Request-ElevationForRemoval { param($SearchName, $Program, $IsResidualOnly, $ContinueSession, $ProtectedOverride, $ProvisionedAppx) return $true }
            function Get-SystemDriveFreeBytes { return [long]100 }
            function Invoke-ConfiguredAntivirusScan { param($Stage, $Identity, $Traces) return @() }
            function Set-OperationProgress { param($Percent, $Status) $script:Events.Add('Progress:' + $Percent) }
            function Complete-OperationProgress { $script:Events.Add('ProgressComplete') }
            function Save-RunLog { param($Program, $SearchName, $Traces, $Result) $script:Events.Add('RemovalLogSaved'); return 'fixture-removal.json' }
            function Add-RemovalHistory { param($ProgramName, $ResidualMode, $RemovedCount, $FailedCount, $RemainingCount, $FreedBytes, $LogPath) $script:Events.Add('HistorySaved') }
            function Read-IntegrityCheckChoice { $script:Events.Add('OptionalQuestion'); return $script:RunOptionalCheck }
            function Save-ToolLog { param($Action, $Data) $script:Events.Add($Action); return 'fixture-integrity.json' }
            Export-ModuleMember -Function @() -Variable @()
        }
    }

    It 'recognizes Windows-managed package roots without matching similarly named user folders' {
        & $script:completionModule {
            foreach ($path in @('C:\Program Files\WindowsApps', '\\?\C:\Program Files\WindowsApps\Package', 'C:\Program Files\WindowsApps\Package\file.xml', 'D:\WindowsApps\Package', 'c:\program files\windowsapps\DeletedAllUserPackages\Package')) {
                if (-not (Test-RemnexaWindowsManagedPath $path)) { throw "Managed package path missed: $path" }
            }
            foreach ($path in @('C:\Program Files\WindowsAppsBackup\file', 'C:\Users\Test\WindowsApps\file', 'C:\Users\Test\AppData\Local\Packages\Package', '..\WindowsApps')) {
                if (Test-RemnexaWindowsManagedPath $path) { throw "Unrelated path classified as Windows-managed: $path" }
            }
        }
    }

    It 'never attempts manual file deletion for Windows-managed packages' {
        & $script:completionModule {
            $result = Remove-Traces @(
                [PSCustomObject]@{ Kind = 'Directory'; Target = 'C:\Program Files\WindowsApps\Package' },
                [PSCustomObject]@{ Kind = 'File'; Target = 'D:\WindowsApps\Package\manifest.xml' }
            )
            if ($result.Removed -ne 0 -or $result.Failed.Count -ne 0 -or $result.Skipped.Count -ne 2 -or $script:RemoveCount -ne 0) {
                throw 'Protected package entries were deleted or counted as failed attempts.'
            }
        }
    }

    It 'reports a genuine access denial without falsely counting the item as removed' {
        & $script:completionModule {
            $script:DenyRemove = $true
            $result = Remove-Traces @([PSCustomObject]@{ Kind = 'File'; Target = 'C:\FixtureOnly\denied.txt' })
            if ($result.Removed -ne 0 -or $result.Failed.Count -ne 1 -or $result.Failed[0] -notmatch 'TraceAccessDenied') {
                throw 'An access denial did not produce a concrete failure reason.'
            }
        }
    }

    It 'does not accept registry exit code one as a successful deletion' {
        & $script:completionModule {
            $script:NativeExit = 1
            $result = Remove-Traces @([PSCustomObject]@{ Kind = 'RegistryKey'; Target = 'HKEY_CURRENT_USER\Software\FixtureOnly' })
            if ($result.Removed -ne 0 -or $result.Failed.Count -ne 1) { throw 'Registry exit code one was counted as success.' }
        }
    }

    It 'counts child values separately only when a parent was actually removed' {
        & $script:completionModule {
            function Remove-RegistryTrace {
                param($Trace)
                $script:RegistryCalls.Add($Trace.Kind)
                if ($script:DenyParent -and $Trace.Kind -eq 'RegistryKey') { throw 'Fixture parent denied.' }
            }
            $traces = @(
                [PSCustomObject]@{ Kind = 'RegistryValue'; Target = 'HKEY_CURRENT_USER\Software\FixtureOnly'; ValueName = 'Value' },
                [PSCustomObject]@{ Kind = 'RegistryKey'; Target = 'HKEY_CURRENT_USER\Software\FixtureOnly' }
            )
            $result = Remove-Traces $traces
            if ($result.Removed -ne 1 -or $result.CoveredByParent -ne 1 -or $script:RegistryCalls.Count -ne 1) { throw 'Successful parent coverage was not counted.' }
            $script:RegistryCalls.Clear()
            $script:DenyParent = $true
            $result = Remove-Traces $traces
            if ($result.Removed -ne 1 -or $result.Failed.Count -ne 1 -or $result.CoveredByParent -ne 0 -or $script:RegistryCalls.Count -ne 2) {
                throw 'A denied parent silently suppressed the child deletion attempt.'
            }
        }
    }

    It 'does not falsely report an older restore point as a newly created backup' {
        & $script:completionModule {
            $script:NoRestorePoint = $false
            $success = New-RestorePointIfPossible -ProgramName 'Fixture'
            if ($success -or $script:Messages.Contains('RestorePointDone') -or -not $script:Messages.Contains('RestorePointUnverified')) {
                throw 'An unconfirmed restore point was reported as created.'
            }
        }
    }

    It 'accepts a restore point only when Windows returns the new unique description' {
        & $script:completionModule {
            $script:NoRestorePoint = $false
            $script:RestoreConfirmed = $true
            if (-not (New-RestorePointIfPossible -ProgramName 'Fixture') -or -not $script:Messages.Contains('RestorePointDone')) {
                throw 'The confirmed new restore point was not recognized.'
            }
        }
    }

    It 'finishes progress and saves removal results before asking about an optional check' {
        & $script:completionModule {
            $script:Traces = @([PSCustomObject]@{ Kind = 'Directory'; Target = 'C:\Program Files\WindowsApps\Fixture' })
            $completed = Invoke-RemovalOperationCore -OperationName 'Fixture' -OperationResidualOnly $true -OperationDryRun $false -PreselectedProgram $null -PreloadedPrograms @() -SkipConfirmation $true -ContinueAfterElevation $false
            if (-not $completed -or $script:Events.Contains('OptionalQuestion')) { throw 'The removal core waited for the optional check.' }
            $script:LastOperationResult = [PSCustomObject]@{ Status = 'Partial'; OperationId = [guid]::NewGuid() }
            Invoke-PostRemovalIntegrityCheck
            $question = $script:Events.IndexOf('OptionalQuestion')
            foreach ($completedEvent in @('Progress:100', 'ProgressComplete', 'RemovalLogSaved', 'HistorySaved')) {
                $index = $script:Events.IndexOf($completedEvent)
                if ($index -lt 0 -or $index -ge $question) { throw "$completedEvent did not occur before the optional question." }
            }
            if ($script:LastRunSummary.Skipped -ne 1 -or $script:LastRunSummary.Failed -ne 0 -or $script:LastRunSummary.Remaining -ne 1) {
                throw 'Intentionally retained package traces were not represented honestly.'
            }
        }
    }

    It 'links a separately logged optional check to the completed removal' {
        & $script:completionModule {
            $script:RunOptionalCheck = $true
            $script:LastRunSummary = [PSCustomObject]@{ Integrity = $null }
            $script:LastOperationResult = [PSCustomObject]@{ Status = 'Completed'; OperationId = [guid]::NewGuid() }
            $script:LastRunLogPath = 'fixture-removal.json'
            Invoke-PostRemovalIntegrityCheck
            if ($script:LastRunSummary.IntegrityLogPath -ne 'fixture-integrity.json' -or $null -eq $script:LastRunSummary.Integrity -or $script:LastRunLogPath -ne 'fixture-removal.json') {
                throw 'The optional diagnostic log did not preserve the existing removal result.'
            }
        }
    }

    It 'does not prompt for extra checks after failed cancelled or preview operations' {
        & $script:completionModule {
            $script:LastRunSummary = [PSCustomObject]@{ Integrity = $null }
            foreach ($status in @('Failed', 'Cancelled', 'DryRun', 'Started')) {
                $script:LastOperationResult = [PSCustomObject]@{ Status = $status }
                Invoke-PostRemovalIntegrityCheck
            }
            if ($script:Events.Contains('OptionalQuestion')) { throw 'An incomplete operation triggered the post-removal check.' }
        }
    }

    It 'explains registered Panda and on-demand services without duplicate Defender failures' {
        & $script:completionModule {
            $result = Test-SystemIntegrity
            if ($result.Warnings.Count -ne 0 -or $result.Checks.Count -ne 5) { throw 'Normal demand-start services or Defender standby produced false warnings.' }
            if ($result.AntivirusAssessment.MessageKey -ne 'SecurityOtherRegistered' -or $result.AntivirusAssessment.ProtectionConfirmed) {
                throw 'Antivirus registration was mistaken for confirmed active protection.'
            }
            $av = @($result.Checks | Where-Object Type -eq 'AntivirusStatus')
            if ($av.Count -ne 1 -or $av[0].Message -notmatch 'Panda Dome') { throw 'Expected a single contextual antivirus explanation.' }
            if (@($result.Checks | Where-Object Type -eq 'Service' | Where-Object Message -notmatch '^ServiceOnDemand').Count -gt 0) {
                throw 'On-demand services did not receive their explanation.'
            }
        }
    }

    It 'reports an unconfirmed protection state once when both status interfaces fail' {
        & $script:completionModule {
            $script:DefenderAvailable = $false
            $script:SecurityCenterAvailable = $false
            $result = Test-SystemIntegrity
            if ($result.Warnings.Count -ne 1 -or $result.AntivirusAssessment.MessageKey -ne 'SecurityProtectionUnknown' -or $result.ProviderErrors.Count -ne 2) {
                throw 'Unavailable status interfaces caused duplicate or misleading antivirus warnings.'
            }
        }
    }

    It 'warns specifically when protection cannot be confirmed and no other provider is registered' {
        & $script:completionModule {
            $script:Products = @([PSCustomObject]@{ displayName = 'Windows Defender'; productState = 0 })
            $result = Test-SystemIntegrity
            if ($result.Warnings.Count -ne 1 -or $result.AntivirusAssessment.MessageKey -ne 'SecurityNoActiveConfirmed') {
                throw 'Unconfirmed protection without a third-party provider was not distinguished.'
            }
        }
    }

    It 'recognizes reported active Defender without claiming third-party verification' {
        & $script:completionModule {
            $script:DefenderStatus = [PSCustomObject]@{ AntivirusEnabled = $true; RealTimeProtectionEnabled = $true }
            $result = Test-SystemIntegrity
            if ($result.AntivirusAssessment.MessageKey -ne 'SecurityDefenderActive' -or -not $result.AntivirusAssessment.DefenderActive -or $result.Warnings.Count -ne 0) {
                throw 'Reported active Defender was not recognized.'
            }
        }
    }

    It 'reports disabled services as configuration notices rather than uninstall damage' {
        & $script:completionModule {
            $script:ServiceStart = 'Disabled'
            $result = Test-SystemIntegrity
            if ($result.Warnings.Count -ne 4 -or @($result.Warnings | Where-Object { $_ -notmatch '^ServiceDisabled' }).Count -gt 0) {
                throw 'Disabled services were not reported with their specific configuration explanation.'
            }
        }
    }
}
