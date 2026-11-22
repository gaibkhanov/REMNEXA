BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseSigning.psm1') -Force
}

Describe 'Release signing fails closed without changing certificate stores' {
    InModuleScope ReleaseSigning {
        It 'requires an exact certificate identity and an installed private key' {
            { Get-RemnexaSigningIdentity -Thumbprint 'not-a-thumbprint' } | Should -Throw '*40 hexadecimal*'
            Mock Get-Item { $null }
            { Get-RemnexaSigningIdentity -Thumbprint ('0' * 40) } | Should -Throw '*accessible private key*'
        }

        It 'rejects insecure or credential-bearing timestamp endpoints before accessing a private key' {
            Mock Get-RemnexaSigningIdentity { throw 'Must not access a private key.' }
            foreach ($endpoint in @('http://timestamp.digicert.com', 'https://name:secret@example.org', 'https://example.org:444', 'https://example.org/?key=value', 'https://example.org/#fragment', 'relative')) {
                { Get-RemnexaSigningContext -Thumbprint ('0' * 40) -TimestampServer $endpoint } | Should -Throw '*HTTPS RFC 3161*'
            }
            Should -Invoke Get-RemnexaSigningIdentity -Times 0
        }

        It 'rejects expired certificates and certificates without the code-signing EKU' {
            Mock Get-Item { [pscustomobject]@{ HasPrivateKey=$true; NotBefore=(Get-Date).AddDays(-3); NotAfter=(Get-Date).AddDays(-1) } }
            { Get-RemnexaSigningIdentity -Thumbprint ('0' * 40) } | Should -Throw '*not currently valid*'
            Mock Get-Item { [pscustomobject]@{ HasPrivateKey=$true; NotBefore=(Get-Date).AddDays(-1); NotAfter=(Get-Date).AddDays(1); EnhancedKeyUsageList=@([pscustomobject]@{ ObjectId='1.3.6.1.5.5.7.3.1' }) } }
            { Get-RemnexaSigningIdentity -Thumbprint ('0' * 40) } | Should -Throw '*does not permit code signing*'
        }

        It 'rejects an untrusted signing tool instead of running it' {
            $tool=Join-Path $TestDrive 'untrusted.exe'
            [IO.File]::WriteAllText($tool,'not executable')
            Mock Get-RemnexaSigningIdentity { [pscustomobject]@{ Certificate=@{}; MachineStore=$false } }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status='NotSigned'; SignerCertificate=$null } }
            { Get-RemnexaSigningContext -Thumbprint ('0' * 40) -SignToolPath $tool } | Should -Throw '*valid Microsoft*'
        }

        It 'requires a valid signature from the expected signer and a timestamp' {
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Thumbprint=('1' * 40) }; TimeStamperCertificate=@{} } }
            { Assert-RemnexaReleaseSignature -Path 'fixture' -Thumbprint ('0' * 40) } | Should -Throw '*verification failed*'
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Thumbprint=('0' * 40) }; TimeStamperCertificate=$null } }
            { Assert-RemnexaReleaseSignature -Path 'fixture' -Thumbprint ('0' * 40) } | Should -Throw '*verification failed*'
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status='HashMismatch'; SignerCertificate=[pscustomobject]@{ Thumbprint=('0' * 40) }; TimeStamperCertificate=@{} } }
            { Assert-RemnexaReleaseSignature -Path 'fixture' -Thumbprint ('0' * 40) } | Should -Throw '*verification failed*'
            Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Thumbprint=('0' * 40) }; TimeStamperCertificate=[pscustomobject]@{ Subject='Timestamp authority' } } }
            { Assert-RemnexaReleaseSignature -Path 'fixture' -Thumbprint ('0' * 40) } | Should -Not -Throw
        }
    }
}

Describe 'Only staged REMNEXA code is signed before manifest hashing' {
    InModuleScope ReleaseSigning {
        BeforeEach {
            $script:stage=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $script:stage 'app/Core'))
            [void][IO.Directory]::CreateDirectory((Join-Path $script:stage 'runtime'))
            foreach ($file in @('REMNEXA.exe','app/REMNEXA.ps1','app/Core/Fixture.psm1','app/Core/Fixture.psd1','runtime/pwsh.exe','runtime/ThirdParty.ps1')) {
                [IO.File]::WriteAllText((Join-Path $script:stage $file),'fixture')
            }
            $script:context=[pscustomobject]@{ Tool='signtool.exe'; TimestampServer='https://timestamp.digicert.com/'; Identity=[pscustomobject]@{ MachineStore=$false; Certificate=[pscustomobject]@{ Thumbprint=('0' * 40) } } }
            Mock Invoke-RemnexaSignTool {}
            Mock Assert-RemnexaReleaseSignature {}
        }

        It 'signs the launcher and every app script using SHA256 and verifies each; runtime is untouched' {
            $before=(Get-FileHash (Join-Path $script:stage 'runtime/ThirdParty.ps1')).Hash
            $report=Invoke-RemnexaPackageSigning -PackageDirectory $script:stage -Context $script:context
            $report.VerifiedFiles | Should -Be 4
            $report.Algorithm | Should -Be 'SHA256'
            Should -Invoke Invoke-RemnexaSignTool -Times 4 -Exactly -ParameterFilter { $Arguments[0] -eq 'sign' -and $Arguments -contains '/tr' -and $Arguments -contains '/td' -and $Arguments -contains 'SHA256' -and $Arguments[-1] -notmatch '[\\/]runtime[\\/]' }
            Should -Invoke Invoke-RemnexaSignTool -Times 4 -Exactly -ParameterFilter { $Arguments[0] -eq 'verify' -and $Arguments -contains '/all' -and $Arguments -contains '/tw' }
            Should -Invoke Assert-RemnexaReleaseSignature -Times 4 -Exactly
            (Get-FileHash (Join-Path $script:stage 'runtime/ThirdParty.ps1')).Hash | Should -Be $before
        }

        It 'uses the machine certificate store only when the selected identity belongs there' {
            $script:context.Identity.MachineStore=$true
            [void](Invoke-RemnexaPackageSigning -PackageDirectory $script:stage -Context $script:context)
            Should -Invoke Invoke-RemnexaSignTool -Times 4 -Exactly -ParameterFilter { $Arguments[0] -eq 'sign' -and $Arguments -contains '/sm' }
        }

        It 'does not report success or sign further files after a verification failure' {
            Mock Assert-RemnexaReleaseSignature { throw 'Signature verification failed.' }
            { Invoke-RemnexaPackageSigning -PackageDirectory $script:stage -Context $script:context } | Should -Throw '*verification failed*'
            Should -Invoke Invoke-RemnexaSignTool -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'sign' }
        }

        It 'refuses an incomplete package before invoking the signing tool' {
            [IO.File]::Delete((Join-Path $script:stage 'REMNEXA.exe'))
            { Invoke-RemnexaPackageSigning -PackageDirectory $script:stage -Context $script:context } | Should -Throw '*staged REMNEXA package*'
            Should -Invoke Invoke-RemnexaSignTool -Times 0
        }
    }
}
