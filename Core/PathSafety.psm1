Set-StrictMode -Version 2.0

function Get-RemnexaPathSafety {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetPathRoot($fullPath)
        if ([string]::IsNullOrWhiteSpace($root)) {
            throw 'The path has no filesystem root.'
        }
        if ($fullPath.Length -gt $root.Length) {
            $fullPath = $fullPath.TrimEnd('\')
        }
    }
    catch {
        return [PSCustomObject]@{
            IsSafe = $false
            Reason = 'InvalidPath'
            FullPath = $Path
            Component = $Path
            Error = $_.Exception.Message
        }
    }

    $current = $fullPath
    while ($true) {
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        }
        catch {
            return [PSCustomObject]@{
                IsSafe = $false
                Reason = 'Uninspectable'
                FullPath = $fullPath
                Component = $current
                Error = $_.Exception.Message
            }
        }

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [PSCustomObject]@{
                IsSafe = $false
                Reason = 'ReparsePoint'
                FullPath = $fullPath
                Component = $current
                Error = ''
            }
        }

        if ($current.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($current, [StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                IsSafe = $false
                Reason = 'Uninspectable'
                FullPath = $fullPath
                Component = $current
                Error = 'The path chain could not be resolved to its root.'
            }
        }
        $current = $parent
    }

    return [PSCustomObject]@{
        IsSafe = $true
        Reason = 'Clear'
        FullPath = $fullPath
        Component = ''
        Error = ''
    }
}

function Test-RemnexaWindowsManagedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not [IO.Path]::IsPathFullyQualified($Path)) { return $false }
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        if ($full.StartsWith('\\?\', [StringComparison]::Ordinal)) { $full = $full.Substring(4) }
        # Match the directory boundary on any drive, including encoded package
        # metadata descendants. A similarly named WindowsAppsBackup is not a match.
        return $full -match '^(?i:[A-Z]:\\(?:Program Files(?: \(x86\))?\\)?WindowsApps)(?:\\|$)'
    }
    catch { return $false }
}

Export-ModuleMember -Function Get-RemnexaPathSafety, Test-RemnexaWindowsManagedPath
