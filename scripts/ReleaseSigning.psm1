#Requires -Version 7.5
Set-StrictMode -Version Latest

function Get-RemnexaSigningIdentity {
    param([Parameter(Mandatory)][string]$Thumbprint)
    if ($Thumbprint -notmatch '^[a-fA-F0-9]{40}$') { throw 'Specify an exact certificate-store SHA-1 thumbprint (40 hexadecimal characters).' }
    $now = Get-Date
    foreach ($store in @('CurrentUser', 'LocalMachine')) {
        $certificate = Get-Item -LiteralPath ("Cert:\$store\My\$Thumbprint") -ErrorAction SilentlyContinue
        if (-not $certificate -or -not $certificate.HasPrivateKey) { continue }
        if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now) { throw 'The code-signing certificate is not currently valid.' }
        if ($certificate.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.3') { throw 'The certificate does not permit code signing.' }
        $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
        try {
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::Online
            $chain.ChainPolicy.RevocationFlag = [Security.Cryptography.X509Certificates.X509RevocationFlag]::ExcludeRoot
            $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(15)
            [void]$chain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
            if (-not $chain.Build($certificate) -or $chain.ChainElements.Count -lt 2) {
                throw 'A trusted, non-self-signed code-signing certificate with a verifiable revocation chain is required.'
            }
        } finally { $chain.Dispose() }
        return [pscustomobject]@{ Certificate = $certificate; MachineStore = ($store -eq 'LocalMachine') }
    }
    throw 'No matching code-signing certificate with an accessible private key is installed.'
}

function Get-RemnexaSigningContext {
    param([Parameter(Mandatory)][string]$Thumbprint, [string]$SignToolPath,
          [string]$TimestampServer = 'https://timestamp.digicert.com')
    $uri = $null
    if (-not [Uri]::TryCreate($TimestampServer, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Use an HTTPS RFC 3161 timestamp endpoint without credentials, query or fragment.'
    }
    $identity = Get-RemnexaSigningIdentity -Thumbprint $Thumbprint
    if (-not $SignToolPath) {
        $command = Get-Command signtool.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $SignToolPath = $command.Source }
        else {
            $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
            if (Test-Path -LiteralPath $kits) {
                $SignToolPath = Get-ChildItem -LiteralPath $kits -Directory |
                    Where-Object { $_.Name -match '^10\.\d+\.\d+\.\d+$' } |
                    Sort-Object { [version]$_.Name } -Descending |
                    ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
                    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
            }
        }
    }
    if (-not $SignToolPath -or -not (Test-Path -LiteralPath $SignToolPath -PathType Leaf)) {
        throw 'Microsoft SignTool from the Windows SDK is required on the signing machine; specify -SignToolPath.'
    }
    $tool = (Resolve-Path -LiteralPath $SignToolPath).Path
    $signature = Get-AuthenticodeSignature -LiteralPath $tool
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation(?:,|$)') {
        throw 'SignTool must have a valid Microsoft Authenticode signature.'
    }
    [pscustomobject]@{ Identity = $identity; Tool = $tool; TimestampServer = $uri.AbsoluteUri }
}

function Invoke-RemnexaSignTool {
    param([Parameter(Mandatory)][string]$Tool, [Parameter(Mandatory)][string[]]$Arguments)
    $info = [Diagnostics.ProcessStartInfo]::new($Tool)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'SignTool timed out; no signed distribution will be published.'
        }
        if ($process.ExitCode -ne 0) {
            throw ('SignTool failed: ' + $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        }
    } finally { $process.Dispose() }
}

function Assert-RemnexaReleaseSignature {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Thumbprint)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $Thumbprint -or -not $signature.TimeStamperCertificate) {
        throw 'Signature verification failed: trusted expected signer and timestamp are required.'
    }
}

function Invoke-RemnexaPackageSigning {
    param([Parameter(Mandatory)][string]$PackageDirectory, [Parameter(Mandatory)]$Context)
    $root = [IO.Path]::GetFullPath($PackageDirectory)
    Import-Module (Join-Path $PSScriptRoot '../Core/PathSafety.psd1') -ErrorAction Stop
    $launcher = Join-Path $root 'REMNEXA.exe'
    $app = Join-Path $root 'app'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or -not (Test-Path -LiteralPath $app -PathType Container)) {
        throw 'Sign only a staged REMNEXA package containing REMNEXA.exe and app/.'
    }
    $files = @($launcher) + @(Get-ChildItem -LiteralPath $app -File -Recurse -Force |
        Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') } | Sort-Object FullName | Select-Object -ExpandProperty FullName)
    if ($files.Count -lt 2) { throw 'The staged package contains no PowerShell application sources.' }
    # Validate the entire set before signing. Never re-sign third-party runtime files.
    foreach ($file in $files) {
        if (-not (Get-RemnexaPathSafety $file).IsSafe) { throw 'Unsafe signing input.' }
    }
    $thumbprint = $Context.Identity.Certificate.Thumbprint
    foreach ($file in $files) {
        $arguments = @('sign', '/s', 'My', '/sha1', $thumbprint, '/fd', 'SHA256', '/tr', $Context.TimestampServer, '/td', 'SHA256')
        if ($Context.Identity.MachineStore) { $arguments += '/sm' }
        Invoke-RemnexaSignTool -Tool $Context.Tool -Arguments ($arguments + @($file))
        Invoke-RemnexaSignTool -Tool $Context.Tool -Arguments @('verify', '/pa', '/all', '/tw', $file)
        Assert-RemnexaReleaseSignature -Path $file -Thumbprint $thumbprint
    }
    [pscustomobject]@{ CertificateThumbprint = $thumbprint; Algorithm = 'SHA256';
        TimestampServer = $Context.TimestampServer; VerifiedFiles = $files.Count }
}

Export-ModuleMember -Function Get-RemnexaSigningContext, Invoke-RemnexaPackageSigning
