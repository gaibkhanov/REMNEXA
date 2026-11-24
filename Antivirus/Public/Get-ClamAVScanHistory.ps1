function ConvertTo-AVHistoryEntry {
    param($Value,[string]$Directory,[DateTimeOffset]$FallbackRecordedUtc,[switch]$Legacy)
    if(-not $Value -or $Value.State -notin @('Completed','Warning','Cancelled','Failed')){return}
    $numbers=@{}
    foreach($name in @('Files','Total','Findings')){
        $number=[long]0
        if(-not [long]::TryParse([string]$Value.$name,[ref]$number) -or $number -lt $(if($name -eq 'Total'){-1}else{0})){return}
        $numbers[$name]=$number
    }
    $elapsed=[double]0
    if(-not [double]::TryParse([string]$Value.ElapsedSeconds,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$elapsed) -or -not [double]::IsFinite($elapsed) -or $elapsed -lt 0 -or $elapsed -gt 31536000){return}
    $dates=@{}
    foreach($name in @('StartedAtUtc','CompletedAtUtc','RecordedAtUtc')){
        $date=[DateTimeOffset]::MinValue
        $property=$Value.PSObject.Properties[$name]
        $dates[$name]=if($property -and [DateTimeOffset]::TryParse([string]$property.Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$date)){$date.ToUniversalTime().ToString('o')}else{$null}
    }
    if(-not $dates.RecordedAtUtc){$dates.RecordedAtUtc=$FallbackRecordedUtc.ToUniversalTime().ToString('o')}
    $type=if($Value.PSObject.Properties['ScanType'] -and $Value.ScanType -in @('Quick','Full','Custom')){[string]$Value.ScanType}else{'Unknown'}
    $report=if($Value.PSObject.Properties['ReportFile'] -and $Value.ReportFile -match '^results-[a-f0-9]{32}\.json$'){[string]$Value.ReportFile}else{'results.json'}
    $id=if($Value.PSObject.Properties['HistoryId'] -and $Value.HistoryId -match '^[a-f0-9]{32}$'){[string]$Value.HistoryId}else{(Split-Path -Leaf $Directory)+'/'+$report}
    [pscustomobject]@{
        Id=$id;State=[string]$Value.State;ScanType=$type;Files=$numbers.Files;Total=$numbers.Total;Findings=$numbers.Findings
        ElapsedSeconds=$elapsed;StartedAtUtc=$dates.StartedAtUtc;CompletedAtUtc=$dates.CompletedAtUtc;RecordedAtUtc=$dates.RecordedAtUtc
        ReportPath=(Join-Path $Directory $report);IsLegacy=[bool]$Legacy
    }
}

function Get-ClamAVScanHistory {
    <# .SYNOPSIS
    Reads saved interactive scan summaries without starting or changing a scan.
    Older snapshots use their recorded file time, not an invented completion time.
    #>
    [CmdletBinding()]
    param([ValidateRange(1,1000)][int]$First=20,[string]$ConfigPath=$script:AVConfigPath)
    $entries=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    try {
        $root=Get-AVSessionRoot $ConfigPath
        if(-not (Test-Path -LiteralPath $root -PathType Container) -or -not (Get-RemnexaPathSafety $root).IsSafe){return}
        $context=Get-AVUpdateContext (Get-AVConfig -Path $ConfigPath)
        foreach($directory in [IO.Directory]::EnumerateDirectories($root,'scan-*',[IO.SearchOption]::TopDirectoryOnly)){
            if((Split-Path -Leaf $directory) -notmatch '^scan-[a-f0-9]{32}$' -or -not (Get-RemnexaPathSafety $directory).IsSafe){continue}
            try {
                $server=Read-AVSessionJson (Join-Path $directory 'server.json')
                if(-not $server -or $server.Context -ne $context){continue}
                foreach($file in [IO.Directory]::EnumerateFiles($directory,'history-*.json',[IO.SearchOption]::TopDirectoryOnly)){
                    if((Split-Path -Leaf $file) -notmatch '^history-[a-f0-9]{32}\.json$'){continue}
                    try {
                        $value=Read-AVSessionJson $file -Limit 64KB
                        $entry=ConvertTo-AVHistoryEntry $value $directory ([IO.File]::GetLastWriteTimeUtc($file))
                        if($entry){$entries[$entry.Id]=$entry}
                    }catch{Write-Verbose ('Ignoring unreadable scan summary: '+$_.Exception.Message)}
                }
                # Compatibility with scans saved before separate history records.
                $file=Join-Path $directory 'status.json'
                $snapshot=Read-AVSessionJson $file
                if($snapshot){
                    if($snapshot.State -in @('Starting','Running','Pausing','Paused','Cancelling')){
                        $session=[pscustomobject]@{Descriptor=$server}
                        if(Test-AVSessionAlive $session){continue}
                        $snapshot.State='Failed'
                    }
                    $entry=ConvertTo-AVHistoryEntry $snapshot $directory ([IO.File]::GetLastWriteTimeUtc($file)) -Legacy
                    if($entry -and -not $entries.ContainsKey($entry.Id)){$entries[$entry.Id]=$entry}
                }
            }catch{Write-Verbose ('Ignoring unreadable scan session: '+$_.Exception.Message)}
        }
    }catch{Write-Verbose ('Scan history is unavailable: '+$_.Exception.Message)}
    $entries.Values|Sort-Object -Property @{Expression={[DateTimeOffset]::Parse($_.RecordedAtUtc)};Descending=$true},Id|Select-Object -First $First
}
