BeforeAll {
    $script:launcherRoot=Split-Path -Parent $PSScriptRoot
    $script:launcherBinary=Join-Path $script:launcherRoot 'dist/launcher/REMNEXA.exe'
    if(-not(Test-Path -LiteralPath $script:launcherBinary)){throw 'Build launcher before running tests: scripts/Build-Launcher.ps1'}
    $script:launcherTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA Launcher Grüße '+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:launcherTemp)
    function Invoke-LauncherFixture {
        param([string]$Directory,[string[]]$Arguments=@('--diagnose'),[switch]$NoRuntime,[switch]$UsePath)
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $Directory 'REMNEXA.exe'))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.WorkingDirectory=[IO.Path]::GetTempPath()
        $info.Environment['ProgramFiles']=$script:launcherTemp;$info.Environment['ProgramW6432']=$script:launcherTemp
        $info.Environment['PATH']=if($NoRuntime){''}else{$PSHOME}
        foreach($arg in $Arguments){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($info)
        try{
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(30000)){$process.Kill($true);throw 'Launcher timed out.'}
            [pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.GetAwaiter().GetResult();Error=$stderr.GetAwaiter().GetResult()}
        }finally{$process.Dispose()}
    }
    function New-LauncherFixture {
        param([string]$Name,[switch]$AppLayout)
        $directory=Join-Path $script:launcherTemp $Name;[void][IO.Directory]::CreateDirectory($directory)
        Copy-Item -LiteralPath $script:launcherBinary -Destination (Join-Path $directory 'REMNEXA.exe')
        $app=if($AppLayout){Join-Path $directory 'app'}else{$directory};[void][IO.Directory]::CreateDirectory($app)
        $fixture=@'
param([string]$Name,[int]$ReturnCode=0)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[ordered]@{Name=$Name;Other=@($args);Version=$PSVersionTable.PSVersion.ToString();WorkingDirectory=(Get-Location).Path}|ConvertTo-Json -Compress
exit $ReturnCode
'@
        [IO.File]::WriteAllText((Join-Path $app 'REMNEXA.ps1'),$fixture)
        return $directory
    }
}
AfterAll {
    $full=[IO.Path]::GetFullPath($script:launcherTemp)
    if($full.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -match '^REMNEXA Launcher Grüße [a-f0-9]{32}$'){Remove-Item -LiteralPath $full -Recurse -Force}
}
Describe 'Native Windows launcher' {
    It 'is an x64 native PE with embedded version and icon resources' {
        $bytes=[IO.File]::ReadAllBytes($script:launcherBinary);$pe=[BitConverter]::ToInt32($bytes,0x3c)
        if($bytes[0] -ne 0x4d -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664){throw 'Not an x64 PE.'}
        if([BitConverter]::ToUInt32($bytes,$pe+24+112+14*8) -ne 0){throw 'Launcher unexpectedly requires the CLR.'}
        if([Diagnostics.FileVersionInfo]::GetVersionInfo($script:launcherBinary).ProductName -ne 'REMNEXA'){throw 'Version resource missing.'}
        $icon=[IO.File]::ReadAllBytes((Join-Path $script:launcherRoot 'assets/icons/remnexa.ico'))
        if([BitConverter]::ToUInt16($icon,4) -ne 7){throw 'Icon resolution count differs.'}
        $sizes=foreach($i in 0..6){if($icon[6+16*$i] -eq 0){256}else{[int]$icon[6+16*$i]}}
        if(($sizes -join ',') -ne '16,24,32,48,64,128,256'){throw 'Incorrect icon sizes.'}
        if([Text.Encoding]::Unicode.GetString($bytes) -notmatch 'REMNEXA Windows Launcher'){throw 'Embedded resources missing.'}
    }
    It 'finds installed PowerShell from an unrelated working directory and a Unicode path with spaces' {
        $directory=New-LauncherFixture 'source with spaces'
        $result=Invoke-LauncherFixture $directory;$data=$result.Output|ConvertFrom-Json
        if($result.ExitCode -or -not $data.ok -or $data.script -ne (Join-Path $directory 'REMNEXA.ps1') -or [version]$data.version -lt [version]'7.5'){throw 'Runtime/source discovery failed.'}
    }
    It 'resolves the end-user app layout and preserves quoted metacharacters without shell evaluation' {
        $directory=New-LauncherFixture 'package with spaces' -AppLayout
        $value='Grüße 🧪 $() ; & "quoted" C:\path with spaces\'
        $result=Invoke-LauncherFixture $directory -Arguments @('-Name',$value)
        $data=$result.Output|ConvertFrom-Json
        if($result.ExitCode -or $data.Name -cne $value -or $data.WorkingDirectory -ne $directory){throw ('Unsafe argument or working-directory handling: '+$result.Output+$result.Error)}
    }
    It 'reports missing runtime and missing app separately without requiring administrator rights' {
        $directory=New-LauncherFixture 'no runtime'
        $result=Invoke-LauncherFixture $directory -NoRuntime
        if($result.ExitCode -ne 10 -or ($result.Output|ConvertFrom-Json).ok){throw 'Missing runtime was not reported.'}
        Remove-Item -LiteralPath (Join-Path $directory 'REMNEXA.ps1')
        if((Invoke-LauncherFixture $directory -NoRuntime).ExitCode -ne 11){throw 'Missing application was not reported.'}
    }
    It 'rejects a corrupt bundled runtime and falls back to the installed runtime' {
        $directory=New-LauncherFixture 'invalid portable runtime'
        [void][IO.Directory]::CreateDirectory((Join-Path $directory 'runtime'))
        [IO.File]::WriteAllText((Join-Path $directory 'runtime/pwsh.exe'),'not executable')
        $result=Invoke-LauncherFixture $directory
        if($result.ExitCode -or ($result.Output|ConvertFrom-Json).runtime -ne (Join-Path $PSHOME 'pwsh.exe')){throw 'Invalid portable fallback failed.'}
    }
    It 'propagates an application failure code without wrapping or rewriting the script' {
        $directory=New-LauncherFixture 'child failure'
        if((Invoke-LauncherFixture $directory -Arguments @('-ReturnCode','7')).ExitCode -ne 7){throw 'Application exit code lost.'}
    }
    It 'does not override execution policy or request automatic elevation' {
        $source=[IO.File]::ReadAllText((Join-Path $script:launcherRoot 'src/Launcher/launcher.c'))
        $manifest=[IO.File]::ReadAllText((Join-Path $script:launcherRoot 'src/Launcher/launcher.manifest'))
        if($source -match 'ExecutionPolicy|ShellExecute|runas|CREATE_NEW_CONSOLE' -or $manifest -notmatch 'level="asInvoker"'){throw 'Launcher overrides policy/elevation/console ownership.'}
        $directory=New-LauncherFixture 'normal privileges'
        $result=Invoke-LauncherFixture $directory;$state=$result.Output|ConvertFrom-Json
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$expected=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if($state.elevated -ne $expected){throw 'Launcher changed elevation.'}
    }
    It 'keeps all source compatibility routes and main-menu modules reachable' {
        foreach($name in @('REMNEXA-Antivirus','REMNEXA-Autostart','REMNEXA-Deinstallation','REMNEXA-Dienste')){
            $text=[IO.File]::ReadAllText((Join-Path $script:launcherRoot ($name+'.cmd')))
            if($text -notmatch 'REMNEXA.cmd' -or $text -match 'ExecutionPolicy') {throw 'Compatibility route bypassed central entry.'}
        }
    }
}
