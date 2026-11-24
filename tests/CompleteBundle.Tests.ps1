BeforeAll {Import-Module (Join-Path $PSScriptRoot '../scripts/BundlePayload.psm1') -Force}
Describe 'Complete bundle integrity and distribution boundaries' {
    BeforeEach {
        $script:bundleFixture=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($script:bundleFixture)
        function New-TestZip {
            param($Name,[hashtable]$Files)
            $path=Join-Path $script:bundleFixture $Name
            $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
            try{foreach($key in $Files.Keys){$entry=$zip.CreateEntry($key);$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write($Files[$key])}finally{$writer.Dispose()}}}finally{$zip.Dispose()}
            $path
        }
        function New-ClamFixture {
            $payload=@{}
            foreach($name in @('clamscan.exe','freshclam.exe','sigtool.exe','libclamav.dll','libfreshclam.dll','vcruntime140.dll','msvcp140.dll','COPYING.txt','COPYING/license.txt','debug.pdb','linker.lib','include/test.h')){$payload['clam/'+$name]='benign packaging fixture'}
            $script:clamFixtureArchive=New-TestZip 'clam.zip' $payload
            $script:sourceFixtureArchive=Join-Path $script:bundleFixture 'source.tar.gz';[IO.File]::WriteAllText($script:sourceFixtureArchive,'benign upstream source fixture')
            $script:fixturePins=[pscustomobject]@{clamAV=[pscustomobject]@{version='1.0.0';sha256=(Get-FileHash $script:clamFixtureArchive).Hash.ToLowerInvariant()};clamAVSource=[pscustomobject]@{version='1.0.0';sha256=(Get-FileHash $script:sourceFixtureArchive).Hash.ToLowerInvariant();uri='https://github.com/Cisco-Talos/clamav/releases/download/fixture/source.tar.gz'}}
            $script:fixtureDatabase=Join-Path $script:bundleFixture 'database';[void][IO.Directory]::CreateDirectory($script:fixtureDatabase)
            $script:fixtureVerification=Join-Path $script:bundleFixture 'verified.json'
            $records=foreach($name in @('main.cvd','daily.cld','bytecode.cvd')){$path=Join-Path $script:fixtureDatabase $name;[IO.File]::WriteAllText($path,('benign database fixture '+$name));[pscustomobject]@{Name=$name;SHA256=(Get-FileHash $path).Hash.ToLowerInvariant()}}
            [IO.File]::WriteAllText((Join-Path $script:fixtureDatabase 'freshclam.dat'),'local cache must not be shipped')
            [IO.File]::WriteAllText((Join-Path $script:fixtureDatabase 'private.hdb'),'private additions must not be shipped')
            [pscustomobject]@{FreshClamExitCode=0;PreparedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');Databases=@($records)}|ConvertTo-Json -Depth 5|Set-Content $script:fixtureVerification -Encoding utf8
            $script:fixturePackage=Join-Path $script:bundleFixture 'package';[void][IO.Directory]::CreateDirectory($script:fixturePackage)
        }
        function Add-TestBundle {Add-RemnexaClamBundle -Archive $script:clamFixtureArchive -SourceArchive $script:sourceFixtureArchive -DatabasePath $script:fixtureDatabase -VerificationPath $script:fixtureVerification -PackageDirectory $script:fixturePackage -Pins $script:fixturePins}
    }
    It 'rejects a missing or mismatched archive before using its contents' {
        {Assert-RemnexaBundleArchive -Path (Join-Path $script:bundleFixture 'missing.zip') -SHA256 ('0'*64)}|Should -Throw
        $path=New-TestZip 'bytes.zip' @{'pwsh.exe'='benign'}
        {Assert-RemnexaBundleArchive -Path $path -SHA256 ('0'*64)}|Should -Throw '*checksum*'
    }
    It 'accepts the exact runtime and rejects changed or extra DLL files' {
        $archive=New-TestZip 'runtime.zip' @{'pwsh.exe'='benign';'runtime.dll'='verified library'}
        $runtime=Join-Path $script:bundleFixture 'runtime';[IO.Compression.ZipFile]::ExtractToDirectory($archive,$runtime)
        $pin=@{sha256=(Get-FileHash $archive).Hash.ToLowerInvariant()}
        Assert-RemnexaBundleRuntime -Directory $runtime -Archive $archive -Pin $pin
        [IO.File]::WriteAllText((Join-Path $runtime 'runtime.dll'),'changed')
        {Assert-RemnexaBundleRuntime -Directory $runtime -Archive $archive -Pin $pin}|Should -Throw '*differs*'
        [IO.File]::WriteAllText((Join-Path $runtime 'runtime.dll'),'verified library')
        [IO.File]::WriteAllText((Join-Path $runtime 'unexpected.dll'),'extra')
        {Assert-RemnexaBundleRuntime -Directory $runtime -Archive $archive -Pin $pin}|Should -Throw '*Unexpected*'
    }
    It 'copies portable dependencies databases and matching source without private or developer files' {
        New-ClamFixture
        $result=Add-TestBundle
        $result.Databases.Count|Should -Be 3
        foreach($name in @('clamscan.exe','freshclam.exe','libclamav.dll','vcruntime140.dll','msvcp140.dll','COPYING.txt','COPYING/license.txt','database/main.cvd','database/daily.cld','database/bytecode.cvd')){Test-Path (Join-Path $script:fixturePackage ('app/ClamAV/'+$name))|Should -BeTrue}
        foreach($name in @('debug.pdb','linker.lib','include/test.h','database/freshclam.dat','database/private.hdb')){Test-Path (Join-Path $script:fixturePackage ('app/ClamAV/'+$name))|Should -BeFalse}
        Test-Path (Join-Path $script:fixturePackage $result.SourcePath)|Should -BeTrue
        $configuration=Get-Content (Join-Path $script:fixturePackage 'app/ClamAV/freshclam.conf') -Raw
        $configuration|Should -Match '(?m)^DatabaseDirectory database$'
        $configuration.Contains($script:bundleFixture)|Should -BeFalse
    }
    It 'rejects changed definitions after FreshClam verification' {
        New-ClamFixture;[IO.File]::WriteAllText((Join-Path $script:fixtureDatabase 'daily.cld'),'tampered')
        {Add-TestBundle}|Should -Throw '*changed*'
    }
    It 'rejects stale signature snapshots and mismatched binary/source versions' {
        New-ClamFixture
        $data=Get-Content $script:fixtureVerification -Raw|ConvertFrom-Json;$data.PreparedAtUtc=[DateTimeOffset]::UtcNow.AddDays(-2).ToString('o');$data|ConvertTo-Json -Depth 5|Set-Content $script:fixtureVerification -Encoding utf8
        {Add-TestBundle}|Should -Throw '*24 hours*'
        $script:fixturePins.clamAVSource.version='0.9.0'
        {Add-TestBundle}|Should -Throw '*versions*'
    }
    It 'rejects traversal even in an archive supplied with its matching test checksum' {
        New-ClamFixture
        $script:clamFixtureArchive=New-TestZip 'unsafe.zip' @{'clam/clamscan.exe'='benign';'clam/../outside.dll'='must not extract'}
        $script:fixturePins.clamAV.sha256=(Get-FileHash $script:clamFixtureArchive).Hash.ToLowerInvariant()
        {Add-TestBundle}|Should -Throw '*Unsafe*'
        Test-Path (Join-Path $script:fixturePackage 'app/outside.dll')|Should -BeFalse
    }
    It 'defaults to Complete and refuses to emit an incomplete package when prerequisites are missing' -Tag CleanCheckout {
        $output=Join-Path $script:bundleFixture 'missing-output'
        $root=Split-Path -Parent $PSScriptRoot
        {& (Join-Path $root 'scripts/Build-Release.ps1') -OutputDirectory $output -ComponentDirectory $script:bundleFixture -GitPath 'C:/Program Files/Git/cmd/git.exe'}|Should -Throw '*Complete prerequisites*'
        Test-Path $output|Should -BeFalse
    }
}
