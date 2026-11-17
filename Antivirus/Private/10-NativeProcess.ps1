$nativeProcessModule = Join-Path $PSScriptRoot '..\..\Core\NativeProcess.psd1'
Import-Module -Name $nativeProcessModule -Force -ErrorAction Stop

# Private compatibility wrappers preserve the existing Antivirus module API.
function ConvertTo-AVNativeArgument {
    param([AllowEmptyString()][string]$Argument)
    return ConvertTo-RemnexaNativeArgument -Argument $Argument
}

function Invoke-AVNativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$ArgumentList = @(),
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600,
        [AllowEmptyString()][string]$WorkingDirectory = '',
        [scriptblock]$OnOutput,
        [scriptblock]$OnHeartbeat,
        [scriptblock]$CaptureFilter,
        [ValidateSet('Idle','BelowNormal','Normal')][string]$ProcessPriority='Normal',
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None
    )

    if (-not $OnHeartbeat) {
        $activeProgress = Get-RemnexaActiveProgress
        if ($activeProgress) {
            $updater = Get-Command Update-RemnexaProgress
            $OnHeartbeat = { param($Event) & $updater $activeProgress }.GetNewClosure()
            # freshclam exposes useful update stages. Version/signature tools
            # can print long technical metadata that does not belong in the UI.
            if (-not $OnOutput -and [IO.Path]::GetFileName($FilePath) -ieq 'freshclam.exe') {
                $OnOutput = { param($Line,$Stream) & $updater $activeProgress -CurrentItem $Line }.GetNewClosure()
            }
        }
    }
    return Invoke-RemnexaNativeProcess -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -WorkingDirectory $WorkingDirectory -OnOutput $OnOutput -OnHeartbeat $OnHeartbeat -CaptureFilter $CaptureFilter -ProcessPriority $ProcessPriority -CancellationToken $CancellationToken
}
