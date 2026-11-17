Describe 'REMNEXA antivirus measured progress' {
    BeforeEach {
        $script:avProgressRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:avProgressRoot 'Core\Progress.psd1') -Force
        Set-RemnexaProgressRendering -Enabled $false
        Import-Module (Join-Path $script:avProgressRoot 'Antivirus\Antivirus.psd1') -Force
        $script:avProgressModule = Get-Module Antivirus
        $script:avProgressFixture = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-AVProgress-' + [guid]::NewGuid().ToString('N'))
        $script:avProgressEnvironment = @{}
        foreach ($name in @('TEMP','APPDATA','LOCALAPPDATA','USERPROFILE','ProgramData')) { $script:avProgressEnvironment[$name]=[Environment]::GetEnvironmentVariable($name) }
        $profile = Join-Path $script:avProgressFixture 'profile'
        $paths = @{ USERPROFILE=$profile; APPDATA=(Join-Path $profile 'AppData\Roaming'); LOCALAPPDATA=(Join-Path $profile 'AppData\Local'); TEMP=(Join-Path $profile 'AppData\Local\Temp'); ProgramData=(Join-Path $script:avProgressFixture 'program-data') }
        foreach ($name in $paths.Keys) { New-Item -ItemType Directory -Path $paths[$name] -Force | Out-Null; [Environment]::SetEnvironmentVariable($name,$paths[$name]) }
        foreach ($relative in @('AppData\Roaming\roaming.txt','AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\startup.cmd','AppData\Local\local.txt','AppData\Local\Temp\temp.txt','Downloads\download.txt')) {
            $path=Join-Path $profile $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path,'harmless fixture')
        }
        foreach ($relative in @('tool.exe','Microsoft\Windows\Start Menu\Programs\Startup\link.lnk')) {
            $path=Join-Path $paths.ProgramData $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path,'harmless non-executable fixture content')
        }
        $config=Get-Content (Join-Path $script:avProgressRoot 'config\antivirus.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.LogPath=Join-Path $script:avProgressFixture 'logs'
        $config.QuarantinePath=Join-Path $script:avProgressFixture 'quarantine'
        $config.ExcludedPaths=@()
        $config.ClamAVPath=Join-Path $script:avProgressFixture 'engine'
        $config.DatabasePath=Join-Path $script:avProgressFixture 'database'
        $configPath=Join-Path $script:avProgressFixture 'config.json'
        $config|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $configPath -Encoding utf8
        & $script:avProgressModule {
            param($ConfigPath,$Fixture)
            $script:FixtureConfigPath=$ConfigPath; $script:FixtureBase=$Fixture
            $script:FixtureMode='Clean'
            $script:FixtureFiles=@()
            $script:FixtureFrames=[Collections.Generic.List[object]]::new()
            $script:ActualComplete=(Get-Command Complete-RemnexaProgress).ScriptBlock
            $script:ActualFrame=Get-Command Get-RemnexaProgressFrame
            function script:Get-AVConfig { param($Path) Get-Content $script:FixtureConfigPath -Raw -Encoding utf8 | ConvertFrom-Json }
            function script:Get-ClamAVStatus { param($ConfigPath) [PSCustomObject]@{Installed=$true;Ready=$true;SignaturesOutdated=$false;ClamScanPath=(Join-Path $script:FixtureBase 'clamscan.exe');DatabasePath=(Join-Path $script:FixtureBase 'database')} }
            function script:Test-AVAdministrator { return $true }
            function script:Write-AVLog { param($Message,$Level,$Event,$Data) }
            function script:Complete-RemnexaProgress {
                param($Progress,$Outcome='Completed',$Status='')
                & $script:ActualComplete $Progress -Outcome $Outcome -Status $Status
                $script:FixtureFrames.Add((& $script:ActualFrame $Progress))
            }
            function script:Invoke-AVNativeProcess {
                param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory,$OnOutput,$OnHeartbeat,$CaptureFilter)
                $list=($ArgumentList | Where-Object { $_.StartsWith('--file-list=') }).Substring(12)
                $script:FixtureFiles=@(Get-Content -LiteralPath $list -Encoding utf8)
                $stdout=[Collections.Generic.List[string]]::new()
                $number=0
                foreach($file in $script:FixtureFiles) {
                    $number++
                    if($script:FixtureMode -eq 'Partial' -and $number -gt 1){continue}
                    & $OnOutput ('Scanning '+$file) Stdout
                    $line=if($script:FixtureMode -eq 'Error'){ $file+': Fixture access error ERROR' }elseif($script:FixtureMode -eq 'Finding'){ $file+': Fixture.Test FOUND' }else{ $file+': OK' }
                    & $OnOutput $line Stdout
                    if(& $CaptureFilter $line Stdout){$stdout.Add($line)}
                    & $OnHeartbeat ([PSCustomObject]@{ElapsedSeconds=$number;ProcessId=0})
                }
                [PSCustomObject]@{ExitCode=$(if($script:FixtureMode -eq 'Error'){2}elseif($script:FixtureMode -in @('Finding','Unparseable')){1}else{0});StandardOutput=($stdout -join [Environment]::NewLine);StandardError=''}
            }
        } $configPath $script:avProgressFixture
    }

    AfterEach {
        foreach($name in $script:avProgressEnvironment.Keys){[Environment]::SetEnvironmentVariable($name,$script:avProgressEnvironment[$name])}
        Remove-Module Antivirus -ErrorAction SilentlyContinue
        $path=[IO.Path]::GetFullPath($script:avProgressFixture)
        if($path.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $path) -like 'REMNEXA-AVProgress-*' -and (Test-Path -LiteralPath $path)){Remove-Item -LiteralPath $path -Recurse -Force}
    }

    It 'runs the real Quick target/inventory workflow once per file without overlapping roots' {
        $result=Invoke-ClamAVScan -ScanType Quick
        if($result.FilesTotal -ne 7 -or $result.FilesReported -ne 7 -or -not $result.CoverageComplete -or $result.Status -ne 'Clean'){throw 'Quick coverage was duplicated or miscounted.'}
        & $script:avProgressModule {
            if(@($script:FixtureFiles|Select-Object -Unique).Count -ne 7){throw 'Quick file list contained duplicates.'}
            $last=$script:FixtureFrames[$script:FixtureFrames.Count-1]
            if($last.Percent -ne 100 -or $last.Color -ne 'Green'){throw 'Successful Quick scan did not complete correctly.'}
        }
    }

    It 'marks missing scanner acknowledgements as partial instead of falsely clean' {
        & $script:avProgressModule {$script:FixtureMode='Partial'}
        $result=Invoke-ClamAVScan -ScanType Quick
        if($result.Status -ne 'Partial' -or $result.CoverageComplete -or $result.FilesUnconfirmed -ne 6){throw 'Unconfirmed files were reported clean.'}
        & $script:avProgressModule {
            $last=$script:FixtureFrames[$script:FixtureFrames.Count-1]
            if($last.Color -ne 'Yellow' -or $last.Completed -ne 1 -or $last.Percent -ne 14){throw 'Partial coverage was green or the processed count was inflated.'}
        }
    }

    It 'fails safely when the scanner reports a detection without an attributable finding' {
        & $script:avProgressModule {$script:FixtureMode='Unparseable'}
        $rejected=$false
        try{Invoke-ClamAVScan -ScanType Quick|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Unattributable detection was presented as clean.'}
        & $script:avProgressModule {if($script:FixtureFrames[$script:FixtureFrames.Count-1].Color -ne 'Red'){throw 'Unattributable detection was not red.'}}
    }

    It 'ends in red on scanner errors and leaves no active progress operation' {
        & $script:avProgressModule {$script:FixtureMode='Error'}
        $rejected=$false
        try {Invoke-ClamAVScan -ScanType Quick|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'A scan error was accepted.'}
        & $script:avProgressModule {if($script:FixtureFrames[$script:FixtureFrames.Count-1].Color -ne 'Red'){throw 'Failed scan was not red.'}}
        if(Get-RemnexaActiveProgress){throw 'Failed progress remained active.'}
    }

    It 'respects exclusions and reports junctions without scanning their targets' {
        $outside=Join-Path $script:avProgressFixture 'outside-scan-roots'
        New-Item -ItemType Directory -Path $outside|Out-Null
        [IO.File]::WriteAllText((Join-Path $outside 'do-not-scan.txt'),'harmless fixture')
        $link=Join-Path $env:APPDATA 'linked-folder'
        New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
        $configPath=Join-Path $script:avProgressFixture 'config.json'
        $config=Get-Content $configPath -Raw -Encoding utf8|ConvertFrom-Json
        $config.ExcludedPaths=@($env:TEMP)
        $config|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $configPath -Encoding utf8
        $result=Invoke-ClamAVScan -ScanType Quick
        if($result.FilesTotal -ne 6 -or $result.FilesReported -ne 6 -or $result.InventorySkipped -ne 1 -or $result.CoverageComplete){throw 'Excluded or linked files were scanned, or skips were hidden.'}
        & $script:avProgressModule {
            if(@($script:FixtureFiles|Where-Object{$_ -match 'do-not-scan|temp.txt|linked-folder'}).Count){throw 'A forbidden fixture reached the scanner.'}
        }
    }

    It 'retains findings as warnings without moving or deleting any file by default' {
        & $script:avProgressModule {$script:FixtureMode='Finding'}
        $results=@(Invoke-ClamAVScan -ScanType Quick)
        if($results.Count -ne 7 -or @($results|Where-Object Status -ne 'Infected').Count){throw 'Finding results were lost.'}
        foreach($result in $results){if(-not(Test-Path -LiteralPath $result.Path) -or $result.Quarantined){throw 'A reporting-only scan changed a file.'}}
        & $script:avProgressModule {if($script:FixtureFrames[$script:FixtureFrames.Count-1].Color -ne 'Yellow'){throw 'Findings were presented green.'}}
    }

    It 'preserves pipeline quarantine restore and closes each progress operation' {
        $root=Join-Path $script:avProgressFixture 'quarantine'
        New-Item -ItemType Directory -Path $root|Out-Null
        foreach($id in @('first','second')){
            $source=Join-Path $root ($id+'.bin')
            [IO.File]::WriteAllText($source,'harmless quarantine fixture')
            $destination=Join-Path $script:avProgressFixture ('restored/'+$id+'.txt')
            $manifest=@{QuarantineId=$id;Status='Quarantined';OriginalPath=$destination;QuarantinedPath=$source;Signature='Fixture.NoThreat';Sha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();RestoredAt=''}
            $manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root ($id+'.json')) -Encoding utf8
        }
        $results=@(@('first','second')|Restore-FromClamAVQuarantine -Force -Confirm:$false)
        if($results.Count -ne 2 -or @($results|Where-Object Status -ne 'Restored').Count){throw 'Pipeline restore behavior was changed.'}
        foreach($result in $results){if(-not(Test-Path -LiteralPath $result.RestoredPath)){throw 'A harmless fixture was not restored.'}}
        if(Get-RemnexaActiveProgress){throw 'Restoration left progress active.'}
    }

    It 'shows a cancelled restore preview and rejects a changed quarantine hash' {
        $root=Join-Path $script:avProgressFixture 'quarantine'
        New-Item -ItemType Directory -Path $root|Out-Null
        $source=Join-Path $root 'preview.bin'
        [IO.File]::WriteAllText($source,'harmless quarantine fixture')
        $destination=Join-Path $script:avProgressFixture 'restored/preview.txt'
        $manifest=@{QuarantineId='preview';Status='Quarantined';OriginalPath=$destination;QuarantinedPath=$source;Signature='Fixture.NoThreat';Sha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();RestoredAt=''}
        $manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'preview.json') -Encoding utf8
        Restore-FromClamAVQuarantine -Identifier preview -Force -WhatIf|Out-Null
        & $script:avProgressModule {if($script:FixtureFrames[$script:FixtureFrames.Count-1].Outcome -ne 'Cancelled'){throw 'An unperformed preview was reported as success.'}}
        [IO.File]::WriteAllText($source,'changed harmless fixture')
        $rejected=$false
        try{Restore-FromClamAVQuarantine -Identifier preview -Force -Confirm:$false|Out-Null}catch{$rejected=$true}
        if(-not $rejected -or -not(Test-Path -LiteralPath $source) -or (Test-Path -LiteralPath $destination)){throw 'Restore integrity checks were bypassed.'}
        if(Get-RemnexaActiveProgress){throw 'Failed restoration left progress active.'}
    }
}
