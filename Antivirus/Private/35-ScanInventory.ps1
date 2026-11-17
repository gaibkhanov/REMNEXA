Import-Module (Join-Path $PSScriptRoot '..\..\Core\PathSafety.psd1') -ErrorAction Stop

function New-AVScanFileList {
    param([string[]]$Targets, [object]$Config, [string]$ListPath, [object]$Progress)
    $excluded = @($Config.ExcludedPaths | ForEach-Object { Expand-AVPath ([string]$_) })
    $excluded += Expand-AVPath ([string]$Config.QuarantinePath)
    $excluded += Expand-AVPath ([string]$Config.LogPath)
    $excluded += [IO.Path]::GetFullPath($ListPath)
    $directories = [Collections.Generic.List[object]]::new()
    $files = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $safeParents = [Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::OrdinalIgnoreCase)
    $count = [long]0
    $skipped = [long]0
    foreach ($target in @($Targets | Sort-Object Length)) {
        Update-RemnexaProgress $Progress -CurrentItem $target
        try {
            $full = [IO.Path]::GetFullPath($target)
            if (-not $seen.Add($full)) { continue }
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            $parent = [IO.Path]::GetDirectoryName($full)
            if ($parent -and -not $safeParents.ContainsKey($parent)) { $safeParents[$parent]=(Get-RemnexaPathSafety -Path $parent).IsSafe }
            if (($parent -and -not $safeParents[$parent]) -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++; continue }
            if ($item.PSIsContainer) {
                $covered=$false
                foreach ($directory in $directories) {
                    if (Test-AVPathIsWithin -Path $full -Parent $directory.FullName) { $covered=$true;break }
                }
                if (-not $covered) { $directories.Add($item) }
            }
            else { $files.Add($item) }
        }
        catch { $skipped++ }
    }
    $pending = [Collections.Generic.Stack[object]]::new()
    foreach ($directory in $directories) { $pending.Push($directory) }
    foreach ($file in $files) {
        $covered=$false
        foreach ($directory in $directories) { if (Test-AVPathIsWithin -Path $file.FullName -Parent $directory.FullName) { $covered=$true;break } }
        if (-not $covered) { $pending.Push($file) }
    }
    $writer = [IO.StreamWriter]::new($ListPath, $false, [Text.UTF8Encoding]::new($false))
    try {
        while ($pending.Count -gt 0) {
            $item = $pending.Pop()
            $current = $item.FullName
            $isExcluded = $false
            foreach ($path in $excluded) {
                if ($path -and ($current.Equals($path, [StringComparison]::OrdinalIgnoreCase) -or (Test-AVPathIsWithin -Path $current -Parent $path))) { $isExcluded=$true;break }
            }
            if ($isExcluded) { continue }
            try {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++;continue }
                if ($item.PSIsContainer) {
                    $readErrors=@()
                    foreach ($child in Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue -ErrorVariable readErrors) { $pending.Push($child) }
                    $skipped += $readErrors.Count
                }
                elseif ($current -match '[\r\n]') { $skipped++ }
                else { $writer.WriteLine($current);$count++ }
            }
            catch { $skipped++ }
            Update-RemnexaProgress $Progress -Completed $count -CurrentItem $current -Status ((Get-RemnexaProgressText 'ProgressScanSkipped') -f $count,$skipped)
        }
    }
    finally { $writer.Dispose() }
    [PSCustomObject]@{Files=$count;Skipped=$skipped;Roots=($directories.Count+$files.Count)}
}
