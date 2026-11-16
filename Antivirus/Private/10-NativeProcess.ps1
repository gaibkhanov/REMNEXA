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
        [AllowEmptyString()][string]$WorkingDirectory = ''
    )

    return Invoke-RemnexaNativeProcess -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -WorkingDirectory $WorkingDirectory
}
