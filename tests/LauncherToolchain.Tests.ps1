BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../scripts/LauncherToolchain.psm1') -Force
}
Describe 'Pinned launcher toolchain download recovery' {
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:fixture)
        $script:bytes = [Text.Encoding]::UTF8.GetBytes('harmless fake archive, never extracted or executed')
        $script:pin = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:bytes)).ToLowerInvariant()
    }
    It 'uses an exactly verified cached archive without requesting metadata or downloads' {
        InModuleScope LauncherToolchain -Parameters @{Root=$script:fixture;Bytes=$script:bytes;Pin=$script:pin} {
            param($Root,$Bytes,$Pin)
            Mock Get-RemnexaToolchainMirror {throw 'No network for a verified cache.'}
            Mock Receive-RemnexaToolchainArchive {throw 'No network for a verified cache.'}
            [IO.File]::WriteAllBytes((Join-Path $Root 'verified-zig.zip'),$Bytes)
            Get-RemnexaVerifiedLauncherArchive $Root '0.15.2' $Pin | Should -Be (Join-Path $Root 'verified-zig.zip')
            Should -Invoke Receive-RemnexaToolchainArchive -Times 0
            Should -Invoke Get-RemnexaToolchainMirror -Times 0
        }
    }
    It 'falls back after timeout and rejects wrong hashes before accepting matching bytes' {
        InModuleScope LauncherToolchain -Parameters @{Root=$script:fixture;Bytes=$script:bytes;Pin=$script:pin} {
            param($Root,$Bytes,$Pin)
            Mock Get-RemnexaToolchainMirror {@('https://first.example','https://second.example')}
            Mock Receive-RemnexaToolchainArchive {
                param($Uri,$Path)
                if($Uri -like 'https://first.example/*'){[IO.File]::WriteAllText($Path,'partial');throw [TimeoutException]::new()}
                if($Uri -like 'https://second.example/*'){[IO.File]::WriteAllText($Path,'tampered');return}
                [IO.File]::WriteAllBytes($Path,$Bytes)
            }
            $archive=Get-RemnexaVerifiedLauncherArchive $Root '0.15.2' $Pin
            (Get-FileHash $archive).Hash.ToLowerInvariant()|Should -Be $Pin
            Should -Invoke Receive-RemnexaToolchainArchive -Times 3 -Exactly
            @(Get-ChildItem $Root -Filter '.zig-download-*').Count|Should -Be 0
        }
    }
    It 'stops after at most two mirrors plus canonical and preserves the previous cache on failure' {
        InModuleScope LauncherToolchain -Parameters @{Root=$script:fixture;Pin=$script:pin} {
            param($Root,$Pin)
            Mock Get-RemnexaToolchainMirror {@('https://a.example','https://b.example','https://never.example')}
            Mock Receive-RemnexaToolchainArchive {param($Path)[IO.File]::WriteAllText($Path,'wrong hash')}
            [IO.File]::WriteAllText((Join-Path $Root 'verified-zig.zip'),'previous incomplete cache')
            {Get-RemnexaVerifiedLauncherArchive $Root '0.15.2' $Pin}|Should -Throw '*bounded*'
            Should -Invoke Receive-RemnexaToolchainArchive -Times 3 -Exactly
            Should -Invoke Receive-RemnexaToolchainArchive -ParameterFilter {$Uri -like '*never.example*'} -Times 0
            [IO.File]::ReadAllText((Join-Path $Root 'verified-zig.zip'))|Should -Be 'previous incomplete cache'
            @(Get-ChildItem $Root -Filter '.zig-download-*').Count|Should -Be 0
        }
    }
    It 'falls back to the fixed canonical source if mirror discovery is offline' {
        InModuleScope LauncherToolchain -Parameters @{Root=$script:fixture;Bytes=$script:bytes;Pin=$script:pin} {
            param($Root,$Bytes,$Pin)
            Mock Invoke-RestMethod {throw 'offline metadata endpoint'}
            Mock Receive-RemnexaToolchainArchive {param($Path)[IO.File]::WriteAllBytes($Path,$Bytes)}
            Get-RemnexaVerifiedLauncherArchive $Root '0.15.2' $Pin|Should -Not -BeNullOrEmpty
            Should -Invoke Receive-RemnexaToolchainArchive -Times 1 -ParameterFilter {$Uri -ceq 'https://ziglang.org/download/0.15.2/zig-x86_64-windows-0.15.2.zip'}
        }
    }
    It 'accepts only HTTPS mirror roots without credentials or query strings' {
        InModuleScope LauncherToolchain {
            Mock Invoke-RestMethod {"http://bad.example`nhttps://user:secret@bad.example`nhttps://bad.example/?q=x`nhttps://good.example/zig`n"}
            @(Get-RemnexaToolchainMirror)|Should -Be @('https://good.example/zig')
        }
    }
}
