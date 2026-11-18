function Stop-ClamAVScanEngine {
    [CmdletBinding()]
    param()
    $engine=$script:AVPrivateWorker
    $script:AVPrivateWorker=$null
    if($engine) {
        try{$engine.Client.Dispose()}catch{$_.Exception.Data['NativeCleanupFailed']=$true;throw}
        try{Remove-AVWorkerTemporaryDirectory -Path $engine.Temp -Root $engine.Root}catch{Write-Verbose $_.Exception.Message}
    }
}

function Get-ClamAVScanEngineState {
    [CmdletBinding()]
    param()
    $engine=$script:AVPrivateWorker
    if($engine -and -not $engine.Client.Alive){Stop-ClamAVScanEngine;$engine=$null}
    if(-not $engine){return [pscustomobject]@{Running=$false;Backend='none';ProcessId=$null;Threads=0}}
    [pscustomobject]@{Running=$true;Backend='libclamav-private';ProcessId=$engine.Client.ProcessId;Threads=$engine.Threads;Version=$engine.Version;TokenMode=$engine.Client.TokenMode;MemoryLimit=$engine.MemoryLimit;LoadedUtc=$engine.LoadedUtc}
}
