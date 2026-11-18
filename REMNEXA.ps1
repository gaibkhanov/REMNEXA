#requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name,

    [switch]$DryRun,
    [switch]$IncludeUserFiles,
    [switch]$ResidualOnly,
    [switch]$NoRestorePoint,
    [switch]$NoElevation,
    [switch]$OverrideProtectedComponent,
    [switch]$RemoveProvisionedAppx,
    [switch]$TestIntegrity,
    [switch]$SelfTest,
    [switch]$ResumeRemoval,
    [switch]$ContinueInteractive,
    [ValidateSet('', 'Registry', 'Features', 'Privacy', 'Antivirus', 'Startup')]
    [string]$ToolMode = '',
    [ValidateSet('', 'Home', 'Uninstall', 'Antivirus', 'Startup', 'Services')]
    [string]$WorkspaceMode = '',
    [string]$SelectedRegistryPath,
    [string]$SelectedPackageFullName,
    [string]$SelectedStartupId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Core\PathSafety.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\PrivacyBackupValidation.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\MenuChoices.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\Localization.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\AppSettings.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\Logging.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\Permissions.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\OperationResults.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\SystemSnapshot.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\Progress.psd1') -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\NativeProcess.psd1') -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'Core\SecurityAssessment.psd1') -Force -ErrorAction Stop

$script:BrandName = 'REMNEXA'
$script:CleanerVersion = '2.2.0-rc.5'
$script:OperationProgress = $null
$script:RestartRequired = $false
$script:ExitRequested = $false
$script:LastRunLogPath = ''
$script:LastRunSummary = $null
$script:LastOperationResult = $null
$script:ReturnToProgramList = $false
$script:LogLines = New-Object System.Collections.Generic.List[string]
$global:ProgramCleanerLogLines = $script:LogLines
$global:RemnexaLogLines = $script:LogLines
$script:TraceIndex = @{}
$script:InteractiveSession = $false
$script:ProvisionedRemovedCount = 0
$script:ProtectedOverrideCategory = ''
$script:LanguageCodes = @('de', 'en', 'es', 'fr', 'ru', 'tr')
$script:Language = 'de'
$script:LegacyDataRoot = Join-Path $env:LOCALAPPDATA 'ProgramCleaner'
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'REMNEXA'
$script:SettingsPath = Join-Path $script:DataRoot 'Settings.json'
$script:HistoryPath = Join-Path $script:DataRoot 'History.jsonl'
$script:LogRoot = Join-Path $script:DataRoot 'Logs'
$script:PrivacyBackupPath = Join-Path $script:DataRoot 'PrivacyBackup.json'
$script:StartupHistoryPath = Join-Path $script:DataRoot 'StartupHistory.jsonl'
$script:StartupBackupRoot = Join-Path $script:DataRoot 'StartupBackups'
$script:AntivirusModulePath = Join-Path $PSScriptRoot 'Antivirus\Antivirus.psd1'
$script:AntivirusAvailable = $false
$script:ProtectedServices = @(
    'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc',
    'wuauserv', 'WaaSMedicSvc', 'UsoSvc', 'BITS', 'DoSvc',
    'InstallService', 'AppXSvc', 'ClipSVC'
)
$script:ProtectedComponents = @(
    [PSCustomObject]@{ Category = 'Windows Defender / Security Center'; Pattern = '(?i)(Windows|Microsoft)\s*(Defender|Security)|Security\s*Center|SecHealth|SecurityHealth|Microsoft\.SecHealthUI' },
    [PSCustomObject]@{ Category = 'Windows Update'; Pattern = '(?i)^Windows\s*Update($|\s)|Update\s*Health\s*Tools|WaaSMedic|UsoSvc|\bwuauserv\b' },
    [PSCustomObject]@{ Category = 'Microsoft Store infrastructure'; Pattern = '(?i)^Microsoft\s*Store$|Windows\s*Store|Microsoft\.WindowsStore|StorePurchaseApp|DesktopAppInstaller|App\s*Installer|\bAppXSvc\b|\bClipSVC\b' },
    [PSCustomObject]@{ Category = '.NET Framework / Runtime'; Pattern = '(?i)Microsoft\s*\.NET|\.NET\s*(Framework|Runtime|Desktop Runtime|Host)|ASP\.NET\s*Core|\bNetFx\d' },
    [PSCustomObject]@{ Category = 'Microsoft Visual C++ Redistributable'; Pattern = '(?i)Microsoft\s*Visual\s*C\+\+.*(Redistributable|Runtime)|VC\+\+.*Runtime' }
)

# Reihenfolge der Sprachcodes: Deutsch, Englisch, Spanisch, Französisch, Russisch, Türkisch.
$script:Texts = Import-RemnexaLocalization -Root (Join-Path $PSScriptRoot 'locales') -LanguageCodes $script:LanguageCodes -FallbackLanguage 'de'

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowEmptyCollection()][object[]]$Values = @()
    )

    $text = Get-RemnexaText -Texts $script:Texts -Key $Key -LanguageCode $script:Language -LanguageCodes $script:LanguageCodes -FallbackLanguage 'de'
    if ($Values.Count -gt 0) { return ($text -f $Values) }
    return $text
}

function Clear-RemnexaScreen {
    # Console cursor APIs are unavailable for redirected output and some hosts.
    # Clearing is cosmetic and must never prevent navigation or application exit.
    if ([Console]::IsOutputRedirected) { return }
    try { Clear-Host -ErrorAction Stop }
    catch { Write-Verbose ('Console clearing unavailable: ' + $_.Exception.Message) }
}

function Show-BrandHeader {
    param([AllowEmptyString()][string]$Section = '')

    try { $Host.UI.RawUI.WindowTitle = "$($script:BrandName) $($script:CleanerVersion)" } catch { }
    Write-Host '  .  :   ________' -ForegroundColor DarkCyan
    Write-Host ' .   :  /        \___' -ForegroundColor Cyan
    Write-Host '       \___   ____/  \____o' -ForegroundColor Cyan
    Write-Host '           \_/' -ForegroundColor DarkCyan
    Write-Host ('  {0}  {1}' -f $script:BrandName, $script:CleanerVersion) -ForegroundColor White
    Write-Host ('  ' + (T 'BrandTagline')) -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($Section)) {
        Write-Host ''
        Write-Host ('  ' + $Section) -ForegroundColor White
    }
    Write-Host ''
}

function Initialize-DataMigration {
    if ((Test-Path -LiteralPath $script:DataRoot) -or -not (Test-Path -LiteralPath $script:LegacyDataRoot)) { return }

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        foreach ($name in @('Settings.json', 'History.jsonl', 'PrivacyBackup.json')) {
            $source = Join-Path $script:LegacyDataRoot $name
            $destination = Join-Path $script:DataRoot $name
            if ((Test-Path -LiteralPath $source) -and -not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
        $legacyLogs = Join-Path $script:LegacyDataRoot 'Logs'
        if (Test-Path -LiteralPath $legacyLogs) {
            New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
            Copy-Item -Path (Join-Path $legacyLogs '*') -Destination $script:LogRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Alte Daten bleiben unangetastet; ein Migrationsfehler darf den Start nicht blockieren.
    }
}

function Initialize-AppSettings {
    Initialize-DataMigration
    $script:Language = Get-RemnexaLanguage -Path $script:SettingsPath -SupportedLanguages $script:LanguageCodes -FallbackLanguage 'de'
    Set-RemnexaProgressLanguage -LanguageCode $script:Language
    Import-HistoryFromExistingLogs
}

function Read-RemnexaInput {
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Prompt = '',
        [switch]$ExitOptionAlreadyShown
    )

    # The caller still handles its existing zero choice. Keep x/exit as quiet
    # compatibility aliases, but advertise just one exit option per prompt.
    if (-not $ExitOptionAlreadyShown) { Write-Host ('  [X] ' + (T 'ExitApplication')) -ForegroundColor DarkGray }
    if (Get-Command Suspend-RemnexaProgress -ErrorAction SilentlyContinue) { Suspend-RemnexaProgress }
    $answer = Read-Host -Prompt $Prompt
    if (Get-Command Resume-RemnexaProgress -ErrorAction SilentlyContinue) { Resume-RemnexaProgress }
    if ($null -eq $answer) { return '' }
    if ($answer.Trim() -ieq 'x' -or $answer.Trim() -ieq 'exit') {
        Stop-RemnexaApplication
    }
    return $answer
}

function Stop-RemnexaApplication {
    $script:ExitRequested = $true
    try {
        if(Get-Command Stop-ClamAVUpdateCheck -ErrorAction SilentlyContinue) { Stop-ClamAVUpdateCheck }
        if(Get-Command Stop-ClamAVScanEngine -ErrorAction SilentlyContinue) { Stop-ClamAVScanEngine }
        Complete-OperationProgress
        if (Get-Command Get-RemnexaActiveProgress -ErrorAction SilentlyContinue) {
            while ($activeProgress = Get-RemnexaActiveProgress) { Complete-RemnexaProgress $activeProgress -Outcome Cancelled }
        }
        Write-Status (T 'ProgramEnded') 'Success'
        if ($script:LogLines.Count -gt 0) {
            $exitLogPath = Save-ToolLog -Action ('SessionExit-' + [Guid]::NewGuid().ToString('N')) -Data ([PSCustomObject]@{
                Reason = 'UserRequested'
                LastRunLogPath = $script:LastRunLogPath
                LastRunSummary = $script:LastRunSummary
                LastOperationResult = $script:LastOperationResult
                Entries = $script:LogLines.ToArray()
            })
            if ($exitLogPath) { Write-Host (T 'LogLabel' @($exitLogPath)) -ForegroundColor DarkGray }
        }
    }
    catch {
        Write-Host (T 'LogSaveError' @($_.Exception.Message)) -ForegroundColor Yellow
    }
    finally {
        exit 0
    }
}

function Save-AppSettings {
    Save-RemnexaLanguage -Path $script:SettingsPath -Language $script:Language -SupportedLanguages $script:LanguageCodes
    Set-RemnexaProgressLanguage -LanguageCode $script:Language
}

function Get-LanguageDisplayName {
    param([Parameter(Mandatory = $true)][string]$Code)
    $names = @{ de = 'Deutsch'; en = 'English'; es = 'Español'; fr = 'Français'; ru = 'Русский'; tr = 'Türkçe' }
    return [string]$names[$Code]
}

function global:Write-LogEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info',
        [string]$Component = 'REMNEXA'
    )

    Write-RemnexaLogEntry -LogLines $script:LogLines -Message $Message -Level $Level -Component $Component
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info'
    )

    if ($Level -in @('Warning','Error')) { Add-RemnexaProgressNotice -Level $Level }
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }

    Write-Host $Message -ForegroundColor $color
    Write-LogEntry -Message $Message -Level $Level
}

function Initialize-AntivirusModule {
    if ($script:AntivirusAvailable) { return $true }
    try {
        if (-not (Test-Path -LiteralPath $script:AntivirusModulePath -PathType Leaf)) {
            throw "Modulmanifest nicht gefunden unter '$script:AntivirusModulePath'."
        }
        Import-Module -Name $script:AntivirusModulePath -Force -ErrorAction Stop
        $script:AntivirusAvailable = $true
        Write-LogEntry -Message 'Antivirus-Modul wurde geladen.' -Component 'Antivirus/Integration'
        return $true
    }
    catch {
        Write-Status (T 'AVNotAvailable' @($_.Exception.Message)) 'Warning'
        return $false
    }
}

function Get-AntivirusTracePaths {
    param(
        [AllowNull()][object]$Identity,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces
    )

    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Identity) {
        foreach ($installPath in @($Identity.InstallPaths)) {
            if ($installPath -and (Test-Path -LiteralPath $installPath)) { $paths.Add([string]$installPath) }
        }
    }
    foreach ($trace in @($Traces | Where-Object { $_.Kind -in @('File', 'Directory') })) {
        if ($trace.Target -and (Test-Path -LiteralPath ([string]$trace.Target))) { $paths.Add([string]$trace.Target) }
    }
    return @($paths | Sort-Object -Unique)
}

function Invoke-ConfiguredAntivirusScan {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Before', 'After')][string]$Stage,
        [AllowNull()][object]$Identity,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces
    )

    if (-not (Initialize-AntivirusModule)) { return @() }
    try {
        $config = Get-AVConfig
        $enabled = if ($Stage -eq 'Before') { [bool]$config.ScanBeforeRemoval } else { [bool]$config.ScanAfterRemoval }
        if (-not $enabled) { return @() }
        $targets = @(Get-AntivirusTracePaths -Identity $Identity -Traces $Traces)
        if ($targets.Count -eq 0) {
            Write-LogEntry -Message "ClamAV-$Stage-Scan uebersprungen: keine Datei- oder Ordnerziele." -Component 'Antivirus/Integration'
            return @()
        }

        $status = Get-ClamAVStatus
        if (-not $status.Installed) {
            throw "ClamAV nicht gefunden unter '$($status.ClamScanPath)'. Bitte im Hauptmenue [9], dann [6] einrichten."
        }
        # Updates require consent; optional noninteractive scans remain offline.
        $scanResults = if($script:InteractiveSession) { @(Invoke-AVScanWithUpdatePrompt -Path $targets -Targeted) } else { @(Invoke-ClamAVTargetedScan -Path $targets) }
        if($scanResults.Count -eq 0) { return @() }
        $findings = @($scanResults | Where-Object { $_.Severity -in @('Malware', 'PotentiallyUnwanted') })
        if ($findings.Count -gt 0) {
            Write-Status (T 'AVFindings' @($findings.Count)) 'Warning'
        }
        else {
            Write-Status (T 'AVClean') 'Success'
        }
        return $scanResults
    }
    catch {
        Write-Status (T 'AVOptionalFailed' @($_.Exception.Message)) 'Warning'
        Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Antivirus/Integration'
        return @()
    }
}

function Test-IsAdministrator {
    return Test-RemnexaAdministrator
}

function ConvertTo-SingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Set-OperationProgress {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 100)][int]$Percent,
        [Parameter(Mandatory = $true)][string]$Status
    )

    # Legacy milestone values select phases; they are not measured percentages.
    if (-not $script:OperationProgress -or $script:OperationProgress.Outcome -ne 'Running') {
        $script:OperationProgress = New-RemnexaProgress -Activity $script:BrandName
    }
    Update-RemnexaProgress $script:OperationProgress -Status $Status -CurrentItem '' -Force
    if ($Percent -eq 100) { Complete-RemnexaProgress $script:OperationProgress }
}

function Complete-OperationProgress {
    if ($script:OperationProgress -and $script:OperationProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $script:OperationProgress -Outcome Cancelled }
}

function Confirm-AdministratorRequest {
    param([Parameter(Mandatory = $true)][string]$ReasonKey)

    Write-Status (T $ReasonKey) 'Info'
    Write-Host (T 'AdminNoticeInstructions') -ForegroundColor Yellow
    while ($true) {
        $answer = Read-RemnexaInput (T 'AdminNoticePrompt')
        if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
        if ($answer.Trim() -eq '0') {
            Write-Status (T 'SelectionCancelled') 'Info'
            return $false
        }
        Write-Status (T 'AdminNoticeInvalid') 'Warning'
    }
}

function Request-ElevationForRemoval {
    param(
        [Parameter(Mandatory = $true)][string]$SearchName,
        [AllowNull()][object]$Program,
        [bool]$IsResidualOnly,
        [bool]$ContinueSession,
        [bool]$ProtectedOverride,
        [bool]$ProvisionedAppx
    )

    if (Test-IsAdministrator) { return $true }
    if ($NoElevation) {
        Write-Status (T 'AdminRequired') 'Warning'
        return $false
    }

    $reasonKey = if ($IsResidualOnly) { 'AdminReasonResidual' } else { 'AdminReasonRemoval' }
    if (-not (Confirm-AdministratorRequest -ReasonKey $reasonKey)) { return $false }
    Write-Status (T 'UacOpening') 'Warning'

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-SingleQuotedLiteral -Value $PSCommandPath))
    $parts.Add('-Name ' + (ConvertTo-SingleQuotedLiteral -Value $SearchName))
    $parts.Add('-ResumeRemoval')
    $parts.Add('-WorkspaceMode Uninstall')
    if ($IncludeUserFiles) { $parts.Add('-IncludeUserFiles') }
    if ($IsResidualOnly) { $parts.Add('-ResidualOnly') }
    if ($NoRestorePoint) { $parts.Add('-NoRestorePoint') }
    if ($ProtectedOverride) { $parts.Add('-OverrideProtectedComponent') }
    if ($ProvisionedAppx) { $parts.Add('-RemoveProvisionedAppx') }
    if ($TestIntegrity) { $parts.Add('-TestIntegrity') }
    if ($ContinueSession) { $parts.Add('-ContinueInteractive') }
    if ($null -ne $Program -and $Program.RegistryPath) {
        $parts.Add('-SelectedRegistryPath ' + (ConvertTo-SingleQuotedLiteral -Value ([string]$Program.RegistryPath)))
    }
    if ($null -ne $Program -and $Program.PackageFullName) {
        $parts.Add('-SelectedPackageFullName ' + (ConvertTo-SingleQuotedLiteral -Value ([string]$Program.PackageFullName)))
    }

    $command = $parts -join ' '
    $bytes = [Text.Encoding]::Unicode.GetBytes($command)
    $encoded = [Convert]::ToBase64String($bytes)

    try {
        $currentPowerShell = (Get-Process -Id $PID).Path
        Start-Process -FilePath $currentPowerShell -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -WorkingDirectory $PSScriptRoot | Out-Null
        exit 0
    }
    catch {
        Write-Status (T 'UacCancelled') 'Warning'
        return $false
    }
}

function Request-ElevationForTool {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Registry', 'Features', 'Privacy', 'Antivirus', 'Startup')][string]$Mode,
        [AllowEmptyString()][string]$ItemId = ''
    )

    if (Test-IsAdministrator) { return $true }
    if ($NoElevation) {
        Write-Status (T 'AdminRequired') 'Warning'
        return $false
    }

    $reasonKey = switch ($Mode) {
        'Registry' { 'AdminReasonRegistry' }
        'Features' { 'AdminReasonFeatures' }
        'Privacy' { 'AdminReasonPrivacy' }
        'Antivirus' { 'AdminReasonAntivirus' }
        'Startup' {
            if ($ItemId.StartsWith('restore:', [StringComparison]::OrdinalIgnoreCase)) { 'AdminReasonStartupRestore' }
            else { 'AdminReasonStartupDisable' }
        }
    }
    if (-not (Confirm-AdministratorRequest -ReasonKey $reasonKey)) { return $false }
    Write-Status (T 'UacOpening') 'Warning'
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-SingleQuotedLiteral -Value $PSCommandPath))
    $parts.Add('-ToolMode ' + (ConvertTo-SingleQuotedLiteral -Value $Mode))
    $parts.Add('-ContinueInteractive')
    if ($Mode -eq 'Startup') { $parts.Add('-WorkspaceMode Startup') }
    if ($Mode -eq 'Antivirus') { $parts.Add('-WorkspaceMode Antivirus') }
    if ($Mode -eq 'Startup' -and -not [string]::IsNullOrWhiteSpace($ItemId)) {
        $parts.Add('-SelectedStartupId ' + (ConvertTo-SingleQuotedLiteral -Value $ItemId))
    }
    if ($NoRestorePoint) { $parts.Add('-NoRestorePoint') }
    if ($OverrideProtectedComponent) { $parts.Add('-OverrideProtectedComponent') }
    $command = $parts -join ' '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    try {
        $currentPowerShell = (Get-Process -Id $PID).Path
        Start-Process -FilePath $currentPowerShell -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -WorkingDirectory $PSScriptRoot | Out-Null
        exit 0
    }
    catch {
        Write-Status (T 'UacCancelled') 'Warning'
        return $false
    }
}

function Normalize-Text {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text.ToLowerInvariant()) -replace '[^\p{L}\p{Nd}]', '')
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $InputObject) { return '' }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return $property.Value
}

function Get-ProtectedComponentMatch {
    param(
        [AllowNull()][object]$Program,
        [AllowEmptyString()][string]$SearchName = ''
    )

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($SearchName)) { $parts.Add($SearchName) }
    if ($null -ne $Program) {
        foreach ($propertyName in @('DisplayName', 'PackageName', 'PackageFullName', 'Publisher', 'ProductCode')) {
            $value = [string](Get-OptionalPropertyValue -InputObject $Program -PropertyName $propertyName)
            if (-not [string]::IsNullOrWhiteSpace($value)) { $parts.Add($value) }
        }
    }
    $combined = $parts -join ' | '
    foreach ($rule in $script:ProtectedComponents) {
        if ($combined -match $rule.Pattern) { return $rule }
    }
    return $null
}

function Confirm-ProtectedComponentOverride {
    param(
        [AllowNull()][object]$Program,
        [Parameter(Mandatory = $true)][string]$SearchName
    )

    $match = Get-ProtectedComponentMatch -Program $Program -SearchName $SearchName
    if ($null -eq $match) { return $true }

    Write-Host ''
    Write-Host (T 'ProtectedTitle') -ForegroundColor Red
    Write-Host (T 'ProtectedReason' @([string]$match.Category)) -ForegroundColor Red
    if ($OverrideProtectedComponent) {
        $script:ProtectedOverrideCategory = [string]$match.Category
        Write-Status (T 'ProtectedOverride') 'Warning'
        return $true
    }
    if (-not $script:InteractiveSession) { return $false }

    Write-Host ('  [1] ' + (T 'ProtectedAbort'))
    Write-Host ('  [2] ' + (T 'ProtectedOverride')) -ForegroundColor Red
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $false }
        if ($answer -eq '2') {
            $script:OverrideProtectedComponent = $true
            $script:ProtectedOverrideCategory = [string]$match.Category
            return $true
        }
        Write-Status (T 'InvalidProtected') 'Warning'
    }
}

function Test-ProtectedServiceName {
    param([Parameter(Mandatory = $true)][string]$ServiceName)
    if ($script:ProtectedServices -notcontains $ServiceName) { return $false }
    $category = if ($ServiceName -in @('WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wscsvc')) {
        'Windows Defender / Security Center'
    }
    elseif ($ServiceName -in @('wuauserv', 'WaaSMedicSvc', 'UsoSvc', 'BITS', 'DoSvc')) {
        'Windows Update'
    }
    else {
        'Microsoft Store infrastructure'
    }
    return $script:ProtectedOverrideCategory -ne $category
}

function Get-SystemDriveFreeBytes {
    try {
        $root = [IO.Path]::GetPathRoot($env:WINDIR)
        return [int64]([IO.DriveInfo]::new($root).AvailableFreeSpace)
    }
    catch { return [int64]-1 }
}

function Format-ByteSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} Bytes' -f $Bytes)
}

function Get-InstalledPrograms {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskInventory') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $items = New-Object System.Collections.Generic.List[object]
        $registryRoots = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($entry in @(Get-ItemProperty -Path $registryRoots -ErrorAction SilentlyContinue)) {
            $entryDisplayName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($entryDisplayName)) { continue }

            $uninstallString = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'UninstallString')
            $quietUninstallString = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'QuietUninstallString')
            $systemComponent = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'SystemComponent')
            $releaseType = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'ReleaseType')
            $parentKeyName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'ParentKeyName')
            $publisher = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Publisher')
            $protectionMatch = Get-ProtectedComponentMatch -Program ([PSCustomObject]@{ DisplayName = $entryDisplayName; Publisher = $publisher }) -SearchName $entryDisplayName
            $looksSystemLike = (
                $systemComponent -eq '1' -or
                -not [string]::IsNullOrWhiteSpace($parentKeyName) -or
                $releaseType -match 'Update|Hotfix|Security|Rollup' -or
                $entryDisplayName -match '^(Update für|Update for|Security Update|Sicherheitsupdate|Hotfix|KB\d+)' -or
                $entryDisplayName -match '^Microsoft Visual C\+\+' -or
                $entryDisplayName -match '^Microsoft \.NET' -or
                $entryDisplayName -match 'Windows Desktop Runtime|WebView2.*(Runtime|Laufzeit)|Software Development Kit|\bSDK\b' -or
                ($publisher -match '^Microsoft' -and $entryDisplayName -match 'Runtime|Laufzeit|Framework|Redistributable|Health Tools') -or
                $entryDisplayName -match '\b(Driver|Treiberpaket)\b'
            )

            $items.Add([PSCustomObject]@{
                Type                 = 'Registry'
                SourceLabel          = 'Desktop'
                DisplayName          = $entryDisplayName
                DisplayVersion       = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayVersion')
                Publisher            = $publisher
                InstallLocation      = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallLocation')
                InstallSource        = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallSource')
                UninstallString      = $uninstallString
                QuietUninstallString = $quietUninstallString
                RegistryPath         = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSPath')
                ProductCode          = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSChildName')
                PackageFullName      = ''
                PackageName          = ''
                IsSystemLike         = [bool]($looksSystemLike -or $null -ne $protectionMatch)
                ProtectionCategory   = $(if ($null -ne $protectionMatch) { [string]$protectionMatch.Category } else { '' })
                CanUninstall         = -not ([string]::IsNullOrWhiteSpace($uninstallString) -and [string]::IsNullOrWhiteSpace($quietUninstallString))
            })
        }

        try {
            foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
                $display = if ($package.Name) { [string]$package.Name } else { [string]$package.PackageFullName }
                $isFramework = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'IsFramework')
                $isResourcePackage = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'IsResourcePackage')
                $nonRemovable = [bool](Get-OptionalPropertyValue -InputObject $package -PropertyName 'NonRemovable')
                $protectionMatch = Get-ProtectedComponentMatch -Program $package -SearchName $display
                $items.Add([PSCustomObject]@{
                    Type                 = 'Appx'
                    SourceLabel          = 'Store'
                    DisplayName          = $display
                    DisplayVersion       = [string]$package.Version
                    Publisher            = [string]$package.Publisher
                    InstallLocation      = [string]$package.InstallLocation
                    InstallSource        = ''
                    UninstallString      = ''
                    QuietUninstallString = ''
                    RegistryPath         = ''
                    ProductCode          = ''
                    PackageFullName      = [string]$package.PackageFullName
                    PackageName          = [string]$package.Name
                    IsSystemLike         = [bool]($isFramework -or $isResourcePackage -or $nonRemovable -or $null -ne $protectionMatch)
                    ProtectionCategory   = $(if ($null -ne $protectionMatch) { [string]$protectionMatch.Category } else { '' })
                    CanUninstall         = -not $nonRemovable
                })
            }
        }
        catch {
            Write-Status (T 'StoreReadError' @($_.Exception.Message)) 'Warning'
        }

        return @($items | Sort-Object DisplayName, DisplayVersion, Type, RegistryPath -Unique)
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Find-ProgramCandidates {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Programs,
        [Parameter(Mandatory = $true)][string]$SearchName
    )

    $needle = $SearchName.Trim()
    return @($Programs | Where-Object {
        $_.DisplayName.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $_.Publisher.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Sort-Object @{
        Expression = { if ($_.DisplayName.Equals($needle, [StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 } }
    }, DisplayName, DisplayVersion)
}

function Select-Program {
    param([Parameter(Mandatory = $true)][object[]]$Candidates)

    return Select-ProgramPaged -Programs $Candidates -Title (T 'FoundProgramsTitle')
}

function Show-PageNavigation {
    param(
        [Parameter(Mandatory = $true)][object]$PageState,
        [string]$NextCommand = '-1',
        [string]$PreviousCommand = '-2'
    )
    if ($PageState.HasNext) { Write-Host ('  [{0}] {1}' -f $NextCommand, (T 'PageNext')) -ForegroundColor DarkGray }
    if ($PageState.HasPrevious) { Write-Host ('  [{0}] {1}' -f $PreviousCommand, (T 'PagePrevious')) -ForegroundColor DarkGray }
}

function Select-ProgramPaged {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Programs,
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowNull()][object]$ResumeContext = $null
    )

    if ($Programs.Count -eq 0) {
        Write-Status (T 'NoApps') 'Warning'
        return $null
    }

    $allPrograms = @($Programs | Sort-Object DisplayName, DisplayVersion, SourceLabel)
    $filteredPrograms = $allPrograms
    $filterText = ''
    $page = 0
    $pageNotice = ''
    if ($null -ne $ResumeContext) { $filterText = [string]$ResumeContext.Filter; $page = [int]$ResumeContext.Page }
    $filteredPrograms = if ($filterText) { @($allPrograms | Where-Object { $_.DisplayName.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $_.Publisher.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) } else { $allPrograms }
    $pageSize = 18

    while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader
        Write-Host $Title -ForegroundColor White
        if ($filterText) { Write-Host (T 'FilterLabel' @($filterText)) -ForegroundColor Yellow }

        $pageState = Get-RemnexaPageState -ItemCount $filteredPrograms.Count -PageSize $pageSize -PageIndex $page
        $pageCount = $pageState.PageCount
        $page = $pageState.PageIndex
        $script:LastProgramListContext = [PSCustomObject]@{ Programs = $allPrograms; Title = $Title; Filter = $filterText; Page = $page }
        $start = $page * $pageSize
        $end = [Math]::Min($start + $pageSize - 1, $filteredPrograms.Count - 1)

        Write-Host (T 'PageLabel' @(($page + 1), $pageCount, $filteredPrograms.Count)) -ForegroundColor DarkGray
        Write-Host ''
        if ($filteredPrograms.Count -eq 0) {
            Write-Host (T 'NoFilterHits') -ForegroundColor Yellow
        }
        else {
            for ($i = $start; $i -le $end; $i++) {
                $item = $filteredPrograms[$i]
                $version = if ($item.DisplayVersion) { ' | ' + $item.DisplayVersion } else { '' }
                $protectionCategory = [string](Get-OptionalPropertyValue -InputObject $item -PropertyName 'ProtectionCategory')
                $protected = if (-not $item.CanUninstall -or -not [string]::IsNullOrWhiteSpace($protectionCategory)) { ' | ' + (T 'ProtectedLabel') } else { '' }
                Write-Host ('  [{0}] {1}{2} | {3}{4}' -f ($i + 1), $item.DisplayName, $version, $item.SourceLabel, $protected)
            }
        }

        Write-Host ''
        Write-Host (T 'ListCommands') -ForegroundColor DarkGray
        Show-PageNavigation -PageState $pageState
        if ($pageNotice) { Write-Status (T $pageNotice) 'Warning'; $pageNotice = '' }
        $answer = Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Status (T 'InvalidList') 'Warning'
            Start-Sleep -Milliseconds 900
            continue
        }

        $trimmedAnswer = $answer.Trim()
        if ($trimmedAnswer -in @('0', 'exit')) {
            $script:ExitRequested = $true
            return $null
        }
        if ($trimmedAnswer -in @('-5', 'b', 'back', 'menu')) { return $null }
        if ($trimmedAnswer -in @('-1', 'n')) {
            if ($pageState.HasNext) { $page++ }
            else { $pageNotice = 'PageNextUnavailable' }
            continue
        }
        if ($trimmedAnswer -in @('-2', 'z')) {
            if ($pageState.HasPrevious) { $page-- }
            else { $pageNotice = 'PagePreviousUnavailable' }
            continue
        }
        if ($trimmedAnswer -in @('-3', 's')) {
            $filterText = (Read-RemnexaInput (T 'SearchPrompt')).Trim()
            if ($filterText) {
                $filteredPrograms = @($allPrograms | Where-Object {
                    $_.DisplayName.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $_.Publisher.IndexOf($filterText, [StringComparison]::OrdinalIgnoreCase) -ge 0
                })
            }
            else {
                $filteredPrograms = $allPrograms
            }
            $page = 0
            continue
        }
        if ($trimmedAnswer -in @('-4', 'a')) {
            $filterText = ''
            $filteredPrograms = $allPrograms
            $page = 0
            continue
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $filteredPrograms.Count) {
            $selectedProgram = $filteredPrograms[$number - 1]
            if (-not $selectedProgram.CanUninstall) {
                Write-Status (T 'ProtectedItem') 'Warning'
                Write-Host (T 'Press1Back') -ForegroundColor DarkGray
                while ($true) {
                    $protectedChoice = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
                    if ($protectedChoice -eq '1') { break }
                    if ($protectedChoice -in @('0', 'exit')) {
                        $script:ExitRequested = $true
                        return $null
                    }
                    Write-Status (T 'Press1Back') 'Warning'
                }
                continue
            }
            $script:LastProgramListContext.Filter = $filterText
            $script:LastProgramListContext.Page = $page
            return $selectedProgram
        }

        Write-Status (T 'InvalidList') 'Warning'
        Start-Sleep -Milliseconds 900
    }
}

function Show-UninstallMenu {
    Write-Host (T 'UninstallTitle') -ForegroundColor White
    Write-Host ''
    Write-Host (T 'MainQuestion') -ForegroundColor White
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Main1'))
    Write-Host ('  [2] ' + (T 'Main2'))
    Write-Host ('  [3] ' + (T 'Main3'))
    Write-Host ('  [4] ' + (T 'Main4'))
    Write-Host ('  [5] ' + (T 'Main5'))
    Write-Host ('  [6] ' + (T 'Main6'))
    Write-Host ('  [7] ' + (T 'Main7'))
    Write-Host ('  [8] ' + (T 'Main8'))
    Write-Host ('  [9] ' + (T 'Main9'))
    Write-Host ('  [0] ' + (T 'BackHome'))
    Write-Host ''

    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -match '^[0-9]$') { return $answer }
        if ($answer -ieq 'exit') { return '0' }
        Write-Status (T 'InvalidMain') 'Warning'
    }
}

function Show-HomeMenu {
    Write-Host (T 'HomeTitle') -ForegroundColor White
    Write-Host (T 'HomeDescription') -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Home1'))
    Write-Host ('  [2] ' + (T 'Home2'))
    Write-Host ('  [3] ' + (T 'Home3'))
    Write-Host ('  [4] ' + (T 'Home4'))
    Write-Host ('  [5] ' + (T 'Home5'))
    Write-Host ('  [6] ' + (T 'Home6'))
    Write-Host ('  [7] ' + (T 'Home7'))
    Write-Host ('  [8] ' + (T 'Home8'))
    Write-Host ('  [9] ' + (T 'Home9'))
    Write-Host ('  [0] ' + (T 'Main0'))
    Write-Host ''
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -match '^[0-9]$') { return $answer }
        if ($answer -ieq 'exit') { return '0' }
        Write-Status (T 'HomeInvalid') 'Warning'
    }
}

function Show-SystemSnapshotScreen {
    Write-Host (T 'SystemSnapshotTitle') -ForegroundColor White
    Write-Host (T 'SystemSnapshotReadOnly') -ForegroundColor DarkGray
    Write-Host ''

    try {
        $snapshot = Get-RemnexaSystemSnapshot
        Write-Host (T 'SystemSnapshotOS' @($snapshot.WindowsCaption, $snapshot.WindowsVersion))
        if (-not [string]::IsNullOrWhiteSpace([string]$snapshot.BuildNumber)) {
            Write-Host (T 'SystemSnapshotBuild' @($snapshot.BuildNumber, $snapshot.Architecture))
        }

        $cpuText = if ($null -eq $snapshot.CpuLoadPercent) { T 'SystemSnapshotUnavailableValue' } else { '{0}%' -f $snapshot.CpuLoadPercent }
        Write-Host (T 'SystemSnapshotCpu' @($cpuText))

        if ($null -eq $snapshot.MemoryUsedPercent) {
            Write-Host (T 'SystemSnapshotMemoryUnavailable')
        }
        else {
            $memoryValues = @(
                $snapshot.MemoryUsedPercent,
                (Format-ByteSize -Bytes $snapshot.FreeMemoryBytes),
                (Format-ByteSize -Bytes $snapshot.TotalMemoryBytes)
            )
            Write-Host (T 'SystemSnapshotMemory' $memoryValues)
        }

        if (@($snapshot.Volumes).Count -eq 0) {
            Write-Host (T 'SystemSnapshotNoDrives') -ForegroundColor DarkGray
        }
        else {
            foreach ($volume in @($snapshot.Volumes)) {
                Write-Host (T 'SystemSnapshotDrive' @(
                    $volume.Drive,
                    $volume.UsedPercent,
                    (Format-ByteSize -Bytes $volume.FreeBytes),
                    (Format-ByteSize -Bytes $volume.TotalBytes)
                ))
            }
        }
    }
    catch {
        Write-Status (T 'SystemSnapshotError' @($_.Exception.Message)) 'Warning'
    }

    Write-Host ''
    [void](Read-RemnexaInput (T 'SystemSnapshotContinue'))
}

function Read-AfterOperationChoice {
    Write-Host ''
    Write-Host (T 'OperationDone') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'BackMain'))
    Write-Host ('  [2] ' + (T 'BackProgramList'))
    if ($script:LastRunLogPath) { Write-Host ('  [3] ' + (T 'OpenRunLog')) }
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $choice = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($choice -eq '3' -and $script:LastRunLogPath) {
            if (Test-Path -LiteralPath $script:LastRunLogPath) {
                Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LastRunLogPath + '"') -Wait
            }
            else { Write-Status ('Protokoll nicht gefunden: ' + $script:LastRunLogPath) 'Warning' }
            Show-LastRunDetails
            Write-Host (T 'OperationDone') -ForegroundColor White
            Write-Host ('  [1] ' + (T 'BackMain'))
            Write-Host ('  [2] ' + (T 'BackProgramList'))
            Write-Host ('  [3] ' + (T 'OpenRunLog'))
            Write-Host ('  [0] ' + (T 'Main0'))
            continue
        }
        if ($choice -eq '1') { return 'main' }
        if ($choice -eq '2') { return 'list' }
        if ($choice -eq '0') { return 'exit' }
        Write-Status (T $(if ($script:LastRunLogPath) { 'InvalidAfterOperation' } else { 'InvalidAfterOperationNoLog' })) 'Warning'
    }
}

function Show-LastRunDetails {
    if ($null -ne $script:LastOperationResult) {
        $statusKey = 'OperationStatus' + [string]$script:LastOperationResult.Status
        Write-Host ('  ' + (T $statusKey)) -ForegroundColor $(if ($script:LastOperationResult.Status -in @('Completed', 'DryRun')) { 'Green' } elseif ($script:LastOperationResult.Status -eq 'Partial') { 'Yellow' } else { 'Red' })
    }
    if ($null -eq $script:LastRunSummary) { return }
    $summary = $script:LastRunSummary
    Write-Host ''
    Write-Host (T 'RunDetails') -ForegroundColor White
    Write-Host ('  Spuren vor der Deinstallation: {0}' -f $summary.Before)
    Write-Host ('  Spuren danach zur Bereinigung gefunden: {0}' -f $summary.Found)
    Write-Host ('  Entfernt: {0} | fehlgeschlagen: {1} | noch vorhanden: {2}' -f $summary.Removed, $summary.Failed, $summary.Remaining)
    if ($summary.PSObject.Properties['Skipped'] -and $summary.Skipped -gt 0) {
        Write-Host ('  ' + (T 'ManagedTraceCount' @($summary.Skipped))) -ForegroundColor DarkYellow
    }
    if ($summary.Integrity) {
        if ($summary.Integrity.Warnings.Count -eq 0) { Write-Host '  Systemprüfung: keine Hinweise.' -ForegroundColor Green }
        else {
            Write-Host ('  Systemprüfung: {0} Hinweis(e)' -f $summary.Integrity.Warnings.Count) -ForegroundColor Yellow
            foreach ($warning in $summary.Integrity.Warnings) { Write-Host ('    - ' + $warning) -ForegroundColor Yellow }
        }
        foreach ($check in @($summary.Integrity.Checks | Where-Object { $_.Type -eq 'AntivirusStatus' -and $_.Healthy })) { Write-Host ('    ' + $check.Message) -ForegroundColor DarkGray }
        if ($summary.PSObject.Properties['IntegrityLogPath'] -and $summary.IntegrityLogPath) { Write-Host (T 'LogLabel' @($summary.IntegrityLogPath)) -ForegroundColor DarkGray }
    }
}

function Get-ExecutableFromCommandLine {
    param([AllowNull()][string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.exe)"') { return $matches[1] }
    if ($expanded -match '^\s*(.+?\.exe)(?:\s|$)') { return $matches[1].Trim() }
    return ''
}

function Split-CommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.exe)"\s*(.*)$') {
        return @($matches[1], $matches[2])
    }
    if ($expanded -match '^\s*(.+?\.exe)\s*(.*)$') {
        return @($matches[1].Trim(), $matches[2])
    }
    throw ('Unbekanntes Deinstallationskommando: ' + $CommandLine)
}

function Get-IdentityInfo {
    param(
        [Parameter(Mandatory = $true)][string]$SearchName,
        [AllowNull()][object]$Program
    )

    $blockedTokens = @(
        'app', 'application', 'desktop', 'program', 'software', 'windows', 'microsoft',
        'client', 'launcher', 'update', 'updater', 'setup', 'installer', 'install',
        'service', 'helper', 'tool', 'tools', 'suite', 'edition', 'version', 'official',
        'x64', 'x86', '64bit', '32bit', 'gmbh', 'llc', 'inc', 'ltd', 'corp', 'corporation'
    )

    $rawNames = New-Object System.Collections.Generic.List[string]
    $paths = New-Object System.Collections.Generic.List[string]
    $rawNames.Add($SearchName.Trim())
    $deepRegistrySource = $SearchName.Trim()

    if ($null -ne $Program) {
        if ($Program.DisplayName) {
            $rawNames.Add([string]$Program.DisplayName)
            $deepRegistrySource = [string]$Program.DisplayName
        }
        if ($Program.PackageName) { $rawNames.Add([string]$Program.PackageName) }

        $identityPaths = New-Object System.Collections.Generic.List[string]
        if ($Program.Type -ne 'Appx' -and $Program.InstallLocation) {
            $identityPaths.Add([string]$Program.InstallLocation)
        }

        foreach ($uninstallCommand in @($Program.UninstallString, $Program.QuietUninstallString)) {
            $uninstallExecutable = Get-ExecutableFromCommandLine $uninstallCommand
            if (-not [string]::IsNullOrWhiteSpace($uninstallExecutable) -and [IO.Path]::IsPathRooted($uninstallExecutable)) {
                $uninstallDirectory = [IO.Path]::GetDirectoryName($uninstallExecutable)
                $insideWindows = $uninstallDirectory.StartsWith($env:WINDIR.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
                $insidePackageCache = $uninstallDirectory.StartsWith((Join-Path $env:ProgramData 'Package Cache').TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
                if (-not $insideWindows -and -not $insidePackageCache) {
                    $identityPaths.Add($uninstallDirectory)
                }
                $rawNames.Add([IO.Path]::GetFileNameWithoutExtension($uninstallExecutable))
            }
        }

        foreach ($path in @($identityPaths)) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            try {
                $fullPath = [IO.Path]::GetFullPath($path)
                if ([IO.Path]::GetExtension($fullPath)) {
                    $rawNames.Add([IO.Path]::GetFileNameWithoutExtension($fullPath))
                    $directory = [IO.Path]::GetDirectoryName($fullPath)
                    if ($directory) { $paths.Add($directory) }
                }
                else {
                    $paths.Add($fullPath)
                    $rawNames.Add((Split-Path -Leaf $fullPath))
                }
            }
            catch { }
        }
    }

    $aliases = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($rawNames)) {
        $normalizedFull = Normalize-Text $raw
        if ($normalizedFull.Length -ge 4 -and $blockedTokens -notcontains $normalizedFull) {
            $aliases.Add($normalizedFull)
        }

        foreach ($token in @($raw -split '[^\p{L}\p{Nd}]+')) {
            $normalizedToken = Normalize-Text $token
            if ($normalizedToken.Length -ge 4 -and $blockedTokens -notcontains $normalizedToken) {
                $aliases.Add($normalizedToken)
            }
        }
    }

    $uniqueAliases = @($aliases | Sort-Object Length -Descending -Unique)
    if ($uniqueAliases.Count -eq 0) {
        throw 'Aus diesem Programmnamen lässt sich kein sicherer Suchbegriff bilden. Bitte einen genaueren Namen eingeben.'
    }

    # Für die langsame Registry-Volltextsuche wird nur ein ausreichend
    # eindeutiger Begriff verwendet. Kurze gewöhnliche Wörter wie "Java" oder
    # "Edge" wären dafür zu breit; kurze echte Akronyme wie "IBKR" sind erlaubt.
    $deepRegistryTerm = ''
    $sourceTokens = @($deepRegistrySource -split '[^\p{L}\p{Nd}]+')
    [array]::Reverse($sourceTokens)
    foreach ($token in $sourceTokens) {
        $normalizedToken = Normalize-Text $token
        if ($blockedTokens -contains $normalizedToken) { continue }
        $isAcronym = $token -cmatch '^[A-Z0-9]{3,5}$' -and $token -cmatch '[A-Z]'
        if ($normalizedToken.Length -ge 5 -or $isAcronym) {
            $deepRegistryTerm = $token
            break
        }
    }

    return [PSCustomObject]@{
        Aliases          = $uniqueAliases
        InstallPaths     = @($paths | Sort-Object -Unique)
        DeepRegistryTerm = $deepRegistryTerm
    }
}

function Test-NameMatch {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string[]]$Aliases
    )

    $normalized = Normalize-Text $Value
    if (-not $normalized) { return $false }
    foreach ($alias in $Aliases) {
        if ($normalized.Equals($alias, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($alias.Length -ge 6 -and $normalized.Contains($alias)) { return $true }

        # Bei kurzen Begriffen sind nur echte Wort-/Pfadgrenzen erlaubt. So
        # trifft "Java" auf java.exe, aber nicht auf einen gemeinsamen JavaSoft-
        # Schlüssel oder auf JavaScript-Dateien.
        if ($alias.Length -ge 4) {
            $boundaryPattern = '(?i)(?<![\p{L}\p{Nd}])' + [regex]::Escape($alias) + '(?![\p{L}\p{Nd}])'
            if ($Value -match $boundaryPattern) { return $true }
        }
    }
    return $false
}

function Add-Trace {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('File', 'Directory', 'RegistryKey', 'RegistryValue', 'Service', 'Task')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$ValueName = '',
        [string]$Reason = '',
        [bool]$Personal = $false
    )

    if ([string]::IsNullOrWhiteSpace($Target)) { return }
    if ($Kind -eq 'Service' -and (Test-ProtectedServiceName -ServiceName $Target)) {
        Write-Status (T 'ProtectedReason' @($Target)) 'Warning'
        return
    }
    $key = ($Kind + '|' + $Target + '|' + $ValueName).ToLowerInvariant()
    if ($script:TraceIndex.ContainsKey($key)) { return }

    $trace = [PSCustomObject]@{
        Kind      = $Kind
        Target    = $Target
        ValueName = $ValueName
        Reason    = $Reason
        Personal  = $Personal
    }
    $script:TraceIndex[$key] = $trace
}

function Test-ProtectedFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-RemnexaWindowsManagedPath -Path $Path) { return $true }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $true }
    $pathSafety = Get-RemnexaPathSafety -Path $full
    if (-not $pathSafety.IsSafe) { return $true }
    $protected = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(
        [IO.Path]::GetPathRoot($full),
        $env:USERPROFILE,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        $env:ProgramData,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:WINDIR,
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Downloads')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            try { $protected.Add([IO.Path]::GetFullPath($item).TrimEnd('\')) } catch { }
        }
    }

    if (@($protected | Where-Object { $_.Equals($full, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        return $true
    }

    # Unter Windows dürfen einzelne Cache-Dateien entfernt werden, niemals aber
    # ein kompletter Systemordner oder dessen Unterordner.
    try {
        $existingItem = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        $windowsRoot = [IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
        if ($existingItem -and $existingItem.PSIsContainer -and
            $full.StartsWith($windowsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    catch { }

    return $false
}

function Add-FileTraceIfSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Reason,
        [bool]$Personal = $false
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-RemnexaWindowsManagedPath -Path $Path) {
        # Keep Windows-owned packages visible as informational findings, while
        # never offering their files to the generic recursive deletion engine.
        $managedItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        $managedKind = if ($null -ne $managedItem -and -not $managedItem.PSIsContainer) { 'File' } else { 'Directory' }
        Add-Trace -Kind $managedKind -Target ([IO.Path]::GetFullPath($Path)) -Reason $Reason -Personal $false
        return
    }
    $pathSafety = Get-RemnexaPathSafety -Path $Path
    if (-not $pathSafety.IsSafe) {
        if ($pathSafety.Reason -eq 'ReparsePoint') {
            Write-Status (T 'SafetyLink' @($pathSafety.Component)) 'Warning'
        }
        else {
            Write-Status (T 'PathCheckError' @($pathSafety.Component)) 'Warning'
        }
        return
    }
    if (Test-ProtectedFilePath -Path $Path) {
        Write-Status (T 'SafetyParent' @($Path)) 'Warning'
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Status (T 'SafetyLink' @($Path)) 'Warning'
            return
        }
        Add-Trace -Kind $(if ($item.PSIsContainer) { 'Directory' } else { 'File' }) -Target $item.FullName -Reason $Reason -Personal $Personal
    }
    catch {
        Write-Status (T 'PathCheckError' @($Path)) 'Warning'
    }
}

function Find-MatchingChildren {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [int]$MaxDepth = 2,
        [bool]$Personal = $false
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskTraceSearch') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (-not (Test-Path -LiteralPath $Root)) { return }
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([PSCustomObject]@{ Path = $Root; Depth = 0 })

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            Update-RemnexaProgress $remnexaWorkProgress -Completed ($remnexaWorkProgress.Completed + 1) -CurrentItem $current.Path
            foreach ($child in @(Get-ChildItem -LiteralPath $current.Path -Force -ErrorAction SilentlyContinue)) {
                $isOwnData = $false
                foreach ($ownDataRoot in @($script:DataRoot, $script:LegacyDataRoot)) {
                    if ($child.FullName.StartsWith($ownDataRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                        $child.FullName.Equals($ownDataRoot, [StringComparison]::OrdinalIgnoreCase)) {
                        $isOwnData = $true
                        break
                    }
                }
                if ($isOwnData) {
                    continue
                }
                if (Test-NameMatch -Value $child.Name -Aliases $Aliases) {
                    Add-FileTraceIfSafe -Path $child.FullName -Reason 'Name passt zum ausgewählten Programm' -Personal $Personal
                    continue
                }
                if ($child.PSIsContainer -and $current.Depth -lt $MaxDepth -and (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) {
                    $queue.Enqueue([PSCustomObject]@{ Path = $child.FullName; Depth = $current.Depth + 1 })
                }
            }
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Test-ProtectedRegistryKey {
    param([Parameter(Mandatory = $true)][string]$RegistryPath)

    $upper = $RegistryPath.ToUpperInvariant()
    if ($upper -match '^HKEY_LOCAL_MACHINE\\(SYSTEM|HARDWARE|SAM|SECURITY)(\\|$)') { return $true }
    if ($upper -match '\\SOFTWARE\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\INSTALLER(\\|$)') { return $true }
    if ($upper -match '\\SOFTWARE\\CLASSES\\(CLSID|INTERFACE|TYPELIB)(\\|$)') { return $true }
    $protectedCategory = ''
    if ($upper -match '\\(MICROSOFT\\)?(WINDOWS DEFENDER|SECURITY CENTER)(\\|$)') {
        $protectedCategory = 'Windows Defender / Security Center'
    }
    elseif ($upper -match '\\(MICROSOFT\\)?(WINDOWSUPDATE|WINDOWS UPDATE)(\\|$)') {
        $protectedCategory = 'Windows Update'
    }
    elseif ($upper -match '\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\(WINDOWSUPDATE)(\\|$)') {
        $protectedCategory = 'Windows Update'
    }
    elseif ($upper -match '\\(WINDOWSSTORE|APPX)(\\|$)' -or $upper -match '\\MICROSOFT\\WINDOWS\\CURRENTVERSION\\(APPX|APPMODEL|STORE)(\\|$)') {
        $protectedCategory = 'Microsoft Store infrastructure'
    }
    elseif ($upper -match '\\(DOTNET|NET FRAMEWORK|\.NETFRAMEWORK)(\\|$)') {
        $protectedCategory = '.NET Framework / Runtime'
    }
    elseif ($upper -match '\\MICROSOFT\\VISUALSTUDIO\\[^\\]+\\VC\\RUNTIMES(\\|$)') {
        $protectedCategory = 'Microsoft Visual C++ Redistributable'
    }
    if ($protectedCategory -and $script:ProtectedOverrideCategory -ne $protectedCategory) { return $true }
    return $false
}

function Find-RegistryTraces {
    param(
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [AllowEmptyString()][string]$DeepRegistryTerm,
        [AllowNull()][object]$Program
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskRegistry') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if ($null -ne $Program -and $Program.RegistryPath) {
            $nativePath = $Program.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
            Add-Trace -Kind 'RegistryKey' -Target $nativePath -Reason 'Deinstallationseintrag des ausgewählten Programms'
        }

        # Maschinenweite Programmschlüssel werden bis zu zwei Ebenen tief anhand
        # ihres Namens geprüft. Das vermeidet eine sehr langsame Volltextsuche durch
        # sämtliche Windows- und Installer-Datenbanken.
        foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\Software',
            'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node',
            'Registry::HKEY_CURRENT_USER\Software'
        )) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $queue = New-Object System.Collections.Queue
            $queue.Enqueue([PSCustomObject]@{ Path = $root; Depth = 0 })
            while ($queue.Count -gt 0) {
                $current = $queue.Dequeue()
                Update-RemnexaProgress $remnexaWorkProgress -Completed ($remnexaWorkProgress.Completed + 1) -CurrentItem $current.Path
                foreach ($child in @(Get-ChildItem -LiteralPath $current.Path -ErrorAction SilentlyContinue)) {
                    $nativePath = $child.Name
                    if ((Test-NameMatch -Value $child.PSChildName -Aliases $Aliases) -and -not (Test-ProtectedRegistryKey -RegistryPath $nativePath)) {
                        Add-Trace -Kind 'RegistryKey' -Target $nativePath -Reason 'Programmspezifischer Registrierungsschlüssel'
                        continue
                    }
                    if ($current.Depth -lt 1 -and -not (Test-ProtectedRegistryKey -RegistryPath $nativePath)) {
                        $queue.Enqueue([PSCustomObject]@{ Path = $child.PSPath; Depth = $current.Depth + 1 })
                    }
                }
            }
        }

        # Eine einzige Volltextsuche im Benutzerbereich erfasst auch Verlaufseinträge
        # wie MuiCache, AppCompat, Start-Kacheln und CloudStore.
        if ([string]::IsNullOrWhiteSpace($DeepRegistryTerm)) { return }

        $term = $DeepRegistryTerm
        $progressUpdater = Get-Command Update-RemnexaProgress
        $pulse = { param($Event) & $progressUpdater $remnexaWorkProgress -CurrentItem 'HKCU\Software' }.GetNewClosure()
        $registryRun = Invoke-RemnexaNativeProcess -FilePath (Join-Path $env:WINDIR 'System32\reg.exe') -ArgumentList @('query','HKCU\Software','/f',$term,'/s') -TimeoutSeconds 600 -OnHeartbeat $pulse
        if ($registryRun.ExitCode -notin @(0,1)) { throw 'Die Registry-Suche konnte nicht abgeschlossen werden.' }
        $output = @($registryRun.StandardOutput -split '\r?\n')
        $currentKey = ''
        foreach ($line in $output) {
            if ($line -match '^HKEY_') {
                $currentKey = $line.Trim()
                $leaf = ($currentKey -split '\\')[-1]
                if ((Test-NameMatch -Value $leaf -Aliases $Aliases) -and -not (Test-ProtectedRegistryKey -RegistryPath $currentKey)) {
                    Add-Trace -Kind 'RegistryKey' -Target $currentKey -Reason ('Registrierungsschlüssel enthält ' + $term)
                }
                continue
            }

            if (-not $currentKey -or (Test-ProtectedRegistryKey -RegistryPath $currentKey)) { continue }
            if ($line -match '^\s{4}(.+?)\s{2,}(REG_[A-Z0-9_]+)\s{2,}(.*)$') {
                $valueName = $matches[1].Trim()
                $data = $matches[3]
                if ((Test-NameMatch -Value $valueName -Aliases $Aliases) -or (Test-NameMatch -Value $data -Aliases $Aliases)) {
                    Add-Trace -Kind 'RegistryValue' -Target $currentKey -ValueName $valueName -Reason ('Registrierungswert enthält ' + $term)
                }
            }
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Find-ServiceAndTaskTraces {
    param(
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$InstallPaths
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskServices') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        try {
            foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
                $combined = ([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName)
                $pathMatch = $false
                foreach ($path in $InstallPaths) {
                    if ($path -and $combined.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $pathMatch = $true; break }
                }
                if ($pathMatch -or (Test-NameMatch -Value $combined -Aliases $Aliases)) {
                    Add-Trace -Kind 'Service' -Target ([string]$service.Name) -Reason ([string]$service.DisplayName)
                }
            }
        }
        catch {
            Write-Status (T 'ServicesReadError' @($_.Exception.Message)) 'Warning'
        }

        try {
            foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
                $actionTextParts = New-Object System.Collections.Generic.List[string]
                foreach ($action in @((Get-OptionalPropertyValue -InputObject $task -PropertyName 'Actions'))) {
                    $execute = [string](Get-OptionalPropertyValue -InputObject $action -PropertyName 'Execute')
                    $arguments = [string](Get-OptionalPropertyValue -InputObject $action -PropertyName 'Arguments')
                    if ($execute -or $arguments) { $actionTextParts.Add($execute + ' ' + $arguments) }
                }
                $actionText = $actionTextParts -join ' '
                $combined = ([string]$task.TaskName) + ' ' + ([string]$task.TaskPath) + ' ' + $actionText
                $pathMatch = $false
                foreach ($path in $InstallPaths) {
                    if ($path -and $combined.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $pathMatch = $true; break }
                }
                if ($pathMatch -or (Test-NameMatch -Value $combined -Aliases $Aliases)) {
                    Add-Trace -Kind 'Task' -Target (([string]$task.TaskPath) + ([string]$task.TaskName)) -Reason 'Geplante Aufgabe'
                }
            }
        }
        catch {
            Write-Status (T 'TasksReadError' @($_.Exception.Message)) 'Warning'
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Find-AllTraces {
    param(
        [Parameter(Mandatory = $true)][object]$Identity,
        [AllowNull()][object]$Program,
        [bool]$WithUserFiles = $false
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskTraceSearch') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $script:TraceIndex = @{}
        foreach ($path in $Identity.InstallPaths) {
            Add-FileTraceIfSafe -Path $path -Reason 'Installationspfad des ausgewählten Programms'
        }

        $systemRoots = @(
            @{ Path = $env:ProgramFiles; Depth = 2 },
            @{ Path = ${env:ProgramFiles(x86)}; Depth = 2 },
            @{ Path = $env:ProgramData; Depth = 2 },
            @{ Path = $env:LOCALAPPDATA; Depth = 2 },
            @{ Path = $env:APPDATA; Depth = 2 },
            @{ Path = $env:TEMP; Depth = 1 },
            @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'); Depth = 4 },
            @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'); Depth = 4 }
        )

        foreach ($root in $systemRoots) {
            if ($root.Path) {
                Find-MatchingChildren -Root $root.Path -Aliases $Identity.Aliases -MaxDepth $root.Depth
            }
        }

        try {
            $systemDriveRoot = [IO.Path]::GetPathRoot($env:WINDIR)
            Find-MatchingChildren -Root $systemDriveRoot -Aliases $Identity.Aliases -MaxDepth 0
        }
        catch { }

        $prefetch = Join-Path $env:WINDIR 'Prefetch'
        Find-MatchingChildren -Root $prefetch -Aliases $Identity.Aliases -MaxDepth 0

        if ($WithUserFiles) {
            foreach ($personalRoot in @(
                (Join-Path $env:USERPROFILE 'Desktop'),
                (Join-Path $env:USERPROFILE 'Documents'),
                (Join-Path $env:USERPROFILE 'Downloads')
            )) {
                Find-MatchingChildren -Root $personalRoot -Aliases $Identity.Aliases -MaxDepth 4 -Personal $true
            }
        }

        Find-RegistryTraces -Aliases $Identity.Aliases -DeepRegistryTerm $Identity.DeepRegistryTerm -Program $Program
        Find-ServiceAndTaskTraces -Aliases $Identity.Aliases -InstallPaths $Identity.InstallPaths
        return @($script:TraceIndex.Values | Sort-Object Kind, Target, ValueName)
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Show-TraceSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces,
        [switch]$ShowAll
    )

    Write-Host ''
    if ($Traces.Count -eq 0) {
        Write-Status (T 'NoTraces') 'Success'
        return
    }

    Write-Host (T 'TracesFound' @($Traces.Count)) -ForegroundColor White
    foreach ($group in @($Traces | Group-Object Kind | Sort-Object Name)) {
        Write-Host ('  {0}: {1}' -f $group.Name, $group.Count)
        $visibleTraces = if ($ShowAll) { @($group.Group) } else { @($group.Group | Select-Object -First 8) }
        foreach ($trace in $visibleTraces) {
            $suffix = if ($trace.ValueName) { ' -> ' + $trace.ValueName } else { '' }
            $personal = if ($trace.Personal) { ' [' + (T 'PersonalFile') + ']' } else { '' }
            if ($trace.Kind -in @('File', 'Directory') -and (Test-RemnexaWindowsManagedPath -Path $trace.Target)) { $personal += ' [' + (T 'ManagedTraceLabel') + ']' }
            Write-Host ('    ' + $trace.Target + $suffix + $personal) -ForegroundColor DarkGray
        }
        if (-not $ShowAll -and $group.Count -gt 8) {
            Write-Host ('    ' + (T 'MoreItems' @(($group.Count - 8)))) -ForegroundColor DarkGray
        }
    }
}

function Read-TraceDeletionConfirmation {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces)
    if ($Traces.Count -eq 0) { return $false }
    $managedCount = @($Traces | Where-Object { $_.Kind -in @('File', 'Directory') -and (Test-RemnexaWindowsManagedPath -Path $_.Target) }).Count
    if ($managedCount -gt 0) { Write-Status (T 'ManagedTraceCount' @($managedCount)) 'Warning' }
    if ($managedCount -eq $Traces.Count) { return $false }

    Write-Host ''
    Write-Host ('  [1] ' + (T 'DeleteFoundTraces')) -ForegroundColor Red
    Write-Host ('  [2] ' + (T 'KeepFoundTraces'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $true }
        if ($answer -eq '2') { return $false }
        Write-Status (T 'InvalidTraceDelete') 'Warning'
    }
}

function New-RestorePointIfPossible {
    param([Parameter(Mandatory = $true)][string]$ProgramName)
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskBackup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if ($NoRestorePoint) {
            Write-Status (T 'RestoreSkipped') 'Warning'
            return $true
        }
        try {
            $description = 'REMNEXA-' + [Guid]::NewGuid().ToString('N') + ': ' + $ProgramName
            Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
            $created = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $description })
            if ($created.Count -eq 0) { throw (T 'RestorePointUnverified') }
            Write-Status (T 'RestorePointDone') 'Success'
            return $true
        }
        catch {
            Write-Status (T 'RestorePointFailed') 'Error'
            Write-Status $_.Exception.Message 'Warning'
            Write-Status (T 'RestoreBlocked') 'Error'
            if (-not $script:InteractiveSession) { return $false }
            Write-Host ('  [1] ' + (T 'RestoreAbort'))
            Write-Host ('  [2] ' + (T 'RestoreContinue')) -ForegroundColor Red
            while ($true) {
                $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
                if ($answer -eq '1') { return $false }
                if ($answer -eq '2') { return $true }
                Write-Status (T 'InvalidRestore') 'Warning'
            }
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Invoke-SelectedUninstall {
    param(
        [Parameter(Mandatory = $true)][object]$Program,
        [bool]$RemoveProvisioned = $false
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskUninstall') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if ($Program.Type -eq 'Appx') {
            $script:ProvisionedRemovedCount = 0
            Write-Status (T 'StoreRemoving' @($Program.DisplayName))
            Remove-AppxPackage -Package $Program.PackageFullName -ErrorAction Stop
            if ($RemoveProvisioned) {
                $packageName = [string]$Program.PackageName
                $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
                    $_.DisplayName -eq $packageName -or $_.PackageName -like ($packageName + '_*')
                })
                foreach ($package in $provisioned) {
                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                    $script:ProvisionedRemovedCount++
                }
                Write-Status (T 'AppxProvisionedDone' @($script:ProvisionedRemovedCount)) 'Success'
            }
            return
        }

        $commandLine = if ($Program.QuietUninstallString) { $Program.QuietUninstallString } else { $Program.UninstallString }
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            throw 'Das Programm besitzt kein verwendbares Deinstallationskommando.'
        }

        $guid = ''
        foreach ($candidate in @($Program.ProductCode, $commandLine)) {
            if ([string]$candidate -match '\{[0-9A-Fa-f-]{36}\}') { $guid = $matches[0]; break }
        }

        if ($guid) {
            $file = Join-Path $env:WINDIR 'System32\msiexec.exe'
            $arguments = '/x ' + $guid + ' /qn /norestart'
        }
        else {
            $split = Split-CommandLine -CommandLine $commandLine
            $file = $split[0]
            $arguments = $split[1]
        }

        if (-not (Test-Path -LiteralPath $file)) {
            $resolvedCommand = Get-Command -Name $file -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolvedCommand) {
                $file = $resolvedCommand.Source
            }
            else {
                throw ('Deinstallationsprogramm nicht gefunden: ' + $file)
            }
        }

        Write-Status (T 'UninstallRunning' @($Program.DisplayName))
        Update-RemnexaProgress $remnexaWorkProgress -CurrentItem $Program.DisplayName -Force
        # Preserve Start-Process -Wait's Windows descendant-wait behavior.
        # The vendor installer owns this blocking phase; do not guess a percent.
        $process = Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru
        $accepted = @(0, 1605, 1614, 1641, 3010)
        if ($accepted -notcontains $process.ExitCode) {
            throw ('Die Deinstallation meldete Exitcode ' + $process.ExitCode + '.')
        }
        if ($process.ExitCode -in @(1641, 3010)) { $script:RestartRequired = $true }
        Write-Status (T 'UninstallDone') 'Success'
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Remove-RegistryTrace {
    param([Parameter(Mandatory = $true)][object]$Trace)

    if (Test-ProtectedRegistryKey -RegistryPath $Trace.Target) {
        throw ('Geschützter Registrierungspfad wurde blockiert: ' + $Trace.Target)
    }

    if ($Trace.Kind -eq 'RegistryKey') {
        & reg.exe delete $Trace.Target /f 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('Registry-Schlüssel konnte nicht gelöscht werden: ' + $Trace.Target) }
        return
    }

    $defaultNames = @('(Default)', '(Standard)', '<NO NAME>')
    if ($defaultNames -contains $Trace.ValueName) {
        & reg.exe delete $Trace.Target /ve /f 2>$null | Out-Null
    }
    else {
        & reg.exe delete $Trace.Target /v $Trace.ValueName /f 2>$null | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw ('Registry-Wert konnte nicht gelöscht werden: ' + $Trace.Target + ' -> ' + $Trace.ValueName) }
}

function Remove-Traces {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces)
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskCleanup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $removed = 0
        $failed = New-Object System.Collections.Generic.List[string]
        $skipped = New-Object System.Collections.Generic.List[object]

        # Only successful key deletions cover child values. A denied parent must not
        # silently suppress a later attempt to remove an individually writable value.
        $removedKeys = New-Object System.Collections.Generic.List[string]
        $coveredCount = 0
        $ordered = @($Traces | Sort-Object @{
            Expression = {
                switch ($_.Kind) {
                    'Service' { 0 }
                    'Task' { 1 }
                    'RegistryKey' { 2 }
                    'RegistryValue' { 3 }
                    'File' { 4 }
                    'Directory' { 5 }
                    default { 9 }
                }
            }
        })

        $processedTraces = 0
        Update-RemnexaProgress $remnexaWorkProgress -Total $ordered.Count
        foreach ($trace in $ordered) {
            try {
                if ($trace.Kind -in @('File', 'Directory') -and (Test-RemnexaWindowsManagedPath -Path $trace.Target)) {
                    $skipped.Add([PSCustomObject]@{ Kind = $trace.Kind; Target = $trace.Target; Reason = 'WindowsManaged' })
                    continue
                }
                if ($trace.Kind -in @('RegistryKey', 'RegistryValue')) {
                    $covered = @($removedKeys | Where-Object { $trace.Target.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) -or $trace.Target.Equals($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
                    if ($covered) { $coveredCount++; continue }
                }

                switch ($trace.Kind) {
                    'File' {
                        if (Test-Path -LiteralPath $trace.Target) {
                            if (Test-ProtectedFilePath -Path $trace.Target) { throw 'Dateipfad ist geschuetzt, verlinkt oder nicht vollstaendig pruefbar.' }
                            Remove-Item -LiteralPath $trace.Target -Force -ErrorAction Stop
                        }
                    }
                    'Directory' {
                        if (Test-Path -LiteralPath $trace.Target) {
                            if (Test-ProtectedFilePath -Path $trace.Target) { throw 'Ordnerpfad ist geschuetzt, verlinkt oder nicht vollstaendig pruefbar.' }
                            Remove-Item -LiteralPath $trace.Target -Recurse -Force -ErrorAction Stop
                        }
                    }
                    'RegistryKey' { Remove-RegistryTrace -Trace $trace; $removedKeys.Add($trace.Target.TrimEnd('\')) }
                    'RegistryValue' { Remove-RegistryTrace -Trace $trace }
                    'Service' {
                        $service = Get-Service -Name $trace.Target -ErrorAction SilentlyContinue
                        if ($service) {
                            if ($service.Status -ne 'Stopped') { Stop-Service -Name $trace.Target -Force -ErrorAction SilentlyContinue }
                            & sc.exe delete $trace.Target | Out-Null
                            if ($LASTEXITCODE -ne 0) { throw ('Dienst konnte nicht gelöscht werden: ' + $trace.Target) }
                        }
                    }
                    'Task' {
                        $lastSlash = $trace.Target.LastIndexOf('\')
                        $taskPath = if ($lastSlash -ge 0) { $trace.Target.Substring(0, $lastSlash + 1) } else { '\' }
                        $taskName = if ($lastSlash -ge 0) { $trace.Target.Substring($lastSlash + 1) } else { $trace.Target }
                        Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                    }
                }
                $removed++
            }
            catch {
                $failureText = $trace.Target
                if ($_.Exception -is [UnauthorizedAccessException] -or $_.FullyQualifiedErrorId -match 'UnauthorizedAccess|PermissionDenied') { $failureText = T 'TraceAccessDenied' @($trace.Target) }
                $failed.Add($failureText + ' :: ' + $_.Exception.Message)
            }
            finally {
                $processedTraces++
                Update-RemnexaProgress $remnexaWorkProgress -Completed $processedTraces -CurrentItem $trace.Target
            }
        }
        if ($failed.Count -gt 0 -or $skipped.Count -gt 0) { Add-RemnexaProgressNotice -Level Warning }

        return [PSCustomObject]@{ Removed = $removed; Failed = $failed.ToArray(); Skipped = $skipped.ToArray(); CoveredByParent = $coveredCount }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Save-RunLog {
    param(
        [AllowNull()][object]$Program,
        [Parameter(Mandatory = $true)][string]$SearchName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Traces,
        [AllowNull()][object]$Result
    )

    try {
        $logRoot = $script:LogRoot
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeName = (Normalize-Text $SearchName)
        if (-not $safeName) { $safeName = 'programm' }
        $base = Join-Path $logRoot ($stamp + '-' + $safeName)

        $manifest = [PSCustomObject]@{
            CleanerVersion = $script:CleanerVersion
            Timestamp      = (Get-Date).ToString('o')
            Computer       = $env:COMPUTERNAME
            SearchName     = $SearchName
            Selected       = $Program
            IncludeUserFiles = [bool]$IncludeUserFiles
            DryRun         = [bool]$DryRun
            Traces         = $Traces
            Result         = $Result
        }
        $manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath ($base + '.json') -Encoding UTF8
        $script:LogLines | Set-Content -LiteralPath ($base + '.log') -Encoding UTF8
        return ($base + '.json')
    }
    catch {
        Write-Status (T 'LogSaveError' @($_.Exception.Message)) 'Warning'
        return ''
    }
}

function Save-ToolLog {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [AllowNull()][object]$Data
    )

    try {
        New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
        $safeAction = (Normalize-Text $Action)
        if (-not $safeAction) { $safeAction = 'tool' }
        $path = Join-Path $script:LogRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $safeAction + '.json')
        [PSCustomObject]@{
            CleanerVersion = $script:CleanerVersion
            Timestamp      = [DateTimeOffset]::Now.ToString('o')
            Computer       = $env:COMPUTERNAME
            Action         = $Action
            Data           = $Data
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
    catch {
        Write-Status (T 'LogSaveError' @($_.Exception.Message)) 'Warning'
        return ''
    }
}

function Test-SystemIntegrity {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskStatus') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $checks = New-Object System.Collections.Generic.List[object]
        $warnings = New-Object System.Collections.Generic.List[string]
        $serviceRules = @(
            [PSCustomObject]@{ Name = 'wuauserv'; Display = 'Windows Update' },
            [PSCustomObject]@{ Name = 'BITS'; Display = 'Background Intelligent Transfer Service' },
            [PSCustomObject]@{ Name = 'SecurityHealthService'; Display = 'Windows Security Health' },
            [PSCustomObject]@{ Name = 'InstallService'; Display = 'Microsoft Store Install Service' }
        )

        Write-Host ''
        Write-Host (T 'IntegrityTitle') -ForegroundColor White
        foreach ($rule in $serviceRules) {
            $state = 'Unknown'
            $startMode = 'Unknown'
            $severity = 'Info'
            $detail = ''
            try {
                $service = Get-CimInstance -ClassName Win32_Service -Filter ("Name='" + $rule.Name + "'") -ErrorAction Stop
                if ($null -eq $service) { throw 'Service was not returned.' }
                $state = [string]$service.State
                $startMode = [string]$service.StartMode
                if ($startMode -eq 'Disabled') { $messageKey = 'ServiceDisabled'; $severity = 'Warning' }
                elseif ($state -eq 'Running') { $messageKey = 'ServiceRunning' }
                elseif ($state -eq 'Stopped' -and $startMode -eq 'Manual') { $messageKey = 'ServiceOnDemand' }
                else { $messageKey = 'ServiceStopped' }
            }
            catch { $messageKey = 'ServiceUnavailable'; $severity = 'Warning'; $detail = $_.Exception.Message }
            $message = T $messageKey @($rule.Display)
            $healthy = $severity -ne 'Warning'
            $check = [PSCustomObject]@{
                Type      = 'Service'
                Name      = $rule.Name
                Display   = $rule.Display
                State     = $state
                StartMode = $startMode
                Healthy   = [bool]$healthy
                Severity  = $severity
                Message   = $message
                ErrorDetail = $detail
            }
            $checks.Add($check)
            Write-Host ('  ' + (T 'IntegrityLine' @($rule.Display, $state, $startMode))) -ForegroundColor $(if ($healthy) { 'Green' } else { 'Yellow' })
            Write-Host ('    ' + $message) -ForegroundColor $(if ($healthy) { 'DarkGray' } else { 'Yellow' })
            if (-not $healthy) { $warnings.Add($message) }
        }

        $defender = $null
        $defenderAvailable = $false
        $securityCenterAvailable = $false
        $registeredProducts = @()
        $providerErrors = New-Object System.Collections.Generic.List[string]
        try {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            $defenderAvailable = $null -ne $defender
        }
        catch { $providerErrors.Add('Get-MpComputerStatus: ' + $_.Exception.Message) }
        try {
            $registeredProducts = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct -ErrorAction Stop |
                Select-Object displayName, productState, timestamp)
            $securityCenterAvailable = $true
        }
        catch { $providerErrors.Add('SecurityCenter2: ' + $_.Exception.Message) }
        $assessment = Get-RemnexaAntivirusAssessment -Defender $defender -DefenderAvailable $defenderAvailable -RegisteredProducts $registeredProducts -SecurityCenterAvailable $securityCenterAvailable
        $securityMessage = T $assessment.MessageKey @(($assessment.ProductNames -join ', '))
        $checks.Add([PSCustomObject]@{
            Type = 'AntivirusStatus'; Name = 'Antivirus'; Display = 'Antivirus'; State = $assessment.MessageKey;
            StartMode = ''; Healthy = ($assessment.Severity -ne 'Warning'); Severity = $assessment.Severity; Message = $securityMessage
        })
        Write-Host ('  ' + $securityMessage) -ForegroundColor $(if ($assessment.Severity -eq 'Warning') { 'Yellow' } else { 'DarkGray' })
        if ($assessment.Severity -eq 'Warning') { $warnings.Add($securityMessage) }

        $result = [PSCustomObject]@{
            Timestamp = [DateTimeOffset]::Now.ToString('o')
            Passed    = ($warnings.Count -eq 0)
            Warnings  = $warnings.ToArray()
            Checks    = $checks.ToArray()
            AntivirusAssessment = $assessment
            RegisteredAntivirusProducts = @($registeredProducts)
            ProviderErrors = $providerErrors.ToArray()
        }
        if ($result.Passed) {
            Write-Status (T 'IntegrityHealthy') 'Success'
        }
        else {
            Write-Status (T 'IntegrityWarnings' @($warnings.Count)) 'Warning'
        }
        return $result
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Read-IntegrityCheckChoice {
    if ($TestIntegrity) { return $true }
    if (-not $script:InteractiveSession) { return $false }
    Write-Host ''
    Write-Host (T 'IntegrityQuestion') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'IntegrityRun'))
    Write-Host ('  [2] ' + (T 'IntegritySkip'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -eq '1') { return $true }
        if ($answer -eq '2') { return $false }
        Write-Status (T 'InvalidOneTwo') 'Warning'
    }
}

function Invoke-PostRemovalIntegrityCheck {
    # The removal result and its log already exist before this optional prompt.
    if ($null -eq $script:LastRunSummary -or $null -eq $script:LastOperationResult -or
        $script:LastOperationResult.Status -notin @('Completed', 'Partial')) { return }
    if (-not (Read-IntegrityCheckChoice)) { return }
    try {
        $checkResult = Test-SystemIntegrity
        $script:LastRunSummary.Integrity = $checkResult
        $logPath = Save-ToolLog -Action 'PostRemovalSystemCheck' -Data ([PSCustomObject]@{
            RemovalLogPath = $script:LastRunLogPath
            OperationId = $script:LastOperationResult.OperationId
            CheckResult = $checkResult
        })
        $script:LastRunSummary | Add-Member -NotePropertyName IntegrityLogPath -NotePropertyValue ([string]$logPath) -Force
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    }
    catch {
        # A diagnostic failure must not relabel a completed uninstall as failed.
        Write-Status (T 'OptionalCheckFailed' @($_.Exception.Message)) 'Warning'
    }
}

function Invoke-SystemIntegrityScreen {
    Clear-RemnexaScreen
    Show-BrandHeader
    $result = Test-SystemIntegrity
    $logPath = Save-ToolLog -Action 'SystemIntegrity' -Data $result
    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Get-RemovalHistory {
    if (-not (Test-Path -LiteralPath $script:HistoryPath)) { return @() }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $script:HistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json -DateKind String)) } catch { }
    }
    return @($entries | Sort-Object Timestamp -Descending)
}

function Add-RemovalHistory {
    param(
        [Parameter(Mandatory = $true)][string]$ProgramName,
        [bool]$ResidualMode,
        [int]$RemovedCount,
        [int]$FailedCount,
        [int]$RemainingCount,
        [int64]$FreedBytes = 0,
        [AllowEmptyString()][string]$LogPath
    )

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        $entry = [PSCustomObject]@{
            Id              = [Guid]::NewGuid().ToString('N')
            Timestamp       = [DateTimeOffset]::Now.ToString('o')
            ProgramName     = $ProgramName
            Mode            = $(if ($ResidualMode) { 'ResidualOnly' } else { 'Uninstall' })
            RemovedTraces   = $RemovedCount
            FailedTraces    = $FailedCount
            RemainingTraces = $RemainingCount
            FreedBytes       = $FreedBytes
            RestartRequired = [bool]$script:RestartRequired
            Status          = $(if ($FailedCount -eq 0 -and $RemainingCount -eq 0) { 'Complete' } else { 'Warnings' })
            LogPath         = $LogPath
        }
        ($entry | ConvertTo-Json -Compress -Depth 4) |
            Add-Content -LiteralPath $script:HistoryPath -Encoding UTF8
    }
    catch {
        Write-Status (T 'HistorySaveError' @($_.Exception.Message)) 'Warning'
    }
}

function Import-HistoryFromExistingLogs {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskInventory') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (-not (Test-Path -LiteralPath $script:LogRoot)) { return }

        try {
            $knownLogs = @{}
            foreach ($entry in @(Get-RemovalHistory)) {
                $knownPath = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'LogPath')
                if (-not [string]::IsNullOrWhiteSpace($knownPath)) { $knownLogs[$knownPath] = $true }
            }

            $importedEntries = New-Object System.Collections.Generic.List[object]
            foreach ($file in @(Get-ChildItem -LiteralPath $script:LogRoot -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                if ($knownLogs.ContainsKey($file.FullName)) { continue }
                try {
                    $manifest = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
                    $wasDryRun = [bool](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'DryRun')
                    $result = Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Result'
                    if ($wasDryRun -or $null -eq $result -or $result -eq '') { continue }

                    $programName = [string](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'SearchName')
                    if ([string]::IsNullOrWhiteSpace($programName)) { continue }
                    if ($programName -like 'CodexCleanerFixture*') { continue }
                    $timestamp = [string](Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Timestamp')
                    if ([string]::IsNullOrWhiteSpace($timestamp)) { $timestamp = $file.LastWriteTime.ToString('o') }
                    $removed = [int](Get-OptionalPropertyValue -InputObject $result -PropertyName 'Removed')
                    $failed = @((Get-OptionalPropertyValue -InputObject $result -PropertyName 'Failed')).Count
                    $selected = Get-OptionalPropertyValue -InputObject $manifest -PropertyName 'Selected'

                    $importedEntries.Add([PSCustomObject]@{
                        Id              = [Guid]::NewGuid().ToString('N')
                        Timestamp       = $timestamp
                        ProgramName     = $programName
                        Mode            = $(if ($null -eq $selected -or $selected -eq '') { 'ResidualOnly' } else { 'Uninstall' })
                        RemovedTraces   = $removed
                        FailedTraces    = $failed
                        RemainingTraces = 0
                        FreedBytes       = [int64](Get-OptionalPropertyValue -InputObject $result -PropertyName 'FreedBytes')
                        RestartRequired = $false
                        Status          = $(if ($failed -eq 0) { 'Complete' } else { 'Warnings' })
                        LogPath         = $file.FullName
                    })
                }
                catch { }
            }

            if ($importedEntries.Count -gt 0) {
                New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
                foreach ($entry in $importedEntries) {
                    ($entry | ConvertTo-Json -Compress -Depth 4) |
                        Add-Content -LiteralPath $script:HistoryPath -Encoding UTF8
                }
            }
        }
        catch { }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Get-HistoryStatusText {
    param([AllowEmptyString()][string]$Status)
    if ($Status -eq 'Complete') { return (T 'StatusComplete') }
    return (T 'StatusWarnings')
}

function Format-HistoryTimestamp {
    param([AllowEmptyString()][string]$Timestamp)
    try {
        $parsed = [DateTimeOffset]::Parse(
            $Timestamp,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
        return $parsed.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    }
    catch { return $Timestamp }
}

function Show-HistorySummary {
    $history = @(Get-RemovalHistory | Select-Object -First 3)
    Write-Host (T 'HistoryHeading') -ForegroundColor White
    if ($history.Count -eq 0) {
        Write-Host ('  ' + (T 'HistoryNone')) -ForegroundColor DarkGray
    }
    else {
        foreach ($entry in $history) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $status = Get-HistoryStatusText -Status ([string]$entry.Status)
            $line = T 'HistoryLine' @($when, [string]$entry.ProgramName, [int]$entry.RemovedTraces, $status)
            $freed = [int64](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'FreedBytes')
            if ($freed -gt 0) { $line += T 'HistoryFreed' @((Format-ByteSize -Bytes $freed)) }
            Write-Host ('  ' + $line) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

function Read-MainOrExitChoice {
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -in @('1', 'menu', 'm')) { return 'menu' }
        if ($answer -in @('0', 'exit')) { return 'exit' }
        Write-Status (T 'InvalidPost') 'Warning'
    }
}

function Show-HistoryScreen {
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'HistoryTitle') -ForegroundColor White
    Write-Host ''
    $history = @(Get-RemovalHistory)
    if ($history.Count -eq 0) {
        Write-Host (T 'HistoryNone') -ForegroundColor DarkGray
    }
    else {
        $number = 1
        foreach ($entry in @($history | Select-Object -First 100)) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $status = Get-HistoryStatusText -Status ([string]$entry.Status)
            $line = T 'HistoryLine' @($when, [string]$entry.ProgramName, [int]$entry.RemovedTraces, $status)
            $freed = [int64](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'FreedBytes')
            if ($freed -gt 0) { $line += T 'HistoryFreed' @((Format-ByteSize -Bytes $freed)) }
            Write-Host ('  [{0}] {1}' -f $number, $line)
            $number++
        }
    }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Show-LanguageMenu {
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'LanguageTitle') -ForegroundColor White
    Write-Host (T 'LanguageCurrent' @((Get-LanguageDisplayName -Code $script:Language))) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1] Deutsch'
    Write-Host '  [2] English'
    Write-Host '  [3] Español'
    Write-Host '  [4] Français'
    Write-Host '  [5] Русский'
    Write-Host '  [6] Türkçe'
    Write-Host ('  [0] ' + (T 'BackMain'))

    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -eq '0') { return }
        $mapping = @{ '1' = 'de'; '2' = 'en'; '3' = 'es'; '4' = 'fr'; '5' = 'ru'; '6' = 'tr' }
        if ($mapping.ContainsKey($answer)) {
            $script:Language = [string]$mapping[$answer]
            Save-AppSettings
            Write-Status (T 'LanguageSaved' @((Get-LanguageDisplayName -Code $script:Language))) 'Success'
            Start-Sleep -Milliseconds 900
            return
        }
        Write-Status (T 'InvalidLanguage') 'Warning'
    }
}

function Show-AdvancedToolsMenu {
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'ToolsTitle') -ForegroundColor White
    Write-Host ''
    Write-Host ('  [1] ' + (T 'Tools1'))
    Write-Host ('  [2] ' + (T 'Tools2'))
    Write-Host ('  [3] ' + (T 'Tools3'))
    Write-Host ('  [4] ' + (T 'Tools4'))
    Write-Host ('  [5] ' + (T 'Tools5'))
    Write-Host ('  [6] ' + (T 'Tools6'))
    Write-Host ('  [0] ' + (T 'BackMain'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -match '^[0-6]$') { return $answer }
        Write-Status (T 'InvalidTools') 'Warning'
    }
}

function Get-AVUpdateStatusText {
    param([string]$Status)
    if($Status -notin @('current','update_available','unknown','offline','check_failed','not_installed')) { $Status='unknown' }
    T ('AVUpdateState_'+$Status)
}

function Show-AVUpdateSummary {
    param($State,[switch]$Detailed)
    if($null -eq $State) {
        try { $State=Get-ClamAVUpdateState }
        catch { Write-Host (T 'AVUpdateState_check_failed') -ForegroundColor Yellow;return }
    }
    $color=if($State.status -eq 'current' -and -not $State.isStale){'Green'}else{'Yellow'}
    if($State.isChecking) { Write-Host (T 'AVUpdateChecking') -ForegroundColor Cyan }
    elseif($State.status -eq 'not_installed') { Write-Host (T 'AVUpdateState_not_installed') -ForegroundColor Yellow;return }
    elseif($State.status -eq 'offline') { Write-Host (T 'AVUpdateState_offline') -ForegroundColor Yellow }
    if($State.isStale) { Write-Host (T 'AVUpdateStale') -ForegroundColor Yellow }
    $installed=if($State.engine.installedVersion){$State.engine.installedVersion}else{'?'}
    $available=if($State.engine.availableVersion){$State.engine.availableVersion}else{'?'}
    Write-Host (T 'AVUpdateEngineLine' @($installed,$available,(Get-AVUpdateStatusText $State.engine.status))) -ForegroundColor $color
    Write-Host (T 'AVUpdateSignatureLine' @((Get-AVUpdateStatusText $State.signatures.status))) -ForegroundColor $color
    if($State.signatures.recommended -and $State.signatures.status -ne 'update_available') { Write-Host (T 'AVUpdateRecommended') -ForegroundColor Yellow }
    if($State.engine.updateAvailable -and -not $State.engine.canUpdate) { Write-Host (T 'AVUpdatePackageBlocked') -ForegroundColor Yellow }
    if($Detailed) {
        foreach($db in $State.signatures.databases) {
            Write-Host (T 'AVUpdateDatabaseLine' @($db.name,$db.installedVersion,$db.availableVersion,(Get-AVUpdateStatusText $db.status)))
        }
        $checked=if($State.lastSuccessfulCheckUtc){Format-HistoryTimestamp $State.lastSuccessfulCheckUtc}else{T 'AVUpdateState_unknown'}
        Write-Host (T 'AVUpdateLastCheck' @($checked)) -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-AVConfirmedUpdate {
    param([ValidateSet('Engine','Signatures','Both')][string]$Component)
    Write-Host ('  [J] '+(T 'AVUpdateConfirm'))
    Write-Host ('  [0] '+(T 'BackPreviousMenu'))
    while($true) {
        $answer=(Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
        if($answer -in @('0','N')) { return $false }
        if($answer -in @('J','Y')) { [void](Invoke-ClamAVManagedUpdate -Component $Component -Confirm:$false);Write-Status (T 'AVUpdateDone') 'Success';return $true }
        Write-Status (T 'AVUpdateInvalidChoice') 'Warning'
    }
}

function Invoke-AVUpdateMenu {
    $state=Invoke-ClamAVUpdateCheck -Force
    while($true) {
        Show-AVUpdateSummary -State $state -Detailed
        $actions=@{}
        if($state.status -ne 'offline' -and $state.status -ne 'not_installed') {
            if($state.signatures.canUpdate) { $actions['1']='Signatures';Write-Host ('  [1] '+(T 'AVUpdateSignaturesOnly')) }
            if($state.engine.updateAvailable -and $state.engine.canUpdate -and -not $state.engine.isStale) {
                $actions['2']='Engine';Write-Host ('  [2] '+(T 'AVUpdateEngineOnly'))
                if($state.signatures.canUpdate) { $actions['3']='Both';Write-Host ('  [3] '+(T 'AVUpdateBoth')) }
            }
        }
        Write-Host ('  [0] '+(T 'BackPreviousMenu'))
        $answer=(Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if($answer -eq '0') { return }
        if($actions.ContainsKey($answer)) { [void](Invoke-AVConfirmedUpdate -Component $actions[$answer]);return }
        Write-Status (T 'AVUpdateInvalidChoice') 'Warning'
    }
}

function Invoke-AVScanWithUpdatePrompt {
    param([ValidateSet('Quick','Full','Custom')][string]$ScanType='Custom',[string[]]$Path=@(),[switch]$Targeted)
    $state=Get-ClamAVUpdateState
    $signatures=($state.signatures.status -eq 'update_available' -and $state.signatures.canUpdate -and -not $state.signatures.isStale)
    $engine=($state.engine.updateAvailable -and $state.engine.canUpdate -and -not $state.engine.isStale)
    if($signatures -or $engine) {
        if($signatures) { Write-Host (T 'AVUpdateBeforeScanSignatures') -ForegroundColor Yellow }
        if($engine) { Write-Host (T 'AVUpdateBeforeScanEngine' @($state.engine.availableVersion)) -ForegroundColor Yellow }
        $update=$false
        while($true) {
            Write-Host ('  [J] '+(T 'AVUpdateAndScan'))
            Write-Host ('  [N] '+(T 'AVUpdateSkipAndScan'))
            Write-Host ('  [I] '+(T 'AVUpdateInfo'))
            Write-Host ('  [0] '+(T 'BackPreviousMenu'))
            $answer=(Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
            if($answer -eq '0') { return @() }
            if($answer -eq 'N') { break }
            if($answer -eq 'I') { Show-AVUpdateSummary -State $state -Detailed;continue }
            if($answer -in @('J','Y')) { $update=$true;break }
            Write-Status (T 'AVUpdateInvalidChoice') 'Warning'
        }
        if($update) {
            $component=if($signatures -and $engine){'Both'}elseif($engine){'Engine'}else{'Signatures'}
            try { [void](Invoke-ClamAVManagedUpdate -Component $component -Confirm:$false) }
            catch {
                Write-Status (T 'AVUpdateFailure') 'Warning'
                Write-LogEntry -Message $_.Exception.Message -Level Warning -Component 'Antivirus/Update'
                # One separate consent after failure; never retry the update here.
                while($true) {
                    Write-Host ('  [J] '+(T 'AVUpdateContinueAfterFailure'))
                    Write-Host ('  [0] '+(T 'BackPreviousMenu'))
                    $answer=(Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
                    if($answer -in @('0','N')) { return @() }
                    if($answer -in @('J','Y')) { break }
                    Write-Status (T 'AVUpdateInvalidChoice') 'Warning'
                }
            }
        }
    }
    if($Targeted) { return @(Invoke-ClamAVTargetedScan -Path $Path) }
    $parameters=@{ScanType=$ScanType}
    if($Path.Count) { $parameters.Path=$Path }
    return @(Invoke-ClamAVScan @parameters)
}

function Invoke-AVPerformanceMenu {
    while($true) {
        Write-Host (T 'AVPerformanceTitle') -ForegroundColor White
        Write-Host (T 'AVPerformanceCurrent' @((Get-AVConfig).ScanPerformanceMode))
        Write-Host ('  [1] '+(T 'AVPerformanceEco'))
        Write-Host ('  [2] '+(T 'AVPerformanceBalanced'))
        Write-Host ('  [3] '+(T 'AVPerformanceFast'))
        Write-Host ('  [0] '+(T 'BackPreviousMenu'))
        $choice=(Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if($choice -eq '0'){return}
        if($choice -in @('1','2','3')) {
            $mode=@{ '1'='Eco';'2'='Balanced';'3'='Fast' }[$choice]
            Set-AVConfig -Values @{ScanPerformanceMode=$mode} -Confirm:$false
            return
        }
        Write-Status (T 'AVUpdateInvalidChoice') 'Warning'
    }
}

function Invoke-AntivirusMenu {
    if (-not (Request-ElevationForTool -Mode Antivirus)) { return 'menu' }
    if (-not (Initialize-AntivirusModule)) { return 'menu' }

    :antivirusLoop while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader
        Write-Host (T 'AVTitle') -ForegroundColor White
        Write-Host ''
        Show-AVUpdateSummary
        Write-Host ('  [1] ' + (T 'AV1'))
        Write-Host ('  [2] ' + (T 'AV2'))
        Write-Host ('  [3] ' + (T 'AV3'))
        Write-Host ('  [4] ' + (T 'AV4'))
        Write-Host ('  [5] ' + (T 'AV5'))
        Write-Host ('  [6] ' + (T 'AV6'))
        Write-Host ('  [7] ' + (T 'AV7'))
        Write-Host ('  [U] ' + (T 'AVUpdateCheck'))
        Write-Host ('  [I] ' + (T 'AVUpdateInfo'))
        Write-Host ('  [P] ' + (T 'AVPerformanceMenu'))
        Write-Host ('  [0] ' + (T 'BackPreviousMenu'))
        $choice = (Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
        if ($choice -eq '0') { return 'menu' }
        if ($choice -notmatch '^[1-7UIP]$') {
            Write-Status (T 'InvalidAVChoice') 'Warning'
            Start-Sleep -Milliseconds 800
            continue antivirusLoop
        }

        try {
            switch ($choice) {
                'P' { Invoke-AVPerformanceMenu;continue antivirusLoop }
                'U' { Invoke-AVUpdateMenu;continue antivirusLoop }
                'I' { Show-AVUpdateSummary -Detailed }
                '1' {
                    Get-ClamAVStatus | Format-List Installed, Ready, Version, SignatureDate, SignatureAgeDays, Signatures, SignaturesOutdated, ClamScanPath, FreshClamPath, DatabasePath | Out-Host
                }
                '2' {
                    Initialize-ClamAV -Install -Confirm:$false | Format-List | Out-Host
                }
                '3' {
                    [void](Invoke-AVConfirmedUpdate -Component Engine)
                }
                '4' {
                    [void](Invoke-AVConfirmedUpdate -Component Signatures)
                }
                '5' {
                    $results = @(Invoke-AVScanWithUpdatePrompt -ScanType Quick)
                    if($results.Count -eq 0) { continue antivirusLoop }
                    $results | Format-Table Status, Severity, Signature, Path -AutoSize | Out-Host
                }
                '6' {
                    $customPath = (Read-RemnexaInput (T 'AVPathPrompt')).Trim().Trim('"')
                    if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                        $results = @(Invoke-AVScanWithUpdatePrompt -Path $customPath -ScanType Custom)
                        if($results.Count -eq 0) { continue antivirusLoop }
                        $results | Format-Table Status, Severity, Signature, Path -AutoSize | Out-Host
                    }
                }
                '7' {
                    $entries = @(Get-ClamAVQuarantine)
                    if ($entries.Count -eq 0) {
                        Write-Status (T 'AVNoQuarantine') 'Success'
                    }
                    else {
                        for ($index = 0; $index -lt $entries.Count; $index++) {
                            Write-Host ('  [{0}] {1} | {2} | {3}' -f ($index + 1), $entries[$index].Signature, $entries[$index].QuarantinedAt, $entries[$index].OriginalPath)
                        }
                        while ($true) {
                            $restoreChoice = Read-RemnexaInput (T 'AVRestorePrompt')
                            $restoreNumber = ConvertFrom-RemnexaMenuChoice -InputText $restoreChoice -Maximum $entries.Count
                            if ($null -eq $restoreNumber) {
                                Write-Status (T 'AVInvalidRestore' @($entries.Count)) 'Warning'
                                continue
                            }
                            if ($restoreNumber -eq 0) { break }
                            $restoreEntry = $entries[$restoreNumber - 1]
                            $restoreConfirmation = Read-ExplicitConfirmation -WarningText (T 'AVRestoreWarning' @($restoreEntry.Signature, $restoreEntry.OriginalPath)) -ActionText (T 'AVRestoreAction')
                            if ($restoreConfirmation -eq 'exit') { Stop-RemnexaApplication }
                            if ($restoreConfirmation -eq 'menu') { return 'menu' }
                            Restore-FromClamAVQuarantine -Identifier $restoreEntry.QuarantineId -Force -Confirm:$false | Format-List | Out-Host
                            break
                        }
                    }
                }
            }
        }
        catch {
            Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
        }

        Write-Host ''
        Write-Host ('  [1] ' + (T 'AVReturnMenu'))
        Write-Host ('  [0] ' + (T 'BackMain'))
        while ($true) {
            $afterChoice = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
            if ($afterChoice -eq '1') { continue antivirusLoop }
            if ($afterChoice -eq '0') { return 'menu' }
            Write-Status (T 'InvalidPost') 'Warning'
        }
    }
}

function Read-ExplicitConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$WarningText,
        [Parameter(Mandatory = $true)][string]$ActionText
    )
    Write-Host ''
    Write-Host $WarningText -ForegroundColor Yellow
    Write-Host ('  [1] ' + $ActionText) -ForegroundColor Red
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -eq '1') { return 'start' }
        if ($answer -eq '2') { return 'menu' }
        if ($answer -eq '0') { return 'exit' }
        Write-Status (T 'InvalidConfirm') 'Warning'
    }
}

function Get-OrphanedUninstallEntries {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskRegistry') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $entries = New-Object System.Collections.Generic.List[object]
        $roots = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($entry in @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue)) {
            $displayName = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
            if ([string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'SystemComponent') -eq '1') { continue }

            $uninstall = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'UninstallString')
            $installLocation = [Environment]::ExpandEnvironmentVariables([string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'InstallLocation'))
            if ([string]::IsNullOrWhiteSpace($uninstall) -and [string]::IsNullOrWhiteSpace($installLocation)) { continue }

            $validLocation = (-not [string]::IsNullOrWhiteSpace($installLocation)) -and (Test-Path -LiteralPath $installLocation)
            $validUninstaller = $false
            $uninstallExecutable = Get-ExecutableFromCommandLine -CommandLine $uninstall
            if (-not [string]::IsNullOrWhiteSpace($uninstallExecutable)) {
                $validUninstaller = Test-Path -LiteralPath $uninstallExecutable
                if (-not $validUninstaller) {
                    $validUninstaller = $null -ne (Get-Command -Name $uninstallExecutable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
                }
            }
            if ($uninstall -match '(?i)msiexec(\.exe)?\s+[/\\][xXiI]\s*\{[0-9A-F-]{36}\}') { $validUninstaller = $true }
            if ($validLocation -or $validUninstaller) { continue }

            $candidate = [PSCustomObject]@{
                Type = 'OrphanRegistry'; SourceLabel = 'Registry'; DisplayName = $displayName
                DisplayVersion = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'DisplayVersion')
                Publisher = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Publisher')
                InstallLocation = $installLocation; InstallSource = ''; UninstallString = $uninstall
                QuietUninstallString = ''; RegistryPath = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSPath')
                ProductCode = [string](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'PSChildName')
                PackageFullName = ''; PackageName = ''; IsSystemLike = $false; CanUninstall = $true
            }
            if ($null -eq (Get-ProtectedComponentMatch -Program $candidate -SearchName $displayName)) { $entries.Add($candidate) }
        }
        return @($entries | Sort-Object DisplayName, RegistryPath -Unique)
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Invoke-OrphanRegistryMenu {
    if (-not (Request-ElevationForTool -Mode Registry)) { return 'menu' }
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'OrphanTitle') -ForegroundColor White
    Write-Host (T 'OrphanDescription') -ForegroundColor DarkGray
    $entries = @(Get-OrphanedUninstallEntries)
    if ($entries.Count -eq 0) {
        Write-Status (T 'OrphanNone') 'Success'
        Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }
    Write-Status (T 'OrphanFound' @($entries.Count)) 'Warning'
    $selected = Select-ProgramPaged -Programs $entries -Title (T 'OrphanTitle')
    if ($script:ExitRequested) { return 'exit' }
    if ($null -eq $selected) { return 'menu' }
    $nativePath = $selected.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    Write-Host (T 'RegistryPathLabel' @($nativePath)) -ForegroundColor DarkGray
    $confirmation = Read-ExplicitConfirmation -WarningText (T 'OrphanDescription') -ActionText (T 'OrphanDelete')
    if ($confirmation -ne 'start') { return $confirmation }
    if (-not (New-RestorePointIfPossible -ProgramName $selected.DisplayName)) { return 'menu' }
    try {
        Remove-RegistryTrace -Trace ([PSCustomObject]@{ Kind = 'RegistryKey'; Target = $nativePath; ValueName = '' })
        Write-Status (T 'OrphanDeleted') 'Success'
        $logPath = Save-ToolLog -Action 'OrphanRegistryRemoval' -Data $selected
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    }
    catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Invoke-OptionalFeatureMenu {
    if (-not (Request-ElevationForTool -Mode Features)) { return 'menu' }
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'FeatureTitle') -ForegroundColor White
    $featureProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskFeatures')
    try {
        $features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object State -eq 'Enabled' | ForEach-Object {
            [PSCustomObject]@{
                Type = 'OptionalFeature'; SourceLabel = 'DISM'; DisplayName = [string]$_.FeatureName
                DisplayVersion = ''; Publisher = 'Microsoft'; InstallLocation = ''; InstallSource = ''
                UninstallString = ''; QuietUninstallString = ''; RegistryPath = ''; ProductCode = ''
                PackageFullName = ''; PackageName = ''; IsSystemLike = $false; CanUninstall = $true
            }
        })
        Complete-RemnexaProgress $featureProgress
    }
    catch {
        Complete-RemnexaProgress $featureProgress -Outcome Failed
        Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
        $features = @()
    }
    if ($features.Count -eq 0) {
        Write-Status (T 'FeatureNone') 'Warning'
        Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }
    $selected = Select-ProgramPaged -Programs $features -Title (T 'FeatureTitle')
    if ($script:ExitRequested) { return 'exit' }
    if ($null -eq $selected) { return 'menu' }
    if (-not (Confirm-ProtectedComponentOverride -Program $selected -SearchName $selected.DisplayName)) { return 'menu' }
    $warning = T 'FeatureWarning' @($selected.DisplayName)
    $confirmation = Read-ExplicitConfirmation -WarningText $warning -ActionText $warning
    if ($confirmation -ne 'start') { return $confirmation }
    if (-not (New-RestorePointIfPossible -ProgramName $selected.DisplayName)) { return 'menu' }
    $featureChangeProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskFeatures')
    try {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $selected.DisplayName -NoRestart -ErrorAction Stop
        Complete-RemnexaProgress $featureChangeProgress
        if ([bool]$result.RestartNeeded) { $script:RestartRequired = $true }
        Write-Status (T 'FeatureDisabled' @($selected.DisplayName)) 'Success'
        $logPath = Save-ToolLog -Action 'DisableWindowsFeature' -Data ([PSCustomObject]@{ Feature = $selected.DisplayName; RestartNeeded = [bool]$result.RestartNeeded })
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
        if ($script:RestartRequired) { Write-Status (T 'RestartNotice') 'Warning' }
    }
    catch {
        if ($featureChangeProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $featureChangeProgress -Outcome Failed }
        Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
    }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Get-PrivacyRegistryChanges {
    return @(
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord' },
        [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0; Type = 'DWord' }
    )
}

function Save-PrivacyBackupIfNeeded {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskBackup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (Test-Path -LiteralPath $script:PrivacyBackupPath) { return }
        $snapshots = New-Object System.Collections.Generic.List[object]
        foreach ($change in @(Get-PrivacyRegistryChanges)) {
            $key = Get-Item -LiteralPath $change.Path -ErrorAction SilentlyContinue
            $valueObject = if ($key) { Get-ItemProperty -LiteralPath $change.Path -Name $change.Name -ErrorAction SilentlyContinue } else { $null }
            $property = if ($null -ne $valueObject) { $valueObject.PSObject.Properties[$change.Name] } else { $null }
            $existed = $null -ne $property
            $kind = if ($existed) { [string]$key.GetValueKind($change.Name) } else { [string]$change.Type }
            $snapshots.Add([PSCustomObject]@{
                Path = $change.Path; Name = $change.Name; Existed = $existed
                Value = $(if ($existed) { $property.Value } else { $null }); Type = $kind
            })
        }
        $diagTrack = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction SilentlyContinue
        $backup = [PSCustomObject]@{
            Timestamp = [DateTimeOffset]::Now.ToString('o')
            Registry = $snapshots.ToArray()
            DiagTrack = $(if ($diagTrack) { [PSCustomObject]@{ Exists = $true; StartMode = [string]$diagTrack.StartMode; State = [string]$diagTrack.State } } else { [PSCustomObject]@{ Exists = $false; StartMode = ''; State = '' } })
        }
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        $backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:PrivacyBackupPath -Encoding UTF8
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Set-PrivacyProfile {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskPrivacy') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        Save-PrivacyBackupIfNeeded
        $privacyChanges = @(Get-PrivacyRegistryChanges)
        $privacyProcessed = 0
        Update-RemnexaProgress $remnexaWorkProgress -Total ($privacyChanges.Count + 1)
        foreach ($change in $privacyChanges) {
            New-Item -Path $change.Path -Force | Out-Null
            New-ItemProperty -LiteralPath $change.Path -Name $change.Name -Value $change.Value -PropertyType $change.Type -Force | Out-Null
            $privacyProcessed++
            Update-RemnexaProgress $remnexaWorkProgress -Completed $privacyProcessed -CurrentItem $change.Path
        }
        $service = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne 'Stopped') { Stop-Service -Name 'DiagTrack' -Force -ErrorAction Stop }
            Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
        }
        Update-RemnexaProgress $remnexaWorkProgress -Completed ($privacyChanges.Count + 1) -CurrentItem 'DiagTrack'
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Restore-PrivacyProfile {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskRestore') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (-not (Test-Path -LiteralPath $script:PrivacyBackupPath)) { Add-RemnexaProgressNotice -Level Warning; return $false }
        $backup = Get-Content -LiteralPath $script:PrivacyBackupPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
        $registryChanges = @(Get-PrivacyRegistryChanges)
        [void](Assert-RemnexaPrivacyBackup -Backup $backup -AllowedChanges $registryChanges)
        $restoreProcessed = 0
        Update-RemnexaProgress $remnexaWorkProgress -Total (@($backup.Registry).Count + 1)
        foreach ($snapshot in @($backup.Registry)) {
            if ([bool]$snapshot.Existed) {
                New-Item -Path ([string]$snapshot.Path) -Force | Out-Null
                New-ItemProperty -LiteralPath ([string]$snapshot.Path) -Name ([string]$snapshot.Name) -Value $snapshot.Value -PropertyType ([string]$snapshot.Type) -Force | Out-Null
            }
            elseif (Test-Path -LiteralPath ([string]$snapshot.Path)) {
                Remove-ItemProperty -LiteralPath ([string]$snapshot.Path) -Name ([string]$snapshot.Name) -ErrorAction SilentlyContinue
            }
            $restoreProcessed++
            Update-RemnexaProgress $remnexaWorkProgress -Completed $restoreProcessed -CurrentItem ([string]$snapshot.Path)
        }
        if ([bool]$backup.DiagTrack.Exists) {
            $startupType = switch ([string]$backup.DiagTrack.StartMode) { 'Auto' { 'Automatic' }; 'Manual' { 'Manual' }; 'Disabled' { 'Disabled' }; default { 'Manual' } }
            Set-Service -Name 'DiagTrack' -StartupType $startupType -ErrorAction SilentlyContinue
            if ([string]$backup.DiagTrack.State -eq 'Running') { Start-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue }
        }
        Remove-Item -LiteralPath $script:PrivacyBackupPath -Force -ErrorAction Stop
        Update-RemnexaProgress $remnexaWorkProgress -Completed (@($backup.Registry).Count + 1) -CurrentItem 'DiagTrack'
        return $true
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Invoke-PrivacyMenu {
    if (-not (Request-ElevationForTool -Mode Privacy)) { return 'menu' }
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'PrivacyTitle') -ForegroundColor White
    Write-Host (T 'PrivacyDescription') -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Service: DiagTrack -> Stopped / Disabled' -ForegroundColor DarkGray
    foreach ($change in @(Get-PrivacyRegistryChanges)) {
        Write-Host ('  {0}\{1} = {2}' -f $change.Path, $change.Name, $change.Value) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ('  [1] ' + (T 'PrivacyApply'))
    Write-Host ('  [2] ' + (T 'PrivacyRestore'))
    Write-Host ('  [3] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -eq '0') { return 'exit' }
        if ($answer -eq '3') { return 'menu' }
        if ($answer -eq '1') {
            $confirmation = Read-ExplicitConfirmation -WarningText (T 'PrivacyDescription') -ActionText (T 'PrivacyApply')
            if ($confirmation -ne 'start') { return $confirmation }
            if (-not (New-RestorePointIfPossible -ProgramName (T 'PrivacyTitle'))) { return 'menu' }
            try {
                Set-PrivacyProfile
                Write-Status (T 'PrivacyDone') 'Success'
                $logPath = Save-ToolLog -Action 'PrivacyProfileApplied' -Data (Get-PrivacyRegistryChanges)
                if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
            }
            catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
            break
        }
        if ($answer -eq '2') {
            if (-not (Test-Path -LiteralPath $script:PrivacyBackupPath)) {
                Write-Status (T 'PrivacyNoBackup') 'Warning'
                continue
            }
            $confirmation = Read-ExplicitConfirmation -WarningText (T 'PrivacyRestore') -ActionText (T 'PrivacyRestore')
            if ($confirmation -ne 'start') { return $confirmation }
            try {
                if (Restore-PrivacyProfile) {
                    Write-Status (T 'PrivacyRestored') 'Success'
                    $logPath = Save-ToolLog -Action 'PrivacyProfileRestored' -Data $null
                    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
                }
            }
            catch { Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error' }
            break
        }
        Write-Status (T 'InvalidPrivacyChoice') 'Warning'
    }
    Write-Host ('  [1] ' + (T 'BackPreviousMenu'))
    Write-Host ('  [0] ' + (T 'Main0'))
    return (Read-MainOrExitChoice)
}

function Invoke-LogCleanupMenu {
    :logCleanupLoop while ($true) {
    Clear-RemnexaScreen
    Show-BrandHeader
    Write-Host (T 'LogsTitle') -ForegroundColor White
    Write-Host ''

    $logFiles = @()
    if (Test-Path -LiteralPath $script:LogRoot) {
        $logFiles = @(Get-ChildItem -LiteralPath $script:LogRoot -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @('.json', '.log')
        })
    }

    if ($logFiles.Count -eq 0) {
        Write-Host (T 'LogsNone') -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ('  [1] ' + (T 'BackMain'))
        Write-Host ('  [0] ' + (T 'Main0'))
        return (Read-MainOrExitChoice)
    }

    Write-Host (T 'LogsCount' @($logFiles.Count))
    Write-Host ('  [1] ' + (T 'LogsDelete')) -ForegroundColor Yellow
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))

    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -in @('0', 'exit')) { return 'exit' }
        if ($answer -in @('2', 'menu', 'm')) { return 'menu' }
        if ($answer -eq '1') {
            $deleted = 0
            $failed = 0
            $logProgress = New-RemnexaProgress -Activity (T 'LogsDelete') -Total $logFiles.Count -Unit (Get-RemnexaProgressText 'ProgressUnitFiles')
            foreach ($file in $logFiles) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $deleted++
                }
                catch { $failed++ }
                Update-RemnexaProgress $logProgress -Completed ($deleted + $failed) -CurrentItem $file.Name
            }
            Complete-RemnexaProgress $logProgress -Outcome $(if ($failed) { 'Warning' } else { 'Completed' })
            Write-Status (T 'LogsDeleted' @($deleted)) 'Success'
            if ($failed -gt 0) { Write-Status (T 'LogsFailed' @($failed)) 'Warning' }
            Write-Host ''
            Write-Host ('  [1] ' + (T 'LogsTitle'))
            Write-Host ('  [0] ' + (T 'BackPreviousMenu'))
            while ($true) {
                $afterChoice = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
                if ($afterChoice -eq '1') { continue logCleanupLoop }
                if ($afterChoice -eq '0') { return 'menu' }
                Write-Status (T 'InvalidPost') 'Warning'
            }
        }
        Write-Status (T 'InvalidLogs') 'Warning'
    }
    }
}

function Get-StableIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return -join @($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    }
    finally { $sha.Dispose() }
}

function Test-StartupItemProtected {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Command,
        [AllowEmptyString()][string]$TaskPath = ''
    )

    if ($TaskPath.StartsWith('\Microsoft\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($null -ne (Get-ProtectedComponentMatch -Program $null -SearchName ($Name + ' | ' + $Command))) { return $true }
    if ($Command -match '(?i)\\Windows\\System32\\(SecurityHealth|UsoClient|MusNotification|MoUsoCoreWorker|WaaSMedic|smartscreen)') { return $true }
    return $false
}

function Get-StartupItems {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskStartup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        $items = New-Object System.Collections.Generic.List[object]
        $registryLocations = @(
            [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Benutzer'; RequiresAdmin = $false },
            [PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Benutzer (einmalig)'; RequiresAdmin = $false },
            [PSCustomObject]@{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Computer'; RequiresAdmin = $true },
            [PSCustomObject]@{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Computer (einmalig)'; RequiresAdmin = $true },
            [PSCustomObject]@{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Computer (32-Bit)'; RequiresAdmin = $true },
            [PSCustomObject]@{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Computer (32-Bit, einmalig)'; RequiresAdmin = $true }
        )

        foreach ($location in $registryLocations) {
            try {
                if (-not (Test-Path -LiteralPath $location.Path)) { continue }
                $key = Get-Item -LiteralPath $location.Path -ErrorAction Stop
                foreach ($valueName in @($key.GetValueNames())) {
                    if ([string]::IsNullOrWhiteSpace($valueName)) { continue }
                    $value = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    $command = if ($value -is [Array]) { $value -join '; ' } else { [string]$value }
                    $id = Get-StableIdentifier -Value ('Registry|' + $location.Path + '|' + $valueName)
                    $items.Add([PSCustomObject]@{
                        Id = $id; Name = $valueName; SourceType = 'Registry'; Scope = $location.Scope
                        Command = $command; Location = $location.Path; RequiresAdmin = [bool]$location.RequiresAdmin
                        IsProtected = (Test-StartupItemProtected -Name $valueName -Command $command)
                        RegistryPath = $location.Path; ValueName = $valueName; Value = $value
                        ValueKind = $key.GetValueKind($valueName).ToString(); FilePath = ''; TaskName = ''; TaskPath = ''
                    })
                }
            }
            catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }
        }

        $startupFolders = @(
            [PSCustomObject]@{ Path = [Environment]::GetFolderPath('Startup'); Scope = 'Benutzer'; RequiresAdmin = $false },
            [PSCustomObject]@{ Path = [Environment]::GetFolderPath('CommonStartup'); Scope = 'Alle Benutzer'; RequiresAdmin = $true }
        )
        foreach ($folder in $startupFolders) {
            try {
                if ([string]::IsNullOrWhiteSpace($folder.Path) -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
                foreach ($file in @(Get-ChildItem -LiteralPath $folder.Path -File -Force -ErrorAction Stop)) {
                    if ($file.Name -ieq 'desktop.ini') { continue }
                    $id = Get-StableIdentifier -Value ('File|' + $file.FullName)
                    $items.Add([PSCustomObject]@{
                        Id = $id; Name = $file.BaseName; SourceType = 'StartupFolder'; Scope = $folder.Scope
                        Command = $file.FullName; Location = $folder.Path; RequiresAdmin = [bool]$folder.RequiresAdmin
                        IsProtected = (Test-StartupItemProtected -Name $file.BaseName -Command $file.FullName)
                        RegistryPath = ''; ValueName = ''; Value = $null; ValueKind = ''; FilePath = $file.FullName
                        TaskName = ''; TaskPath = ''
                    })
                }
            }
            catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }
        }

        try {
            if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
                foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
                    $_.State -ne 'Disabled' -and @($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -gt 0
                })) {
                    $command = @($task.Actions | ForEach-Object { (($_.Execute + ' ' + $_.Arguments).Trim()) }) -join ' | '
                    $id = Get-StableIdentifier -Value ('Task|' + $task.TaskPath + '|' + $task.TaskName)
                    $items.Add([PSCustomObject]@{
                        Id = $id; Name = $task.TaskName; SourceType = 'ScheduledTask'; Scope = 'Geplante Aufgabe'
                        Command = $command; Location = $task.TaskPath; RequiresAdmin = $true
                        IsProtected = (Test-StartupItemProtected -Name $task.TaskName -Command $command -TaskPath $task.TaskPath)
                        RegistryPath = ''; ValueName = ''; Value = $null; ValueKind = ''; FilePath = ''
                        TaskName = $task.TaskName; TaskPath = $task.TaskPath
                    })
                }
            }
        }
        catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Inventory' }

        return @($items | Sort-Object Name, SourceType, Scope)
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Save-StartupManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [AllowEmptyString()][string]$Path = ''
    )

    New-Item -ItemType Directory -Path $script:StartupBackupRoot -Force | Out-Null
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $script:StartupBackupRoot ([string]$Manifest.BackupId + '.json')
    }
    $copy = $Manifest.PSObject.Copy()
    if ($copy.PSObject.Properties['_ManifestPath']) { $copy.PSObject.Properties.Remove('_ManifestPath') }
    $copy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Add-StartupHistory {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][bool]$Succeeded,
        [AllowEmptyString()][string]$Details = ''
    )

    try {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
        [PSCustomObject]@{
            Timestamp = [DateTimeOffset]::Now.ToString('o')
            Action = $Action
            Name = [string]$Item.Name
            SourceType = [string]$Item.SourceType
            Location = [string]$Item.Location
            Command = [string]$Item.Command
            Succeeded = $Succeeded
            Details = $Details
        } | ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $script:StartupHistoryPath -Encoding UTF8
    }
    catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/History' }
}

function Get-StartupHistory {
    if (-not (Test-Path -LiteralPath $script:StartupHistoryPath)) { return @() }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $script:StartupHistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return @($entries | Sort-Object Timestamp -Descending)
}

function Get-StartupBackups {
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskStartup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (-not (Test-Path -LiteralPath $script:StartupBackupRoot)) { return @() }
        $backups = New-Object System.Collections.Generic.List[object]
        foreach ($file in @(Get-ChildItem -LiteralPath $script:StartupBackupRoot -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            try {
                $entry = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([bool](Get-OptionalPropertyValue -InputObject $entry -PropertyName 'Active')) {
                    $entry | Add-Member -NotePropertyName '_ManifestPath' -NotePropertyValue $file.FullName -Force
                    $backups.Add($entry)
                }
            }
            catch { Write-LogEntry -Message $_.Exception.Message -Level 'Warning' -Component 'Startup/Backup' }
        }
        return @($backups | Sort-Object DisabledAt -Descending)
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Disable-StartupItem {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [switch]$SkipConfirmation
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskStartup') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if ([bool]$Item.IsProtected) {
            Write-Status (T 'StartupProtected') 'Warning'
            return $false
        }
        if (-not $SkipConfirmation) {
            $choice = Read-ExplicitConfirmation -WarningText (T 'StartupConfirm' @([string]$Item.Name)) -ActionText (T 'StartupConfirm' @([string]$Item.Name))
            if ($choice -ne 'start') { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Cancelled; return $false }
        }
        if ([bool]$Item.RequiresAdmin -and -not (Test-IsAdministrator)) {
            [void](Request-ElevationForTool -Mode Startup -ItemId ([string]$Item.Id))
            return $false
        }

        $backupId = [Guid]::NewGuid().ToString('N')
        $backupPath = ''
        $manifest = [PSCustomObject]@{
            BackupId = $backupId; Active = $true; DisabledAt = [DateTimeOffset]::Now.ToString('o'); RestoredAt = ''
            Name = [string]$Item.Name; SourceType = [string]$Item.SourceType; Scope = [string]$Item.Scope
            Command = [string]$Item.Command; Location = [string]$Item.Location; RequiresAdmin = [bool]$Item.RequiresAdmin
            RegistryPath = [string]$Item.RegistryPath; ValueName = [string]$Item.ValueName
            Value = $Item.Value; ValueKind = [string]$Item.ValueKind; OriginalFilePath = [string]$Item.FilePath
            BackupFilePath = ''; TaskName = [string]$Item.TaskName; TaskPath = [string]$Item.TaskPath
        }

        try {
            if ($Item.SourceType -eq 'StartupFolder') {
                $fileBackupRoot = Join-Path (Join-Path $script:StartupBackupRoot 'Files') $backupId
                New-Item -ItemType Directory -Path $fileBackupRoot -Force | Out-Null
                $backupPath = Join-Path $fileBackupRoot ([IO.Path]::GetFileName([string]$Item.FilePath))
                $manifest.BackupFilePath = $backupPath
            }
            $manifestPath = Save-StartupManifest -Manifest $manifest

            switch ([string]$Item.SourceType) {
                'Registry' {
                    Remove-ItemProperty -LiteralPath ([string]$Item.RegistryPath) -Name ([string]$Item.ValueName) -ErrorAction Stop
                }
                'StartupFolder' {
                    Move-Item -LiteralPath ([string]$Item.FilePath) -Destination $backupPath -ErrorAction Stop
                }
                'ScheduledTask' {
                    Disable-ScheduledTask -TaskName ([string]$Item.TaskName) -TaskPath ([string]$Item.TaskPath) -ErrorAction Stop | Out-Null
                }
                default { throw "Unbekannter Autostart-Typ: $($Item.SourceType)" }
            }

            Add-StartupHistory -Action 'Disabled' -Item $Item -Succeeded $true -Details $manifestPath
            [void](Save-ToolLog -Action 'StartupDisabled' -Data $manifest)
            Write-Status (T 'StartupDisabled' @([string]$Item.Name)) 'Success'
            return $true
        }
        catch {
            $manifest.Active = $false
            $manifest.RestoredAt = [DateTimeOffset]::Now.ToString('o')
            try { [void](Save-StartupManifest -Manifest $manifest) } catch { }
            Add-StartupHistory -Action 'DisableFailed' -Item $Item -Succeeded $false -Details $_.Exception.Message
            Write-Status (T 'StartupActionFailed' @($_.Exception.Message)) 'Error'
            return $false
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Restore-StartupItem {
    param(
        [Parameter(Mandatory = $true)][object]$Backup,
        [switch]$SkipConfirmation
    )
    $remnexaWorkProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskRestore') -Unit (Get-RemnexaProgressText 'ProgressUnitItems')
    try {
        if (-not $SkipConfirmation) {
            $choice = Read-ExplicitConfirmation -WarningText (T 'StartupRestoreConfirm' @([string]$Backup.Name)) -ActionText (T 'StartupRestoreConfirm' @([string]$Backup.Name))
            if ($choice -ne 'start') { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Cancelled; return $false }
        }
        if ([bool]$Backup.RequiresAdmin -and -not (Test-IsAdministrator)) {
            [void](Request-ElevationForTool -Mode Startup -ItemId ('restore:' + [string]$Backup.BackupId))
            return $false
        }

        try {
            switch ([string]$Backup.SourceType) {
                'Registry' {
                    if (-not (Test-Path -LiteralPath ([string]$Backup.RegistryPath))) {
                        New-Item -Path ([string]$Backup.RegistryPath) -Force | Out-Null
                    }
                    $value = $Backup.Value
                    switch ([string]$Backup.ValueKind) {
                        'Binary' { $value = [byte[]]@($Backup.Value) }
                        'DWord' { $value = [int]$Backup.Value }
                        'QWord' { $value = [long]$Backup.Value }
                        'MultiString' { $value = [string[]]@($Backup.Value) }
                        default { $value = [string]$Backup.Value }
                    }
                    New-ItemProperty -LiteralPath ([string]$Backup.RegistryPath) -Name ([string]$Backup.ValueName) -Value $value -PropertyType ([string]$Backup.ValueKind) -Force -ErrorAction Stop | Out-Null
                }
                'StartupFolder' {
                    if (-not (Test-Path -LiteralPath ([string]$Backup.BackupFilePath))) { throw 'Die gesicherte Autostart-Datei fehlt.' }
                    if (Test-Path -LiteralPath ([string]$Backup.OriginalFilePath)) { throw 'Am ursprünglichen Ort existiert bereits eine Datei mit demselben Namen.' }
                    $parent = Split-Path -Parent ([string]$Backup.OriginalFilePath)
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                    Move-Item -LiteralPath ([string]$Backup.BackupFilePath) -Destination ([string]$Backup.OriginalFilePath) -ErrorAction Stop
                }
                'ScheduledTask' {
                    Enable-ScheduledTask -TaskName ([string]$Backup.TaskName) -TaskPath ([string]$Backup.TaskPath) -ErrorAction Stop | Out-Null
                }
                default { throw "Unbekannter Autostart-Typ: $($Backup.SourceType)" }
            }

            $Backup.Active = $false
            $Backup.RestoredAt = [DateTimeOffset]::Now.ToString('o')
            [void](Save-StartupManifest -Manifest $Backup -Path ([string]$Backup._ManifestPath))
            Add-StartupHistory -Action 'Restored' -Item $Backup -Succeeded $true -Details ([string]$Backup.BackupId)
            [void](Save-ToolLog -Action 'StartupRestored' -Data $Backup)
            Write-Status (T 'StartupRestored' @([string]$Backup.Name)) 'Success'
            return $true
        }
        catch {
            Add-StartupHistory -Action 'RestoreFailed' -Item $Backup -Succeeded $false -Details $_.Exception.Message
            Write-Status (T 'StartupActionFailed' @($_.Exception.Message)) 'Error'
            return $false
        }
    }
    catch { Complete-RemnexaProgress $remnexaWorkProgress -Outcome Failed; throw }
    finally { if ($remnexaWorkProgress.Outcome -eq 'Running') { Complete-RemnexaProgress $remnexaWorkProgress } }
}

function Show-StartupHistoryScreen {
    Clear-RemnexaScreen
    Show-BrandHeader -Section (T 'StartupTitle')
    $history = @(Get-StartupHistory)
    if ($history.Count -eq 0) {
        Write-Host (T 'StartupHistoryNone') -ForegroundColor DarkGray
    }
    else {
        $number = 1
        foreach ($entry in @($history | Select-Object -First 100)) {
            $when = Format-HistoryTimestamp -Timestamp ([string]$entry.Timestamp)
            $state = if ([bool]$entry.Succeeded) { 'OK' } else { 'FEHLER' }
            Write-Host ('  [{0}] {1} | {2} | {3} | {4}' -f $number, $when, $entry.Action, $entry.Name, $state)
            $number++
        }
    }
    Write-Host ''
    Write-Host ('  [0] ' + (T 'BackHome'))
    while ((Read-RemnexaInput (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
}

function Invoke-StartupList {
    $page = 0
    $pageNotice = ''
    :startupListLoop while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader -Section (T 'StartupTitle')
        Write-Host (T 'StartupDescription') -ForegroundColor DarkGray
        Write-Host ''
        $items = @(Get-StartupItems)
        if ($items.Count -eq 0) {
            Write-Host (T 'StartupNone') -ForegroundColor DarkGray
            Write-Host ('  [0] ' + (T 'BackHome'))
            while ((Read-RemnexaInput (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
            return
        }

        $pageSize = 18
        :startupPageLoop while ($true) {
            Clear-RemnexaScreen
            Show-BrandHeader -Section (T 'StartupTitle')
            $pageState = Get-RemnexaPageState -ItemCount $items.Count -PageSize $pageSize -PageIndex $page
            $pageCount = $pageState.PageCount
            $page = $pageState.PageIndex
            $start = $page * $pageSize
            $end = [Math]::Min($start + $pageSize - 1, $items.Count - 1)
            Write-Host (T 'PageLabel' @(($page + 1), $pageCount, $items.Count)) -ForegroundColor DarkGray
            Write-Host ''
            for ($index = $start; $index -le $end; $index++) {
                $item = $items[$index]
                $flag = if ($item.IsProtected) { ' | geschützt' } elseif ($item.RequiresAdmin) { ' | Admin' } else { '' }
                Write-Host ('  [{0}] {1} | {2} | {3}{4}' -f ($index + 1), $item.Name, $item.SourceType, $item.Scope, $flag)
                Write-Host ('       ' + $item.Command) -ForegroundColor DarkGray
            }
            Write-Host ''
            Write-Host (T 'StartupSelect') -ForegroundColor DarkGray
            Show-PageNavigation -PageState $pageState
            Write-Host ('  [0] ' + (T 'BackPreviousMenu')) -ForegroundColor DarkGray
            if ($pageNotice) { Write-Status (T $pageNotice) 'Warning'; $pageNotice = '' }
            $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
            if ($answer -eq '0') { return }
            if ($answer -eq '-1') {
                if ($pageState.HasNext) { $page++ } else { $pageNotice = 'PageNextUnavailable' }
                continue startupPageLoop
            }
            if ($answer -eq '-2') {
                if ($pageState.HasPrevious) { $page-- } else { $pageNotice = 'PagePreviousUnavailable' }
                continue startupPageLoop
            }
            $number = 0
            if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $items.Count) {
                $selected = $items[$number - 1]
                if (Disable-StartupItem -Item $selected) { Start-Sleep -Milliseconds 900 }
                continue startupListLoop
            }
            Write-Status (T 'StartupInvalid') 'Warning'
            Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-StartupRestoreList {
    :startupRestoreLoop while ($true) {
    Clear-RemnexaScreen
    Show-BrandHeader -Section (T 'StartupTitle')
    $backups = @(Get-StartupBackups)
    if ($backups.Count -eq 0) {
        Write-Host (T 'StartupBackupsNone') -ForegroundColor DarkGray
        Write-Host ('  [0] ' + (T 'BackHome'))
        while ((Read-RemnexaInput (T 'SelectPrompt')).Trim() -ne '0') { Write-Status (T 'StartupInvalid') 'Warning' }
        return
    }
    for ($index = 0; $index -lt $backups.Count; $index++) {
        $when = Format-HistoryTimestamp -Timestamp ([string]$backups[$index].DisabledAt)
        Write-Host ('  [{0}] {1} | {2} | {3}' -f ($index + 1), $when, $backups[$index].Name, $backups[$index].SourceType)
    }
    Write-Host ('  [0] ' + (T 'BackHome'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        if ($answer -eq '0') { return }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $backups.Count) {
            [void](Restore-StartupItem -Backup $backups[$number - 1])
            Start-Sleep -Milliseconds 900
            continue startupRestoreLoop
        }
        Write-Status (T 'StartupInvalid') 'Warning'
    }
    }
}

function Invoke-StartupMenu {
    param([AllowEmptyString()][string]$InitialActionId = '')

    if (-not [string]::IsNullOrWhiteSpace($InitialActionId)) {
        if ($InitialActionId.StartsWith('restore:', [StringComparison]::OrdinalIgnoreCase)) {
            $backupId = $InitialActionId.Substring(8)
            $backup = @(Get-StartupBackups | Where-Object { $_.BackupId -eq $backupId } | Select-Object -First 1)
            if ($backup.Count -eq 1) { [void](Restore-StartupItem -Backup $backup[0] -SkipConfirmation) }
        }
        else {
            $item = @(Get-StartupItems | Where-Object { $_.Id -eq $InitialActionId } | Select-Object -First 1)
            if ($item.Count -eq 1) { [void](Disable-StartupItem -Item $item[0] -SkipConfirmation) }
        }
    }

    :startupMenuLoop while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader -Section (T 'StartupTitle')
        Write-Host (T 'StartupDescription') -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ('  [1] ' + (T 'Startup1'))
        Write-Host ('  [2] ' + (T 'Startup2'))
        Write-Host ('  [3] ' + (T 'Startup3'))
        Write-Host ('  [0] ' + (T 'BackHome'))
        $choice = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        switch ($choice) {
            '0' { return 'menu' }
            '1' { Invoke-StartupList; continue startupMenuLoop }
            '2' { Invoke-StartupRestoreList; continue startupMenuLoop }
            '3' { Show-StartupHistoryScreen; continue startupMenuLoop }
            default { Write-Status (T 'InvalidStartupMenu') 'Warning'; Start-Sleep -Milliseconds 700 }
        }
    }
}

function Invoke-ActiveServicesScreen {
    $servicesProgress = New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskServices')
    try {
        $allServices = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
            Where-Object { $_.State -eq 'Running' } |
            Sort-Object DisplayName, Name)
        Complete-RemnexaProgress $servicesProgress
    }
    catch {
        Complete-RemnexaProgress $servicesProgress -Outcome Failed
        Write-Status (T 'ServicesReadError' @($_.Exception.Message)) 'Error'
        return 'menu'
    }

    $filter = ''
    $page = 0
    $pageSize = 20
    $pageNotice = ''
    while ($true) {
        $services = if ([string]::IsNullOrWhiteSpace($filter)) {
            $allServices
        }
        else {
            @($allServices | Where-Object { $_.DisplayName -like ('*' + $filter + '*') -or $_.Name -like ('*' + $filter + '*') })
        }
        $pageState = Get-RemnexaPageState -ItemCount $services.Count -PageSize $pageSize -PageIndex $page
        $pageCount = $pageState.PageCount
        $page = $pageState.PageIndex
        Clear-RemnexaScreen
        Show-BrandHeader -Section (T 'ServicesTitle')
        Write-Host (T 'ServicesDescription') -ForegroundColor DarkGray
        if ($filter) { Write-Host (T 'FilterLabel' @($filter)) -ForegroundColor Yellow }
        Write-Host (T 'ServicesPage' @(($page + 1), $pageCount, $services.Count)) -ForegroundColor DarkGray
        Write-Host ''
        if ($services.Count -eq 0) {
            Write-Host (T 'ServicesNone') -ForegroundColor DarkGray
        }
        else {
            $start = $page * $pageSize
            $end = [Math]::Min($start + $pageSize - 1, $services.Count - 1)
            for ($index = $start; $index -le $end; $index++) {
                $service = $services[$index]
                Write-Host ('  [{0}] {1} [{2}] | Start: {3} | PID: {4}' -f ($index + 1), $service.DisplayName, $service.Name, $service.StartMode, $service.ProcessId)
            }
        }
        Write-Host ''
        Write-Host (T 'ServicesCommands') -ForegroundColor DarkGray
        Show-PageNavigation -PageState $pageState -NextCommand '1' -PreviousCommand '2'
        if ($pageNotice) { Write-Status (T $pageNotice) 'Warning'; $pageNotice = '' }
        $choice = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        switch ($choice) {
            '0' { return 'menu' }
            '1' { if ($pageState.HasNext) { $page++ } else { $pageNotice = 'PageNextUnavailable' } }
            '2' { if ($pageState.HasPrevious) { $page-- } else { $pageNotice = 'PagePreviousUnavailable' } }
            '3' { $filter = (Read-RemnexaInput (T 'SearchPrompt')).Trim(); $page = 0 }
            '4' { $filter = ''; $page = 0 }
            default { Write-Status (T 'StartupInvalid') 'Warning'; Start-Sleep -Milliseconds 700 }
        }
    }
}

function Read-RemovalConfirmation {
    param([Parameter(Mandatory = $true)][string]$ProgramName)
    Write-Host ''
    Write-Host (T 'Selected' @($ProgramName)) -ForegroundColor White
    Write-Host (T 'RemovalWarning') -ForegroundColor Yellow
    if ($IncludeUserFiles) {
        Write-Host (T 'PersonalWarning') -ForegroundColor Red
    }
    Write-Host ('  [1] ' + (T 'ConfirmStart'))
    Write-Host ('  [2] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))

    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -in @('1', 'ent')) { return 'start' }
        if ($answer -in @('2', 'menu', 'm')) { return 'menu' }
        if ($answer -in @('0', 'exit')) { return 'exit' }
        Write-Status (T 'InvalidConfirm') 'Warning'
    }
}

function Read-AppxRemovalScope {
    Write-Host ''
    Write-Host (T 'AppxScopeQuestion') -ForegroundColor White
    Write-Host ('  [1] ' + (T 'AppxCurrentOnly'))
    Write-Host ('  [2] ' + (T 'AppxProvisioned')) -ForegroundColor Yellow
    Write-Host ('  [3] ' + (T 'BackMain'))
    Write-Host ('  [0] ' + (T 'Main0'))
    while ($true) {
        $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
        if ($answer -eq '1') { return 'current' }
        if ($answer -eq '2') { return 'provisioned' }
        if ($answer -eq '3') { return 'menu' }
        if ($answer -eq '0') { return 'exit' }
        Write-Status (T 'InvalidAppxScope') 'Warning'
    }
}

function Invoke-RemovalOperationCore {
    param(
        [Parameter(Mandatory = $true)][string]$OperationName,
        [bool]$OperationResidualOnly,
        [bool]$OperationDryRun,
        [AllowNull()][object]$PreselectedProgram,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$PreloadedPrograms,
        [bool]$SkipConfirmation,
        [bool]$ContinueAfterElevation,
        [AllowEmptyString()][string]$ExpectedRegistryPath,
        [AllowEmptyString()][string]$ExpectedPackageFullName
    )

    # Lokale Variablen gleichen Namens sorgen dafür, dass Protokoll- und Hilfsfunktionen
    # innerhalb dieses Durchlaufs die tatsächlich gewählten Optionen sehen.
    $Name = $OperationName.Trim()
    $script:LastRunLogPath = ''
    $script:LastRunSummary = $null
    $ResidualOnly = $OperationResidualOnly
    $DryRun = $OperationDryRun
    $programs = @($PreloadedPrograms)
    $selected = $PreselectedProgram
    $removeProvisionedForRun = [bool]$RemoveProvisionedAppx
    $antivirusBeforeResults = @()
    $antivirusAfterResults = @()

    Set-OperationProgress -Percent 1 -Status (T 'ProgressPrepare')

    if ((-not [string]::IsNullOrWhiteSpace($ExpectedRegistryPath)) -or
        (-not [string]::IsNullOrWhiteSpace($ExpectedPackageFullName))) {
        Set-OperationProgress -Percent 5 -Status (T 'ProgressRecheck')
        if ($programs.Count -eq 0) { $programs = @(Get-InstalledPrograms) }

        $exactMatches = @($programs | Where-Object {
            ((-not [string]::IsNullOrWhiteSpace($ExpectedRegistryPath)) -and $_.RegistryPath -eq $ExpectedRegistryPath) -or
            ((-not [string]::IsNullOrWhiteSpace($ExpectedPackageFullName)) -and $_.PackageFullName -eq $ExpectedPackageFullName)
        })
        if ($exactMatches.Count -ne 1) {
            throw 'Die zuvor ausgewählte Anwendung konnte nach der Administratorfreigabe nicht eindeutig wiedergefunden werden. Es wurde nichts entfernt.'
        }
        $selected = $exactMatches[0]
        $Name = $selected.DisplayName
    }

    if ($null -eq $selected -and -not $ResidualOnly) {
        if ($programs.Count -eq 0) {
            Set-OperationProgress -Percent 5 -Status (T 'ProgressInventory')
            $programs = @(Get-InstalledPrograms)
        }
        $candidates = @(Find-ProgramCandidates -Programs $programs -SearchName $Name)

        if ($candidates.Count -gt 0) {
            $selected = Select-Program -Candidates $candidates
            if ($null -eq $selected) {
                Write-Status (T 'SelectionCancelled') 'Warning'
                Complete-OperationProgress
                return $false
            }
            $Name = $selected.DisplayName
        }
        else {
            Write-Status (T 'NoProgramFound' @($Name)) 'Warning'
            Write-Host (T 'ResidualQuestion') -ForegroundColor White
            Write-Host ('  [1] ' + (T 'YesResidual'))
            Write-Host ('  [2] ' + (T 'BackMain'))
            Write-Host ('  [0] ' + (T 'Main0'))
            while ($true) {
                $answer = (Read-RemnexaInput (T 'SelectPrompt') -ExitOptionAlreadyShown).Trim()
                if ($answer -in @('1', 'j', 'ja', 'y', 'yes')) {
                    $ResidualOnly = $true
                    break
                }
                if ($answer -in @('2', 'menu', 'm')) {
                    Complete-OperationProgress
                    return $false
                }
                if ($answer -in @('0', 'exit')) {
                    $script:ExitRequested = $true
                    Complete-OperationProgress
                    return $false
                }
                Write-Status (T 'InvalidConfirm') 'Warning'
            }
        }
    }

    if (-not $DryRun -and -not (Confirm-ProtectedComponentOverride -Program $selected -SearchName $Name)) {
        Write-Status (T 'SelectionCancelled') 'Warning'
        Complete-OperationProgress
        return $false
    }

    Set-OperationProgress -Percent 10 -Status (T 'ProgressIdentity')
    $identity = Get-IdentityInfo -SearchName $Name -Program $selected
    Write-Status (T 'SafeTerms' @(($identity.Aliases -join ', ')))
    Write-Status (T 'DeepSearch')
    Set-OperationProgress -Percent 15 -Status (T 'ProgressSearch')
    $traces = @(Find-AllTraces -Identity $identity -Program $selected -WithUserFiles ([bool]$IncludeUserFiles))
    $initialTraceCount = $traces.Count
    Set-OperationProgress -Percent 30 -Status (T 'ProgressPreview')
    Show-TraceSummary -Traces $traces -ShowAll

    if ($DryRun) {
        Write-Status (T 'DryRunDone') 'Success'
        $logPath = Save-RunLog -Program $selected -SearchName $Name -Traces $traces -Result $null
        $script:LastRunLogPath = [string]$logPath
        if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
        $script:LastRunSummary = [PSCustomObject]@{ Before = $initialTraceCount; Found = $initialTraceCount; Removed = 0; Failed = 0; Remaining = $initialTraceCount; Integrity = $null }
        Set-OperationProgress -Percent 100 -Status (T 'ProgressDryDone')
        Complete-OperationProgress
        return $true
    }

    $displayName = if ($null -ne $selected) { $selected.DisplayName } else { T 'ResidualSuffix' @($Name) }
    if (-not $SkipConfirmation) {
        if ($null -ne $selected -and $selected.Type -eq 'Appx') {
            $scope = Read-AppxRemovalScope
            if ($scope -eq 'exit') {
                $script:ExitRequested = $true
                Complete-OperationProgress
                return $false
            }
            if ($scope -eq 'menu') {
                Complete-OperationProgress
                return $false
            }
            $removeProvisionedForRun = $scope -eq 'provisioned'
        }
        $confirmation = Read-RemovalConfirmation -ProgramName $displayName
        if ($confirmation -eq 'exit') {
            $script:ExitRequested = $true
            Complete-OperationProgress
            return $false
        }
        if ($confirmation -ne 'start') {
            Write-Status (T 'SelectionCancelled') 'Warning'
            Complete-OperationProgress
            return $false
        }
    }

    if (-not (Request-ElevationForRemoval -SearchName $Name -Program $selected -IsResidualOnly $ResidualOnly -ContinueSession $ContinueAfterElevation -ProtectedOverride ([bool]$OverrideProtectedComponent) -ProvisionedAppx $removeProvisionedForRun)) {
        Complete-OperationProgress
        return $false
    }

    Set-OperationProgress -Percent 35 -Status (T 'ProgressBackup')
    if (-not (New-RestorePointIfPossible -ProgramName $displayName)) {
        Complete-OperationProgress
        return $false
    }
    $freeBefore = Get-SystemDriveFreeBytes

    $antivirusBeforeResults = @(Invoke-ConfiguredAntivirusScan -Stage Before -Identity $identity -Traces $traces)

    if ($null -ne $selected) {
        Set-OperationProgress -Percent 40 -Status (T 'ProgressUninstall')
        Invoke-SelectedUninstall -Program $selected -RemoveProvisioned $removeProvisionedForRun
        Start-Sleep -Seconds 2
    }
    Set-OperationProgress -Percent 60 -Status (T 'ProgressUninstallDone')

    # Nach der regulären Deinstallation erneut suchen, da manche Deinstaller neue Logs hinterlassen.
    Write-Status (T 'RescanMessage')
    Set-OperationProgress -Percent 65 -Status (T 'ProgressRescan')
    $traces = @(Find-AllTraces -Identity $identity -Program $selected -WithUserFiles ([bool]$IncludeUserFiles))
    Set-OperationProgress -Percent 75 -Status (T 'ProgressRescanDone')
    Show-TraceSummary -Traces $traces -ShowAll
    $antivirusAfterResults = @(Invoke-ConfiguredAntivirusScan -Stage After -Identity $identity -Traces $traces)
    $deleteTraces = $false
    if ($traces.Count -gt 0 -and $script:InteractiveSession) {
        $deleteTraces = Read-TraceDeletionConfirmation -Traces $traces
    }
    if ($deleteTraces) {
        Set-OperationProgress -Percent 78 -Status (T 'ProgressRemove')
        $result = Remove-Traces -Traces $traces
    }
    else {
        $managed = @($traces | Where-Object { $_.Kind -in @('File', 'Directory') -and (Test-RemnexaWindowsManagedPath -Path $_.Target) } |
            ForEach-Object { [PSCustomObject]@{ Kind = $_.Kind; Target = $_.Target; Reason = 'WindowsManaged' } })
        $result = [PSCustomObject]@{ Removed = 0; Failed = @(); Skipped = $managed; CoveredByParent = 0 }
        if ($traces.Count -gt 0) { Write-Status (T 'KeepFoundTraces') 'Warning' }
    }
    Set-OperationProgress -Percent 88 -Status (T 'ProgressCleanupDone')
    Write-Status (T 'RemovedCount' @($result.Removed)) 'Success'
    if ($result.Skipped.Count -gt 0) { Write-Status (T 'ManagedTraceCount' @($result.Skipped.Count)) 'Warning' }
    if ($result.CoveredByParent -gt 0) { Write-Status (T 'TraceCoveredCount' @($result.CoveredByParent)) }

    if ($result.Failed.Count -gt 0) {
        Write-Status (T 'FailedCount' @($result.Failed.Count)) 'Warning'
        foreach ($failure in $result.Failed) { Write-Host ('  ' + $failure) -ForegroundColor Yellow }
    }

    Write-Status (T 'FinalCheck')
    Set-OperationProgress -Percent 92 -Status (T 'ProgressVerify')
    $remaining = @(Find-AllTraces -Identity $identity -Program $null -WithUserFiles ([bool]$IncludeUserFiles))
    $remaining = @($remaining | Where-Object {
        if ($_.Kind -eq 'RegistryKey' -and $null -ne $selected -and $_.Target -eq ($selected.RegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')) {
            return $false
        }
        return $true
    })

    $freeAfter = Get-SystemDriveFreeBytes
    $freedBytes = [int64]0
    if ($freeBefore -ge 0 -and $freeAfter -ge 0) {
        $difference = [int64]($freeAfter - $freeBefore)
        if ($difference -gt 0) {
            $freedBytes = $difference
            Write-Status (T 'StorageFreed' @((Format-ByteSize -Bytes $freedBytes))) 'Success'
        }
        else {
            Write-Status (T 'StorageUnclear') 'Warning'
        }
    }

    $integrityResult = $null
    $result | Add-Member -NotePropertyName FreedBytes -NotePropertyValue $freedBytes -Force
    $result | Add-Member -NotePropertyName ProvisionedAppxRemoved -NotePropertyValue ([int]$script:ProvisionedRemovedCount) -Force
    $result | Add-Member -NotePropertyName IntegrityCheck -NotePropertyValue $integrityResult -Force
    $result | Add-Member -NotePropertyName RemainingTraces -NotePropertyValue @($remaining) -Force
    $result | Add-Member -NotePropertyName AntivirusBefore -NotePropertyValue @($antivirusBeforeResults) -Force
    $result | Add-Member -NotePropertyName AntivirusAfter -NotePropertyValue @($antivirusAfterResults) -Force

    $logPath = Save-RunLog -Program $selected -SearchName $Name -Traces $traces -Result $result
    $script:LastRunLogPath = [string]$logPath
    if ($remaining.Count -eq 0 -and $result.Failed.Count -eq 0) {
        Write-Status (T 'FinishedClean') 'Success'
    }
    else {
        Write-Status (T 'FinishedRemaining' @($remaining.Count)) 'Warning'
        Show-TraceSummary -Traces $remaining
    }

    if ($script:RestartRequired) {
        Write-Status (T 'RestartNotice') 'Warning'
    }
    if ($logPath) { Write-Host (T 'LogLabel' @($logPath)) -ForegroundColor DarkGray }
    Add-RemovalHistory -ProgramName $Name -ResidualMode $ResidualOnly -RemovedCount ([int]$result.Removed) -FailedCount $result.Failed.Count -RemainingCount $remaining.Count -FreedBytes $freedBytes -LogPath $logPath
    $script:LastRunSummary = [PSCustomObject]@{ Before = $initialTraceCount; Found = $traces.Count; Removed = [int]$result.Removed; Failed = $result.Failed.Count; Skipped = $result.Skipped.Count; CoveredByParent = $result.CoveredByParent; Remaining = $remaining.Count; FreedBytes = $freedBytes; Integrity = $integrityResult }
    Set-OperationProgress -Percent 100 -Status (T 'ProgressDone')
    Complete-OperationProgress
    return $true
}

function Invoke-RemovalOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OperationName,
        [bool]$OperationResidualOnly,
        [bool]$OperationDryRun,
        [AllowNull()][object]$PreselectedProgram,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$PreloadedPrograms,
        [bool]$SkipConfirmation,
        [bool]$ContinueAfterElevation,
        [AllowEmptyString()][string]$ExpectedRegistryPath,
        [AllowEmptyString()][string]$ExpectedPackageFullName
    )

    $operationId = [guid]::NewGuid()
    $startedAt = [DateTimeOffset]::UtcNow
    $script:LastOperationResult = New-RemnexaOperationResult -OperationId $operationId -OperationName $OperationName -Status Started -StartedAtUtc $startedAt -CompletedAtUtc $startedAt
    try {
        $completed = Invoke-RemovalOperationCore @PSBoundParameters
        $summary = $script:LastRunSummary
        $status = if (-not $completed) { 'Cancelled' }
            elseif ($OperationDryRun) { 'DryRun' }
            elseif ($null -ne $summary -and (($summary.Failed -gt 0) -or ($summary.Remaining -gt 0))) { 'Partial' }
            else { 'Completed' }

        $script:LastOperationResult = New-RemnexaOperationResult `
            -OperationId $operationId `
            -OperationName $OperationName `
            -Status $status `
            -StartedAtUtc $startedAt `
            -CompletedAtUtc ([DateTimeOffset]::UtcNow) `
            -FoundCount $(if ($null -ne $summary) { [int]$summary.Found } else { 0 }) `
            -RemovedCount $(if ($null -ne $summary) { [int]$summary.Removed } else { 0 }) `
            -FailedCount $(if ($null -ne $summary) { [int]$summary.Failed } else { 0 }) `
            -RemainingCount $(if ($null -ne $summary) { [int]$summary.Remaining } else { 0 }) `
            -FreedBytes $(if ($null -ne $summary -and $null -ne $summary.PSObject.Properties['FreedBytes']) { [long]$summary.FreedBytes } else { 0 }) `
            -LogPath ([string]$script:LastRunLogPath)
        if ($status -eq 'Cancelled') { Write-Status (T 'OperationStatusCancelled') 'Warning' }
        return [bool]$completed
    }
    catch {
        $summary = $script:LastRunSummary
        $script:LastOperationResult = New-RemnexaOperationResult `
            -OperationId $operationId `
            -OperationName $OperationName `
            -Status Failed `
            -StartedAtUtc $startedAt `
            -CompletedAtUtc ([DateTimeOffset]::UtcNow) `
            -FoundCount $(if ($null -ne $summary) { [int]$summary.Found } else { 0 }) `
            -RemovedCount $(if ($null -ne $summary) { [int]$summary.Removed } else { 0 }) `
            -FailedCount $(if ($null -ne $summary) { [int]$summary.Failed } else { 0 }) `
            -RemainingCount $(if ($null -ne $summary) { [int]$summary.Remaining } else { 0 }) `
            -LogPath ([string]$script:LastRunLogPath) `
            -ErrorMessage $_.Exception.Message
        throw
    }
}

function Invoke-RemnexaSelfTest {
    $checks = New-Object System.Collections.Generic.List[object]
    $addCheck = {
        param([string]$Name, [bool]$Passed, [string]$Details)
        $checks.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Details = $Details })
    }

    & $addCheck 'Brand' ($script:BrandName -eq 'REMNEXA' -and $script:CleanerVersion -eq '2.2.0-rc.5') "$($script:BrandName) $($script:CleanerVersion)"
    $translationProblems = @(
        foreach ($key in $script:Texts.Keys) {
            $translations = @($script:Texts[$key])
            if ($translations.Count -ne $script:LanguageCodes.Count) {
                "${key}: expected $($script:LanguageCodes.Count) entries, found $($translations.Count)"
                continue
            }
            for ($index = 0; $index -lt $translations.Count; $index++) {
                if ([string]::IsNullOrWhiteSpace([string]$translations[$index])) {
                    "${key}: empty translation for '$($script:LanguageCodes[$index])'"
                }
            }
        }
    )
    $translationDetails = if ($translationProblems.Count -eq 0) {
        "All $($script:Texts.Count) text keys contain entries for $($script:LanguageCodes.Count) languages."
    }
    else {
        ($translationProblems | Select-Object -First 10) -join '; '
    }
    & $addCheck 'Übersetzungen' ($translationProblems.Count -eq 0) $translationDetails

    foreach ($requiredPath in @(
        (Join-Path $PSScriptRoot 'Antivirus\Antivirus.psd1'),
        (Join-Path $PSScriptRoot 'config\antivirus.json'),
        (Join-Path $PSScriptRoot 'Core\OperationResults.psd1'),
        (Join-Path $PSScriptRoot 'Core\AiContracts.psd1'),
        (Join-Path $PSScriptRoot 'Core\SystemSnapshot.psd1'),
        (Join-Path $PSScriptRoot 'assets\remnexa-logo.png')
    )) {
        & $addCheck ('Datei: ' + [IO.Path]::GetFileName($requiredPath)) (Test-Path -LiteralPath $requiredPath -PathType Leaf) $requiredPath
    }

    $portableRuntimePath = Join-Path $PSScriptRoot 'runtime\pwsh.exe'
    $portableRuntimePresent = Test-Path -LiteralPath $portableRuntimePath -PathType Leaf
    $portableRuntimeDetails = if ($portableRuntimePresent) {
        "Optionale portable Laufzeit vorhanden: $portableRuntimePath"
    }
    else {
        'Nicht gebündelt; REMNEXA verwendet PowerShell 7.5 oder neuer aus dem System.'
    }
    & $addCheck 'Portable PowerShell-Laufzeit (optional)' $true $portableRuntimeDetails

    try {
        $startupCount = @(Get-StartupItems).Count
        & $addCheck 'Autostart-Inventar' $true ("{0} aktive Einträge lesbar" -f $startupCount)
    }
    catch { & $addCheck 'Autostart-Inventar' $false $_.Exception.Message }

    try {
        $serviceCount = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | Where-Object { $_.State -eq 'Running' }).Count
        & $addCheck 'Dienste-Inventar' $true ("{0} aktive Dienste lesbar" -f $serviceCount)
    }
    catch { & $addCheck 'Dienste-Inventar' $false $_.Exception.Message }

    try {
        if (-not (Initialize-AntivirusModule)) { throw 'Antivirus-Modul konnte nicht geladen werden.' }
        $avStatus = Get-ClamAVStatus
        if ($null -eq $avStatus -or $null -eq $avStatus.PSObject.Properties['Installed']) {
            throw 'ClamAV-Status lieferte kein gueltiges Statusobjekt.'
        }
        $avDetails = if ($avStatus.Installed) {
            "Installiert: Version $($avStatus.Version); Signaturen: $($avStatus.Signatures)"
        }
        else {
            'ClamAV-Engine nicht installiert; die Integration ist optional.'
        }
        & $addCheck 'ClamAV (optionale Engine)' $true $avDetails
    }
    catch { & $addCheck 'ClamAV' $false $_.Exception.Message }

    $failed = @($checks | Where-Object { -not $_.Passed }).Count
    return [PSCustomObject]@{
        Application = $script:BrandName
        Version = $script:CleanerVersion
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Passed = ($failed -eq 0)
        FailedChecks = $failed
        Checks = $checks.ToArray()
    }
}

function Main {
    Initialize-AppSettings
    [void](Initialize-AntivirusModule)
    try { if($script:AntivirusAvailable) { [void](Start-ClamAVUpdateCheck) } } catch { Write-Verbose 'Antivirus metadata check was skipped.' }
    $interactiveSession = (([string]::IsNullOrWhiteSpace($Name) -and -not $ResidualOnly -and -not $DryRun) -or $ContinueInteractive)
    $script:InteractiveSession = [bool]$interactiveSession
    $hasProvidedRequest = -not [string]::IsNullOrWhiteSpace($Name)
    $currentWorkspace = if ($hasProvidedRequest) { 'Uninstall' } elseif ([string]::IsNullOrWhiteSpace($WorkspaceMode)) { 'Home' } else { $WorkspaceMode }

    if (-not [string]::IsNullOrWhiteSpace($ToolMode)) {
        $toolResult = switch ($ToolMode) {
            'Registry' { Invoke-OrphanRegistryMenu }
            'Features' { Invoke-OptionalFeatureMenu }
            'Privacy'  { Invoke-PrivacyMenu }
            'Antivirus' { Invoke-AntivirusMenu }
            'Startup' { Invoke-StartupMenu -InitialActionId $SelectedStartupId }
        }
        if ($toolResult -eq 'exit' -or -not $ContinueInteractive) { return }
        $currentWorkspace = 'Home'
    }

    :mainLoop while ($true) {
        $script:RestartRequired = $false
        $script:ExitRequested = $false
        Clear-RemnexaScreen
        Show-BrandHeader

        if ($interactiveSession -and -not $hasProvidedRequest -and $currentWorkspace -ne 'Uninstall') {
            switch ($currentWorkspace) {
                'Antivirus' {
                    if ((Invoke-AntivirusMenu) -eq 'exit') { return }
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                'Startup' {
                    if ((Invoke-StartupMenu) -eq 'exit') { return }
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                'Services' {
                    [void](Invoke-ActiveServicesScreen)
                    $currentWorkspace = 'Home'
                    continue mainLoop
                }
                default {
                    Show-HistorySummary
                    $homeChoice = Show-HomeMenu
                    switch ($homeChoice) {
                        '0' {
                            Write-Status (T 'ProgramEnded') 'Success'
                            return
                        }
                        '1' { $currentWorkspace = 'Uninstall'; continue mainLoop }
                        '2' { $currentWorkspace = 'Antivirus'; continue mainLoop }
                        '3' { $currentWorkspace = 'Startup'; continue mainLoop }
                        '4' { $currentWorkspace = 'Services'; continue mainLoop }
                        '5' {
                            if ((Show-HistoryScreen) -eq 'exit') { return }
                            continue mainLoop
                        }
                        '6' {
                            if ((Invoke-LogCleanupMenu) -eq 'exit') { return }
                            continue mainLoop
                        }
                        '7' {
                            Show-LanguageMenu
                            continue mainLoop
                        }
                        '9' {
                            Show-SystemSnapshotScreen
                            continue mainLoop
                        }
                        '8' {
                            :homeToolsLoop while ($true) {
                                $homeToolChoice = Show-AdvancedToolsMenu
                                switch ($homeToolChoice) {
                                    '0' { continue mainLoop }
                                    '1' { if ((Invoke-SystemIntegrityScreen) -eq 'exit') { return }; continue homeToolsLoop }
                                    '2' {
                                        Write-Status 'AppX/UWP befindet sich im Deinstallationsbereich unter [9] > [2].' 'Info'
                                        Start-Sleep -Milliseconds 1200
                                        $currentWorkspace = 'Uninstall'
                                        continue mainLoop
                                    }
                                    '3' { if ((Invoke-OrphanRegistryMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '4' { if ((Invoke-OptionalFeatureMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '5' { if ((Invoke-PrivacyMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                    '6' { if ((Invoke-AntivirusMenu) -eq 'exit') { return }; continue homeToolsLoop }
                                }
                            }
                        }
                    }
                }
            }
        }

        Write-Host (T 'AppDescription')
        if (-not (Test-IsAdministrator)) {
            Write-Host (T 'AdminDeferred') -ForegroundColor DarkGray
        }
        Write-Host ''

        $operationName = ''
        $operationResidualOnly = $false
        $operationDryRun = $false
        $preselected = $null
        $preloadedPrograms = @()
        $skipConfirmation = $false
        $expectedRegistryPath = ''
        $expectedPackageFullName = ''

        if ($hasProvidedRequest) {
            $operationName = $Name
            $operationResidualOnly = [bool]$ResidualOnly
            $operationDryRun = [bool]$DryRun
            $skipConfirmation = [bool]$ResumeRemoval
            $expectedRegistryPath = $SelectedRegistryPath
            $expectedPackageFullName = $SelectedPackageFullName
            $hasProvidedRequest = $false
        }
        elseif ($interactiveSession) {
            Show-HistorySummary
            if ($script:ReturnToProgramList -and $null -ne $script:LastProgramListContext) {
                $menuChoice = '99'
                $preselected = Select-ProgramPaged -Programs $script:LastProgramListContext.Programs -Title $script:LastProgramListContext.Title -ResumeContext $script:LastProgramListContext
                $script:ReturnToProgramList = $false
                if ($script:ExitRequested) { return }
                if ($null -eq $preselected) { continue mainLoop }
            }
            else { $menuChoice = Show-UninstallMenu }
            if ($menuChoice -eq '0') {
                $currentWorkspace = 'Home'
                continue mainLoop
            }

            switch ($menuChoice) {
                '99' { $operationName = $preselected.DisplayName }
                '1' {
                    $operationName = Read-RemnexaInput (T 'ProgramNamePrompt')
                }
                '2' {
                    Write-Status (T 'InventoryReading')
                    $preloadedPrograms = @(Get-InstalledPrograms)
                    $ordinaryPrograms = @($preloadedPrograms | Where-Object { -not $_.IsSystemLike -and $_.CanUninstall })
                    $preselected = Select-ProgramPaged -Programs $ordinaryPrograms -Title (T 'InstalledTitle')
                    if ($script:ExitRequested) { return }
                    if ($null -eq $preselected) { continue mainLoop }
                    $operationName = $preselected.DisplayName
                }
                '3' {
                    Write-Status (T 'InventoryAllReading')
                    $preloadedPrograms = @(Get-InstalledPrograms)
                    $preselected = Select-ProgramPaged -Programs $preloadedPrograms -Title (T 'AllAppsTitle')
                    if ($script:ExitRequested) { return }
                    if ($null -eq $preselected) { continue mainLoop }
                    $operationName = $preselected.DisplayName
                }
                '4' {
                    $operationName = Read-RemnexaInput (T 'ResidualNamePrompt')
                    $operationResidualOnly = $true
                }
                '5' {
                    $operationName = Read-RemnexaInput (T 'DryRunNamePrompt')
                    $operationDryRun = $true
                }
                '6' {
                    if ((Show-HistoryScreen) -eq 'exit') {
                        Write-Status (T 'ProgramEnded') 'Success'
                        return
                    }
                    continue mainLoop
                }
                '7' {
                    if ((Invoke-LogCleanupMenu) -eq 'exit') {
                        Write-Status (T 'ProgramEnded') 'Success'
                        return
                    }
                    continue mainLoop
                }
                '8' {
                    Show-LanguageMenu
                    continue mainLoop
                }
                '9' {
                    $startAppxRemoval = $false
                    :uninstallToolsLoop while ($true) {
                        $toolChoice = Show-AdvancedToolsMenu
                        switch ($toolChoice) {
                            '0' { $currentWorkspace = 'Home'; continue mainLoop }
                            '1' { if ((Invoke-SystemIntegrityScreen) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '2' {
                                Write-Status (T 'InventoryReading')
                                $preloadedPrograms = @(Get-InstalledPrograms)
                                $appxPrograms = @($preloadedPrograms | Where-Object { $_.Type -eq 'Appx' -and -not $_.IsSystemLike -and $_.CanUninstall })
                                $preselected = Select-ProgramPaged -Programs $appxPrograms -Title (T 'AppxTitle')
                                if ($script:ExitRequested) { return }
                                if ($null -eq $preselected) { continue uninstallToolsLoop }
                                $operationName = $preselected.DisplayName
                                $startAppxRemoval = $true
                            }
                            '3' { if ((Invoke-OrphanRegistryMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '4' { if ((Invoke-OptionalFeatureMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '5' { if ((Invoke-PrivacyMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                            '6' { if ((Invoke-AntivirusMenu) -eq 'exit') { return }; continue uninstallToolsLoop }
                        }
                        if ($startAppxRemoval) { break }
                    }
                    if (-not $startAppxRemoval) { continue mainLoop }
                }
            }
        }
        else {
            return
        }

        if ([string]::IsNullOrWhiteSpace($operationName)) {
            Write-Status (T 'NoName') 'Warning'
            if ($interactiveSession) {
                Start-Sleep -Milliseconds 900
                continue mainLoop
            }
            return
        }

        try {
            $completed = Invoke-RemovalOperation `
                -OperationName $operationName `
                -OperationResidualOnly $operationResidualOnly `
                -OperationDryRun $operationDryRun `
                -PreselectedProgram $preselected `
                -PreloadedPrograms $preloadedPrograms `
                -SkipConfirmation $skipConfirmation `
                -ContinueAfterElevation $interactiveSession `
                -ExpectedRegistryPath $expectedRegistryPath `
                -ExpectedPackageFullName $expectedPackageFullName
        }
        catch {
            Complete-OperationProgress
            Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
            $failureLogPath = Save-RunLog -Program $preselected -SearchName $operationName -Traces @() -Result $null
            if ($null -ne $script:LastOperationResult) { $script:LastOperationResult.LogPath = [string]$failureLogPath }
            $completed = $true
        }

        if ($script:ExitRequested) { return }
        if ($completed) { Invoke-PostRemovalIntegrityCheck }
        if (-not $interactiveSession) { return }
        if (-not $completed) { continue mainLoop }

        Show-LastRunDetails
        $nextAction = Read-AfterOperationChoice
        if ($nextAction -eq 'list') { $script:ReturnToProgramList = $true }
        if ($nextAction -eq 'exit') {
            Write-Status (T 'ProgramEnded') 'Success'
            return
        }
    }
}

$scriptExitCode = 0
try {
    if ($SelfTest) {
        Set-RemnexaProgressRendering -Enabled $false
        $selfTestResult = Invoke-RemnexaSelfTest
        $selfTestResult | ConvertTo-Json -Depth 6
        if (-not $selfTestResult.Passed) { $scriptExitCode = 1 }
    }
    else {
        Main
    }
}
catch {
    Write-Status (T 'ErrorPrefix' @($_.Exception.Message)) 'Error'
    Save-RunLog -Program $null -SearchName $(if ($Name) { $Name } else { 'unbekannt' }) -Traces @() -Result $null | Out-Null
    $scriptExitCode = 1
}
finally {
    if(Get-Command Stop-ClamAVUpdateCheck -ErrorAction SilentlyContinue) { try { Stop-ClamAVUpdateCheck } catch { Write-Verbose 'Antivirus metadata worker cleanup failed.' } }
    if(Get-Command Stop-ClamAVScanEngine -ErrorAction SilentlyContinue) { try { Stop-ClamAVScanEngine } catch { Write-Verbose 'Antivirus scan worker cleanup failed.' } }
}
Complete-OperationProgress

exit $scriptExitCode
