function Get-AVQuickScanTargets {
    param([AllowEmptyCollection()][string[]]$AdditionalPaths = @())

    $targets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @(
        $env:TEMP,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $targets.Add([IO.Path]::GetFullPath($candidate)) }
    }

    # ProgramData wird nicht pauschal gescannt: nur typische ausfuehrbare Inhalte
    # werden in die Zieldatei aufgenommen, damit der Quick-Scan auch wirklich kurz bleibt.
    if ($env:ProgramData -and (Test-Path -LiteralPath $env:ProgramData -PathType Container)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $env:ProgramData -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @('.exe', '.dll', '.scr', '.com', '.msi', '.ps1', '.bat', '.cmd', '.js', '.vbs')
        })) {
            $targets.Add($file.FullName)
        }
    }
    foreach ($path in $AdditionalPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) { $targets.Add([IO.Path]::GetFullPath($path)) }
    }
    return @($targets | Select-Object -Unique)
}

function Get-AVFullScanTargets {
    param([AllowEmptyCollection()][string[]]$AdditionalPaths = @())

    $targets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @(
        $env:WINDIR,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:USERPROFILE
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $targets.Add([IO.Path]::GetFullPath($candidate)) }
    }
    foreach ($path in $AdditionalPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) { $targets.Add([IO.Path]::GetFullPath($path)) }
    }
    return @($targets | Select-Object -Unique)
}

function Resolve-AVScanTargets {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Quick', 'Full', 'Custom')][string]$ScanType,
        [AllowEmptyCollection()][string[]]$Path,
        [Parameter(Mandatory = $true)][object]$Config
    )

    if ($ScanType -eq 'Custom' -and @($Path).Count -eq 0) {
        throw 'Fuer ScanType Custom muss mindestens ein Pfad mit -Path angegeben werden.'
    }
    $rawTargets = switch ($ScanType) {
        'Quick' { @(Get-AVQuickScanTargets -AdditionalPaths @($Path)) }
        'Full'  { @(Get-AVFullScanTargets -AdditionalPaths @($Path)) }
        default { @($Path) }
    }

    $excluded = @($Config.ExcludedPaths | ForEach-Object { Expand-AVPath ([string]$_) } | Where-Object { $_ })
    $quarantine = Expand-AVPath ([string]$Config.QuarantinePath)
    if ($quarantine) { $excluded += $quarantine }
    $logPath = Expand-AVPath ([string]$Config.LogPath)
    if ($logPath) { $excluded += $logPath }

    $targets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rawTarget in $rawTargets) {
        if ([string]::IsNullOrWhiteSpace([string]$rawTarget)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$rawTarget)
        if (-not (Test-Path -LiteralPath $expanded)) {
            Write-Warning "Scan-Ziel existiert nicht und wird uebersprungen: '$expanded'."
            Write-AVLog -Message "Scan-Ziel nicht gefunden: $expanded" -Level 'Warning' -Event 'Scan'
            continue
        }
        $fullPath = [IO.Path]::GetFullPath($expanded)
        $isExcluded = $false
        foreach ($excludedPath in $excluded) {
            if ($fullPath.Equals($excludedPath, [StringComparison]::OrdinalIgnoreCase) -or (Test-AVPathIsWithin -Path $fullPath -Parent $excludedPath)) {
                $isExcluded = $true
                break
            }
        }
        if (-not $isExcluded) { $targets.Add($fullPath) }
    }
    return @($targets | Select-Object -Unique)
}

function Get-AVExcludeArguments {
    param([Parameter(Mandatory = $true)][object]$Config)

    $paths = @($Config.ExcludedPaths | ForEach-Object { Expand-AVPath ([string]$_) } | Where-Object { $_ })
    $paths += Expand-AVPath ([string]$Config.QuarantinePath)
    $paths += Expand-AVPath ([string]$Config.LogPath)
    foreach ($path in @($paths | Where-Object { $_ } | Select-Object -Unique)) {
        $pattern = '^' + [regex]::Escape($path.TrimEnd('\')) + '(?:[\\/]|$)'
        '--exclude-dir=' + $pattern
    }
}

function Test-AVSystemScanRequiresElevation {
    param([AllowEmptyCollection()][string[]]$Path)

    foreach ($candidate in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        if (-not $candidate) { continue }
        foreach ($target in $Path) {
            if ($target.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) -or (Test-AVPathIsWithin -Path $target -Parent $candidate)) {
                return $true
            }
        }
    }
    return $false
}
