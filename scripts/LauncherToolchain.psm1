Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-RemnexaToolchainMirror {
    # Availability hints only. Archive authenticity comes from the immutable
    # SHA-256 pin in Install-LauncherToolchain.ps1, never from this remote list.
    try {
        $list = Invoke-RestMethod -Uri 'https://ziglang.org/download/community-mirrors.txt' -TimeoutSec 10
        if ($list -isnot [string] -or $list.Length -gt 65536) { return }
        $valid = @(foreach ($line in ($list -split '\r?\n')) {
            $uri = $null
            if ([uri]::TryCreate($line.Trim(), [UriKind]::Absolute, [ref]$uri) -and
                $uri.Scheme -eq 'https' -and $uri.Host -and -not $uri.UserInfo -and
                -not $uri.Query -and -not $uri.Fragment) { $uri.AbsoluteUri.TrimEnd('/') }
        })
        if ($valid.Count) { $valid | Sort-Object -Unique | Get-Random -Count ([Math]::Min(2, $valid.Count)) }
    } catch { Write-Verbose 'Mirror discovery unavailable; using the canonical Zig endpoint.' }
}

function Receive-RemnexaToolchainArchive {
    param([string]$Uri, [string]$Path)
    $curl = Join-Path $env:SystemRoot 'System32/curl.exe'
    & $curl --silent --show-error --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --max-filesize 110000000 --retry 0 --output $Path $Uri
    if ($LASTEXITCODE -ne 0) { throw 'Toolchain transfer failed or exceeded its bounded timeout.' }
}

function Get-RemnexaVerifiedLauncherArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][ValidatePattern('\A\d+\.\d+\.\d+\z')][string]$Version,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{64}\z')][string]$SHA256)

    $root = [IO.Path]::GetFullPath($Directory)
    [void][IO.Directory]::CreateDirectory($root)
    $archive = Join-Path $root 'verified-zig.zip'
    if ((Test-Path -LiteralPath $archive -PathType Leaf) -and
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $SHA256) { return $archive }

    $filename = 'zig-x86_64-windows-' + $Version + '.zip'
    $sources = @(@(Get-RemnexaToolchainMirror | Select-Object -First 2 | ForEach-Object { $_ + '/' + $filename + '?source=remnexa_ci' }) +
        @('https://ziglang.org/download/' + $Version + '/' + $filename))
    $stage = Join-Path $root ('.zig-download-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        foreach ($source in $sources) {
            try {
                Write-Host ('Downloading pinned Zig compiler from ' + ([uri]$source).Host)
                Receive-RemnexaToolchainArchive -Uri $source -Path $stage
                if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash.ToLowerInvariant() -cne $SHA256) {
                    throw 'Toolchain SHA-256 mismatch.'
                }
                # Never replace an existing archive with incomplete/unverified bytes.
                [IO.File]::Move($stage, $archive, $true)
                return $archive
            } catch { Write-Verbose ('Rejected toolchain candidate: ' + $_.Exception.Message) }
            finally { if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
        }
        throw 'Verified Zig toolchain unavailable after bounded mirror/canonical attempts.'
    } finally { if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
}

Export-ModuleMember -Function @('Get-RemnexaVerifiedLauncherArchive')
