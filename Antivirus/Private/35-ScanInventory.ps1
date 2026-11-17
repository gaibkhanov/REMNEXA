Import-Module (Join-Path $PSScriptRoot '..\..\Core\PathSafety.psd1') -ErrorAction Stop

function New-AVScanFileList {
    param([string[]]$Targets,[object]$Config,[string]$ListPath,[object]$Progress,
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,$CancellationControl=$null)
    if(-not ('Remnexa.Scan.Inventory' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'ScanInventory.cs') -ErrorAction Stop
    }
    $excluded=@($Config.ExcludedPaths|ForEach-Object{Expand-AVPath ([string]$_)})
    $excluded+=Expand-AVPath ([string]$Config.QuarantinePath)
    $excluded+=Expand-AVPath ([string]$Config.LogPath)
    $excluded+=[IO.Path]::GetFullPath($ListPath)
    $roots=[Collections.Generic.List[string]]::new()
    $directories=[Collections.Generic.List[string]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $skipped=0
    foreach($target in @($Targets|Sort-Object Length)) {
        $CancellationToken.ThrowIfCancellationRequested()
        $full=[IO.Path]::GetFullPath($target)
        if(-not $seen.Add($full)){continue}
        $covered=$false
        foreach($directory in $directories){if(Test-AVPathIsWithin $full $directory){$covered=$true;break}}
        if($covered){continue}
        if(-not (Get-RemnexaPathSafety -Path $full).IsSafe){$skipped++;continue}
        $roots.Add($full)
        if([IO.Directory]::Exists($full)){$directories.Add($full)}
    }
    $updater=Get-Command Update-RemnexaProgress
    $text=Get-RemnexaProgressText 'ProgressScanSkipped'
    $callback=[Action[long,long,string]]{param($Files,$Skipped,$Current)
        if($CancellationControl){$CancellationControl.Poll()}
        & $updater $Progress -Completed $Files -CurrentItem $Current -Status ($text -f $Files,$Skipped)
    }.GetNewClosure()
    try{$result=[Remnexa.Scan.Inventory]::Write($roots.ToArray(),[string[]]$excluded,$ListPath,$CancellationToken,$callback)}
    catch{if($CancellationToken.IsCancellationRequested){throw [OperationCanceledException]::new('Scan cancelled.',$CancellationToken)};throw}
    [pscustomobject]@{Files=$result.Files;Skipped=($result.Skipped+$skipped);Roots=$result.Roots;Issues=@($result.Issues)}
}
