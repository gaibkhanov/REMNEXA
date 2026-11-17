Describe 'REMNEXA global exit at interactive prompts' {
    BeforeEach {
        $script:exitFixture = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ExitTest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:exitFixture | Out-Null
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $tokens = $null
        $errors = $null
        $script:applicationAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'REMNEXA.ps1'), [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw 'The application did not parse.' }
        $definitions = foreach ($name in @('Read-RemnexaInput', 'Stop-RemnexaApplication', 'Save-ToolLog', 'Normalize-Text', 'Read-ExplicitConfirmation', 'Confirm-AdministratorRequest', 'Show-AdvancedToolsMenu', 'Get-AVUpdateStatusText','Show-AVUpdateSummary','Invoke-AVConfirmedUpdate','Invoke-AVUpdateMenu','Invoke-AVScanWithUpdatePrompt','Invoke-AntivirusMenu')) {
            $node = $script:applicationAst.Find({ param($candidate) $candidate -is [Management.Automation.Language.FunctionDefinitionAst] -and $candidate.Name -eq $name }, $true)
            if ($null -eq $node) { throw "Missing application function: $name" }
            $node.Extent.Text
        }
        $driver = @'
param([string]$Scenario)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:LogRoot = Join-Path $PSScriptRoot 'Logs'
$script:CleanerVersion = '2.2.0'
$script:LastRunLogPath = 'previous-operation.json'
$script:LastRunSummary = [PSCustomObject]@{ Found = 4; Removed = 0 }
$script:LastOperationResult = $null
$script:LogLines = New-Object 'System.Collections.Generic.List[string]'
$script:LogLines.Add('Existing operation detail')
$script:Inputs = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($value in @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Input.json') -Raw | ConvertFrom-Json)) { $script:Inputs.Enqueue([string]$value) }
function T {
    param($Key, [object[]]$Values = @())
    $text = switch ($Key) {
        'ExitApplication' { 'Exit the application' }
        'ProgramEnded' { 'APPLICATION_CLOSED' }
        'LogLabel' { 'Log: {0}' }
        'LogSaveError' { 'Log could not be saved: {0}' }
        default { $Key }
    }
    if ($Values.Count -gt 0) { return ($text -f $Values) }
    return $text
}
function Read-Host {
    param($Prompt)
    if ($script:Inputs.Count -eq 0) { throw 'Unexpected extra prompt.' }
    return $script:Inputs.Dequeue()
}
function Clear-RemnexaScreen { }
function Show-BrandHeader { }
function Complete-OperationProgress { }
function Write-Status { param($Message, $Level) $script:LogLines.Add($Message); Write-Host $Message }
function Request-ElevationForTool { param($Mode) return $true }
function Initialize-AntivirusModule { return $true }
function Get-ClamAVUpdateState { [PSCustomObject]@{status='not_installed';isChecking=$false;isStale=$true} }
function Get-ClamAVStatus { [PSCustomObject]@{ Installed = $true; Ready = $true; Version = 'fixture'; SignatureDate = ''; SignatureAgeDays = 0; Signatures = 0; SignaturesOutdated = $false; ClamScanPath = ''; FreshClamPath = ''; DatabasePath = '' } }
function Invoke-ClamAVScan { throw 'A scan must not run in this exit test.' }
function Get-ClamAVQuarantine { [PSCustomObject]@{ Signature = 'fixture'; QuarantinedAt = ''; OriginalPath = 'fixture'; QuarantineId = 'fixture' } }
function ConvertFrom-RemnexaMenuChoice { param($InputText, $Maximum) $number = 0; if ([int]::TryParse($InputText, [ref]$number) -and $number -ge 0 -and $number -le $Maximum) { return $number }; return $null }
function Restore-FromClamAVQuarantine {
    param($Identifier, [switch]$Force, [bool]$Confirm)
    [PSCustomObject]@{ Identifier = $Identifier; Force = [bool]$Force; Confirm = $Confirm } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Restore.json')
}
'@
        $driver += [Environment]::NewLine + ($definitions -join [Environment]::NewLine)
        $driver += @'

switch ($Scenario) {
    'Submenu' { Show-AdvancedToolsMenu }
    'AdminNotice' { Confirm-AdministratorRequest -ReasonKey 'AdminReasonAntivirus' }
    'Confirmation' {
        try { Read-ExplicitConfirmation -WarningText 'Preview only' -ActionText 'Do not run' }
        catch { Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Caught.txt') -Value 'Unexpected caught exit' }
        finally { Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Finally.txt') -Value 'Cleanup ran' }
    }
    'Antivirus' { Invoke-AntivirusMenu }
    'NormalInput' { $answer = Read-RemnexaInput -Prompt 'Path'; Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Answer.txt') -Value $answer -NoNewline }
    'ExistingZeroExit' { $answer = Read-RemnexaInput -Prompt 'Choice' -ExitOptionAlreadyShown; Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Answer.txt') -Value $answer -NoNewline }
    'LogFailure' { function Save-ToolLog { throw 'simulated disk failure' }; Read-RemnexaInput -Prompt 'Choice' }
}
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'Continued.txt') -Value 'The application continued after the prompt.'
'@
        [IO.File]::WriteAllText((Join-Path $script:exitFixture 'Driver.ps1'), $driver, (New-Object Text.UTF8Encoding($false)))
    }

    AfterEach {
        $fixture = [IO.Path]::GetFullPath($script:exitFixture)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $fixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $fixture) -notlike 'REMNEXA-ExitTest-*') {
            throw 'Refusing cleanup outside the isolated test directory.'
        }
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }

    It 'routes every raw console input through the global exit wrapper' {
        $raw = @($script:applicationAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Read-Host' }, $true))
        if ($raw.Count -ne 1) { throw "Expected exactly one raw input site, found $($raw.Count)." }
        $owner = $raw[0].Parent
        while ($null -ne $owner -and $owner -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
        if ($null -eq $owner -or $owner.Name -ne 'Read-RemnexaInput') { throw 'A prompt bypasses the global exit wrapper.' }
    }

    It 'exits a submenu immediately and preserves the session log' {
        @('x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Submenu 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Submenu exit failed: $output" }
        $logs = @(Get-ChildItem -LiteralPath (Join-Path $script:exitFixture 'Logs') -File)
        if ($logs.Count -ne 1) { throw 'Expected one session exit log.' }
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw | ConvertFrom-Json
        if ($log.Data.Reason -ne 'UserRequested' -or $log.Data.LastRunSummary.Found -ne 4 -or $log.Data.Entries -notcontains 'Existing operation detail') { throw 'Session details were lost at exit.' }
        if (($output -join ' ') -notmatch '\[X\] Exit the application') { throw 'The exit option was not visible.' }
    }

    It 'keeps x as a quiet working alias when a menu already advertises zero to exit' {
        @('x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario ExistingZeroExit 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Quiet exit alias failed: $output" }
        if (($output -join ' ') -match '\[X\]') { throw 'The redundant exit option was still advertised.' }
        if (@(Get-ChildItem -LiteralPath (Join-Path $script:exitFixture 'Logs') -File).Count -ne 1) { throw 'The quiet exit lost the session log.' }
    }

    It 'leaves zero unchanged for the owning menu without printing a duplicate exit option' {
        @('0') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario ExistingZeroExit 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "The input wrapper changed the existing zero handling: $output" }
        if ((Get-Content -LiteralPath (Join-Path $script:exitFixture 'Answer.txt') -Raw) -ne '0' -or ($output -join ' ') -match '\[X\]') {
            throw 'Zero was modified or the redundant X option was shown.'
        }
    }

    It 'exits a confirmation without being swallowed by a surrounding catch and runs cleanup' {
        @(' X ') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Confirmation 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Confirmation exit failed: $output" }
        foreach ($name in @('Continued.txt', 'Caught.txt')) { if (Test-Path -LiteralPath (Join-Path $script:exitFixture $name)) { throw "Exit did not stop the confirmation: $name" } }
        if (-not (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Finally.txt'))) { throw 'The exit skipped the enclosing cleanup block.' }
    }

    It 'exits the antivirus result menu without returning to the main menu' {
        @('1', 'exit') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Antivirus 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Antivirus result exit failed: $output" }
    }

    It 'exits an antivirus path prompt before a scan can start' {
        @('6', 'x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Antivirus 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Antivirus path exit failed: $output" }
    }

    It 'exits a quarantine selection before a restore can start' {
        @('7', 'x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Antivirus 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Quarantine exit failed: $output" }
        if (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Restore.json')) { throw 'A quarantine file was restored without confirmation.' }
    }

    It 'allows exiting the quarantine warning without approving a restore' {
        @('7', '1', 'x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Antivirus 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Quarantine warning exit failed: $output" }
        if (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Restore.json')) { throw 'The restore ran after choosing exit.' }
    }

    It 'invokes quarantine restore only after explicit approval in the application warning' {
        @('7', '1', '1', 'x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario Antivirus 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Approved restore flow failed: $output" }
        $restore = Get-Content -LiteralPath (Join-Path $script:exitFixture 'Restore.json') -Raw | ConvertFrom-Json
        if ($restore.Identifier -ne 'fixture' -or -not $restore.Force -or $restore.Confirm) { throw 'The explicitly confirmed restore was not passed to the module correctly.' }
    }

    It 'preserves normal input exactly instead of treating a path containing x as exit' {
        @('C:\Example\x.txt') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario NormalInput 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Normal input failed: $output" }
        if ((Get-Content -LiteralPath (Join-Path $script:exitFixture 'Answer.txt') -Raw) -ne 'C:\Example\x.txt') { throw 'Normal input was modified.' }
        if (-not (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw 'A normal path closed the application.' }
    }

    It 'still closes and reports the problem when saving the exit log fails' {
        @('x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario LogFailure 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Log failure blocked exit: $output" }
        if (($output -join ' ') -notmatch 'Log could not be saved') { throw 'The failed log save was hidden.' }
    }

    It 'allows a direct application exit from the administrator explanation' {
        @('x') | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $script:exitFixture 'Input.json')
        $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File (Join-Path $script:exitFixture 'Driver.ps1') -Scenario AdminNotice 2>&1
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $script:exitFixture 'Continued.txt'))) { throw "Exiting from the administrator explanation failed: $output" }
    }
}
