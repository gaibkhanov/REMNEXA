BeforeAll {
    $script:downloadRoot=Split-Path -Parent $PSScriptRoot
    if(-not('Remnexa.Tests.DownloadHandler' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'fixtures/DownloadHandler.cs')}
}
Describe 'Bounded streaming package downloads without a second progress renderer' {
    BeforeEach {
        Import-Module (Join-Path $script:downloadRoot 'Antivirus/Antivirus.psd1') -Force
        $script:downloadModule=Get-Module Antivirus
        & $script:downloadModule {Set-RemnexaProgressRendering $false}
        $script:downloadHandler=[Remnexa.Tests.DownloadHandler]::new()
        $script:downloadClient=[Net.Http.HttpClient]::new($script:downloadHandler)
        $script:downloadFile=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.zip')
    }
    AfterEach {$script:downloadClient.Dispose();Remove-Module Antivirus -ErrorAction SilentlyContinue}
    It 'streams identical bytes with <Mode> content length and releases the output file' -TestCases @(@{Mode='Known'},@{Mode='Unknown'}) {
        param($Mode)
        $script:downloadHandler.Mode=$Mode
        & $script:downloadModule {param($File,$Client)Receive-AVPackage -Uri 'https://invalid.example/package.zip' -OutFile $File -Client $Client} $script:downloadFile $script:downloadClient
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($script:downloadFile))) | Should -Be ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:downloadHandler.Payload)))
        $stream=[IO.File]::Open($script:downloadFile,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$stream.Dispose()
        $script:downloadHandler.Requests | Should -Be 1
        & $script:downloadModule {Get-RemnexaActiveProgress} | Should -BeNullOrEmpty
    }
    It 'rejects <Mode> responses and does not retain a partial archive' -TestCases @(@{Mode='Downgrade'},@{Mode='RedirectLoop'},@{Mode='Failure'},@{Mode='Truncated'},@{Mode='Oversize'}) {
        param($Mode)
        $script:downloadHandler.Mode=$Mode
        { & $script:downloadModule {param($File,$Client)Receive-AVPackage -Uri 'https://invalid.example/package.zip' -OutFile $File -Client $Client} $script:downloadFile $script:downloadClient } | Should -Throw
        Test-Path -LiteralPath $script:downloadFile | Should -BeFalse
        ($script:downloadHandler.Requests -le 6) | Should -BeTrue
        & $script:downloadModule {Get-RemnexaActiveProgress} | Should -BeNullOrEmpty
    }
    It 'does not overwrite existing files and rejects plaintext transport before any request' {
        [IO.File]::WriteAllText($script:downloadFile,'existing')
        { & $script:downloadModule {param($File,$Client)Receive-AVPackage -Uri 'https://invalid.example/package.zip' -OutFile $File -Client $Client} $script:downloadFile $script:downloadClient } | Should -Throw '*overwrite*'
        [IO.File]::ReadAllText($script:downloadFile) | Should -Be 'existing'
        { & $script:downloadModule {param($File,$Client)Receive-AVPackage -Uri 'http://invalid.example/package.zip' -OutFile $File -Client $Client} $script:downloadFile $script:downloadClient } | Should -Throw '*HTTPS*'
        $script:downloadHandler.Requests | Should -Be 0
    }
    It 'times out a stalled request without leaving an archive or active progress' {
        $script:downloadHandler.Mode='Timeout'
        $watch=[Diagnostics.Stopwatch]::StartNew()
        { & $script:downloadModule {param($File,$Client)Receive-AVPackage -Uri 'https://invalid.example/package.zip' -OutFile $File -Client $Client -TimeoutSeconds 1} $script:downloadFile $script:downloadClient } | Should -Throw -ExceptionType ([TimeoutException])
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 5
        Test-Path -LiteralPath $script:downloadFile | Should -BeFalse
        & $script:downloadModule {Get-RemnexaActiveProgress} | Should -BeNullOrEmpty
    }
    It 'cleans a partially written download when the user cancels without changing existing files' {
        $sentinel=Join-Path $TestDrive 'installed-engine.txt'
        [IO.File]::WriteAllText($sentinel,'previous installation')
        InModuleScope Antivirus -Parameters @{File=$script:downloadFile;Client=$script:downloadClient} {
            param($File,$Client)
            Mock Wait-AVDownloadTask {
                if($Progress.Completed -ge 65536){
                    $CancellationState.UserRequested=$true;$Cancellation.Cancel()
                    $Cancellation.Token.ThrowIfCancellationRequested()
                }
                $Task.GetAwaiter().GetResult()
            }
            {Receive-AVPackage -Uri 'https://invalid.example/package.zip' -OutFile $File -Client $Client} | Should -Throw -ExceptionType ([OperationCanceledException])
            Test-Path -LiteralPath $File | Should -BeFalse
            Get-RemnexaActiveProgress | Should -BeNullOrEmpty
        }
        [IO.File]::ReadAllText($sentinel) | Should -Be 'previous installation'
    }
}
