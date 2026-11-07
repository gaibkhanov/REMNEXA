function Expand-AVPath {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path (Split-Path -Parent $script:AVModuleRoot) $expanded
    }
    return [IO.Path]::GetFullPath($expanded)
}

function ConvertTo-AVPortableConfigPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $applicationRoot = [IO.Path]::GetFullPath((Split-Path -Parent $script:AVModuleRoot)).TrimEnd('\')
    if ($fullPath.StartsWith($applicationRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($applicationRoot.Length + 1)
    }
    return $fullPath
}

function Test-AVAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-AVLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Level = 'Info',
        [string]$Event = 'Antivirus',
        [AllowNull()][object]$Data
    )

    $line = '[{0:yyyy-MM-dd HH:mm:ss}] [{1}] [Antivirus/{2}] {3}' -f (Get-Date), $Level, $Event, $Message
    $hostLogger = Get-Command -Name Write-LogEntry -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $hostLogger) {
        try {
            & $hostLogger -Message $Message -Level $Level -Component ('Antivirus/' + $Event)
            return
        }
        catch { }
    }

    try {
        $config = Get-AVConfig
        $logRoot = Expand-AVPath ([string]$config.LogPath)
        if (-not [string]::IsNullOrWhiteSpace($logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force -ErrorAction Stop | Out-Null
            Add-Content -LiteralPath (Join-Path $logRoot ('antivirus-{0:yyyyMMdd}.log' -f (Get-Date))) -Value $line -Encoding UTF8 -ErrorAction Stop
            if ($null -ne $Data) {
                [PSCustomObject]@{
                    Timestamp = [DateTimeOffset]::Now.ToString('o')
                    Level     = $Level
                    Event     = $Event
                    Message   = $Message
                    Data      = $Data
                } | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath (Join-Path $logRoot ('antivirus-{0:yyyyMMdd}.jsonl' -f (Get-Date))) -Encoding UTF8
            }
        }
    }
    catch {
        Write-Verbose ('Antivirus-Protokoll konnte nicht geschrieben werden: ' + $_.Exception.Message)
    }
}

function Get-ClamAVExecutablePaths {
    param([AllowNull()][object]$Config)

    if ($null -eq $Config) { $Config = Get-AVConfig }
    $root = Expand-AVPath ([string]$Config.ClamAVPath)
    [PSCustomObject]@{
        Root         = $root
        ClamScan     = Join-Path $root 'clamscan.exe'
        FreshClam    = Join-Path $root 'freshclam.exe'
        SigTool      = Join-Path $root 'sigtool.exe'
        Database     = Expand-AVPath ([string]$Config.DatabasePath)
        FreshClamConf = Join-Path $root 'freshclam.conf'
    }
}

function ConvertTo-AVFlatConfig {
    param([Parameter(Mandatory = $true)][object]$Config)

    $copy = [ordered]@{}
    foreach ($property in $Config.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }
    return [PSCustomObject]$copy
}

function Test-AVMaxFileSize {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^\d+(?:\.\d+)?[KMG]?$') {
        throw "Ungueltiger Wert fuer MaxFileSize: '$Value'. Beispiele: 100M, 512K oder 1G."
    }
}

function Get-AVNormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function Test-AVPathIsWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    try {
        $candidate = (Get-AVNormalizedFullPath $Path) + '\'
        $root = (Get-AVNormalizedFullPath $Parent) + '\'
        return $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}
