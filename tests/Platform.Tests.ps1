BeforeAll {
    $script:platformRoot=Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:platformRoot 'Core/Platform.psm1') -Force
    $script:platformTemp=Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-Platform-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:platformTemp)
    $tool=Join-Path $script:platformRoot 'tools/Modules/zig/zig-x86_64-windows-0.15.2/zig.exe'
    $headers=Join-Path (Split-Path -Parent $tool) 'lib/libc/include/any-windows-any'
    [void][IO.Directory]::CreateDirectory((Join-Path $script:platformTemp 'native'))
    $script:probe=Join-Path $script:platformTemp 'native/platform-probe.exe'
    & $tool cc -target x86_64-windows-gnu -isystem $headers -std=c11 -Oz -s -fno-builtin -fno-stack-protector -nostdlib '-Wl,--entry,Entry' '-Wl,--subsystem,console' (Join-Path $PSScriptRoot 'fixtures/LauncherPlatformProbe.c') -lkernel32 -luser32 -lshell32 -ladvapi32 -o $script:probe
    if($LASTEXITCODE -ne 0){throw 'Platform probe compilation failed.'}
}
AfterAll {
    $full=[IO.Path]::GetFullPath($script:platformTemp)
    if((Split-Path -Parent $full).TrimEnd('\') -eq [IO.Path]::GetTempPath().TrimEnd('\') -and (Split-Path -Leaf $full) -match '^REMNEXA-Platform-[a-f0-9]{32}$'){
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
Describe 'Windows 11 client minimum requirement' {
    It 'accepts Windows 11 at build 22000 and later without using the marketing product name' {
        foreach($version in @('10.0.22000','10.0.26100','11.0.1')){
            if(-not(Test-RemnexaWindowsVersion -Version $version -ProductType WinNT)){throw ('Supported client was rejected: '+$version)}
        }
    }
    It 'matches independent OS inventory and enforces the production launcher requirement on the actual host' {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $supported=([int]$os.ProductType -eq 1 -and [version]$os.Version -ge [version]'10.0.22000')
        if((Get-RemnexaPlatformSupport).Supported -ne $supported){throw 'Platform check disagrees with independent OS inventory.'}
        $directory=Join-Path $script:platformTemp 'real-host'
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::Copy((Join-Path $script:platformRoot 'dist/launcher/REMNEXA.exe'),(Join-Path $directory 'REMNEXA.exe'))
        [IO.File]::WriteAllText((Join-Path $directory 'REMNEXA.ps1'),'exit 0')
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $directory 'REMNEXA.exe'))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.Environment['PATH']=$PSHOME;$info.ArgumentList.Add('--diagnose')
        $p=[Diagnostics.Process]::Start($info)
        try {
            $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
            if(-not $p.WaitForExit(20000)){$p.Kill($true);throw 'Real platform diagnosis timed out.'}
            $result=$stdout.GetAwaiter().GetResult()|ConvertFrom-Json
            $expected=if($supported){0}else{14}
            if($p.ExitCode -ne $expected -or $result.ok -ne $supported -or $stderr.GetAwaiter().GetResult()){throw 'Production launcher did not enforce the actual-host requirement.'}
        }finally{$p.Dispose()}
    }
    It 'rejects Windows 10, older versions, servers and an unknown product type' {
        foreach($sample in @(@('10.0.19045','WinNT'),@('10.0.21999','WinNT'),@('6.1.7601','WinNT'),@('10.0.26100','ServerNT'),@('10.0.26100','LanmanNT'),@('10.0.26100',''))){
            if(Test-RemnexaWindowsVersion -Version $sample[0] -ProductType $sample[1]){throw 'Unsupported Windows variant was accepted.'}
        }
    }
    It 'rejects an unsupported platform before module initialization, network workers or user-data creation' {
        $app=Join-Path $script:platformTemp 'app'
        [void][IO.Directory]::CreateDirectory((Join-Path $app 'Core'))
        [IO.File]::Copy((Join-Path $script:platformRoot 'REMNEXA.ps1'),(Join-Path $app 'REMNEXA.ps1'))
        [IO.File]::WriteAllText((Join-Path $app 'Core/Platform.psm1'),'function Get-RemnexaPlatformSupport { [pscustomobject]@{Supported=$false} }; Export-ModuleMember -Function Get-RemnexaPlatformSupport')
        Copy-Item -LiteralPath (Join-Path $script:platformRoot 'locales') -Destination $app -Recurse
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $data=Join-Path $script:platformTemp 'user-data-not-created';$info.Environment['LOCALAPPDATA']=$data
        foreach($arg in @('-NoProfile','-File',(Join-Path $app 'REMNEXA.ps1'),'-SelfTest','-NoElevation')){$info.ArgumentList.Add($arg)}
        $p=[Diagnostics.Process]::Start($info)
        try {
            $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
            if(-not $p.WaitForExit(15000)){$p.Kill($true);throw 'Unsupported-platform rejection timed out.'}
            if($p.ExitCode -ne 14 -or $stderr.GetAwaiter().GetResult() -notmatch 'Windows 11' -or $stdout.GetAwaiter().GetResult() -or (Test-Path -LiteralPath $data)){throw 'Unsupported startup did not stop cleanly before other application work.'}
        }finally{$p.Dispose()}
    }
    It 'enforces the same requirement in the real native launch path for <Mode>' -TestCases @(
        @{Mode='windows10';Expected=14},@{Mode='boundary';Expected=14},@{Mode='windows7';Expected=14},
        @{Mode='server';Expected=14},@{Mode='query_error';Expected=14},@{Mode='unavailable';Expected=14},
        @{Mode='windows11';Expected=11},@{Mode='future';Expected=11}
    ) {
        param($Mode,$Expected)
        $info=[Diagnostics.ProcessStartInfo]::new($script:probe)
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.Environment['REMNEXA_TEST_OS']=$Mode;$info.Environment['PATH']=''
        $info.ArgumentList.Add('--diagnose')
        $p=[Diagnostics.Process]::Start($info)
        try {
            $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
            if(-not $p.WaitForExit(5000)){$p.Kill($true);throw 'Native platform rejection timed out.'}
            $result=$stdout.GetAwaiter().GetResult()|ConvertFrom-Json
            if($p.ExitCode -ne $Expected -or $result.ok -or $stderr.GetAwaiter().GetResult()){throw ('Incorrect native platform outcome: '+$Mode)}
            if($Expected -eq 14 -and $result.message -notmatch 'Windows 11'){throw 'Native compatibility message was missing.'}
        }finally{$p.Dispose()}
    }
    It 'provides the unsupported-platform message in all six language resources' {
        foreach($language in @('de','en','es','fr','ru','tr')){
            $messages=Get-Content (Join-Path $script:platformRoot ('locales/'+$language+'.json')) -Raw -Encoding utf8|ConvertFrom-Json
            if($messages.Windows11Required -notmatch 'Windows 11' -or $messages.Windows11Required -notmatch '22000'){throw ('Missing platform text: '+$language)}
        }
    }
}
