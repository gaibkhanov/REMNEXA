BeforeAll {
    $script:userPackageRoot=Split-Path -Parent $PSScriptRoot
    $script:userPackageOutput=Join-Path $script:userPackageRoot ('dist/package-tests-'+[guid]::NewGuid().ToString('N'))
    $command=Get-Command git -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    $git=if($command){$command.Source}else{'C:/Program Files/Git/cmd/git.exe'}
    $script:userPackage=& (Join-Path $script:userPackageRoot 'scripts/Build-Release.ps1') -OutputDirectory $script:userPackageOutput -GitPath $git
}
AfterAll {
    $full=[IO.Path]::GetFullPath($script:userPackageOutput)
    if((Split-Path -Parent $full) -eq (Join-Path $script:userPackageRoot 'dist') -and (Split-Path -Leaf $full) -match '^package-tests-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}
}
Describe 'Clean end-user Windows distribution' {
    It 'exposes one launcher and excludes developer or private artifacts' {
        $top=@(Get-ChildItem -LiteralPath $script:userPackage.Directory|Select-Object -ExpandProperty Name|Sort-Object)
        if(($top -join ',') -cne 'app,README.txt,REMNEXA.exe'){throw ('Unexpected user-package root: '+($top -join ','))}
        $files=@(Get-ChildItem -LiteralPath $script:userPackage.Directory -Recurse -File)
        foreach($file in $files){
            $relative=[IO.Path]::GetRelativePath($script:userPackage.Directory,$file.FullName)
            if($relative -match '(^|[\\/])(\.git|tests|tools|scripts|src|dist|examples|Backup-[^\\/]*|ScanSessions)([\\/]|$)' -or $relative -match '\.(cmd|log|jsonl|tmp)$'){throw ('Developer/private payload: '+$relative)}
        }
    }
    It 'verifies every copied file and preserves runtime module and license dependencies' {
        $root=$script:userPackage.Directory
        $manifest=Get-Content (Join-Path $root 'app/package-manifest.json') -Raw|ConvertFrom-Json
        if($manifest.RuntimeIncluded -or $manifest.Signed -or $manifest.PackageStatus -ne 'LauncherPreview'){throw 'Incorrect distribution claims.'}
        foreach($record in $manifest.Files){if((Get-FileHash -LiteralPath (Join-Path $root $record.Path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.SHA256){throw 'Copied application hash mismatch.'}}
        foreach($relative in @('REMNEXA.ps1','Core/PathSafety.psd1','Antivirus/Antivirus.psd1','Antivirus/Workers/ScanHost.ps1','Antivirus/Workers/COPYING.txt','config/antivirus.json','assets/remnexa-logo.png','assets/icons/remnexa.ico','LICENSE')){if(-not(Test-Path -LiteralPath (Join-Path $root ('app/'+$relative)))){throw ('Required application file missing: '+$relative)}}
        foreach($code in @('de','en','es','fr','ru','tr')){[void](Get-Content (Join-Path $root ('app/locales/'+$code+'.json')) -Raw|ConvertFrom-Json)}
    }
    It 'starts the real packaged application through the native launcher and passes self-tests' {
        $info=[Diagnostics.ProcessStartInfo]::new($script:userPackage.Launcher)
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.WorkingDirectory=[IO.Path]::GetTempPath();$info.Environment['PATH']=$PSHOME
        foreach($arg in @('-SelfTest','-NoElevation')){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($info)
        try{
            $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(45000)){$process.Kill($true);throw 'Packaged application startup timed out.'}
            if($process.ExitCode -ne 0){throw ($out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult())}
            $result=$out.GetAwaiter().GetResult()|ConvertFrom-Json
            if(-not $result.Passed -or @($result.Checks).Count -ne 12){throw 'Packaged self-test did not pass all checks.'}
        }finally{$process.Dispose()}
    }
    It 'has a valid ZIP checksum and refuses to overwrite an existing user package' {
        if((Get-FileHash $script:userPackage.Archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $script:userPackage.SHA256){throw 'ZIP checksum differs.'}
        $command=Get-Command git -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
        $git=if($command){$command.Source}else{'C:/Program Files/Git/cmd/git.exe'}
        $rejected=$false
        try{& (Join-Path $script:userPackageRoot 'scripts/Build-Release.ps1') -OutputDirectory $script:userPackageOutput -GitPath $git}catch{$rejected=$true}
        if(-not $rejected){throw 'Existing user package was overwritten.'}
    }
}
