function Wait-AVDownloadTask {
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Progress,
          [Parameter(Mandatory)][Threading.CancellationTokenSource]$Cancellation,$ConsoleView,$CancellationState)
    while(-not $Task.IsCompleted){
        if($ConsoleView){
            for($key=0;$key -lt 16 -and [Console]::KeyAvailable;$key++){
                if([Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant() -eq 'C'){$CancellationState.UserRequested=$true;$Cancellation.Cancel()}
            }
        }
        $Cancellation.Token.ThrowIfCancellationRequested()
        Update-RemnexaProgress $Progress
        Start-Sleep -Milliseconds 100
    }
    return $Task.GetAwaiter().GetResult()
}

function Receive-AVPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri,[Parameter(Mandatory)][string]$OutFile,
          [ValidateRange(1,3600)][int]$TimeoutSeconds=900,
          [ValidateRange(1,1099511627776)][long]$MaximumBytes=1GB,
          [Net.Http.HttpClient]$Client)
    if(-not $Uri.IsAbsoluteUri -or $Uri.Scheme -ne 'https' -or $Uri.UserInfo){throw 'Package downloads require HTTPS without embedded credentials.'}
    if(Test-Path -LiteralPath $OutFile){throw 'Refusing to overwrite an existing download.'}
    $OutFile=[IO.Path]::GetFullPath($OutFile)
    if(-not(Get-RemnexaPathSafety (Split-Path -Parent $OutFile)).IsSafe){throw 'Unsafe download destination.'}
    $progress=New-RemnexaProgress -Activity (Get-RemnexaProgressText 'ProgressTaskDownload') -Unit (Get-RemnexaProgressText 'ProgressUnitBytes')
    $cancel=[Threading.CancellationTokenSource]::new();$cancel.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    $ownClient=$null -eq $Client;$response=$null;$source=$null;$target=$null;$request=$null;$created=$false;$complete=$false;$view=$null
    $cancellationState=[pscustomobject]@{UserRequested=$false}
    try {
        $view=New-AVScanWindow -InputOnly
        Update-RemnexaProgress $progress -Status (Get-RemnexaProgressText 'AVDownloadHint') -Force
        if($ownClient){
            $handler=[Net.Http.SocketsHttpHandler]::new();$handler.AllowAutoRedirect=$false;$handler.ConnectTimeout=[TimeSpan]::FromSeconds(15)
            $Client=[Net.Http.HttpClient]::new($handler,$true);$Client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
        }
        $current=$Uri
        for($redirect=0;$redirect -le 5;$redirect++){
            if($current.Scheme -ne 'https' -or $current.UserInfo){throw 'Insecure download redirect was rejected.'}
            $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$current)
            $response=Wait-AVDownloadTask -Task ($Client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token)) -Progress $progress -Cancellation $cancel -ConsoleView $view -CancellationState $cancellationState
            $request.Dispose();$request=$null
            if([int]$response.StatusCode -notin @(301,302,303,307,308)){break}
            if($redirect -eq 5 -or -not $response.Headers.Location){throw 'Too many or invalid download redirects.'}
            $current=[uri]::new($current,$response.Headers.Location)
            $response.Dispose();$response=$null
        }
        [void]$response.EnsureSuccessStatusCode()
        $length=if($null -ne $response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength}else{[long]-1}
        if($length -gt $MaximumBytes){throw 'Package exceeds the permitted download size.'}
        Update-RemnexaProgress $progress -Total $length -Force
        $source=Wait-AVDownloadTask -Task ($response.Content.ReadAsStreamAsync($cancel.Token)) -Progress $progress -Cancellation $cancel -ConsoleView $view -CancellationState $cancellationState
        $target=[IO.FileStream]::new($OutFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $created=$true;$bytes=[long]0;$buffer=[byte[]]::new(65536)
        while($true){
            $count=Wait-AVDownloadTask -Task ($source.ReadAsync($buffer,0,$buffer.Length,$cancel.Token)) -Progress $progress -Cancellation $cancel -ConsoleView $view -CancellationState $cancellationState
            if($count -eq 0){break}
            if($bytes+$count -gt $MaximumBytes){throw 'Package exceeds the permitted download size.'}
            $target.Write($buffer,0,$count);$bytes+=$count
            Update-RemnexaProgress $progress -Completed $bytes
        }
        if($length -ge 0 -and $bytes -ne $length){throw 'The package download is incomplete.'}
        $target.Flush($true);$target.Dispose();$target=$null
        $complete=$true;Complete-RemnexaProgress $progress
    }catch{
        if($cancel.IsCancellationRequested){
            if(-not $cancellationState.UserRequested){
                Complete-RemnexaProgress $progress -Outcome Failed
                throw [TimeoutException]::new((Get-RemnexaProgressText 'AVDownloadTimeout'),$_.Exception)
            }
            Complete-RemnexaProgress $progress -Outcome Cancelled
            throw [OperationCanceledException]::new((Get-RemnexaProgressText 'AVUpdateCancelled'),$_.Exception,$cancel.Token)
        }
        Complete-RemnexaProgress $progress -Outcome Failed
        throw
    }finally{
        $cancel.Cancel()
        if($target){$target.Dispose()};if($source){$source.Dispose()};if($response){$response.Dispose()};if($request){$request.Dispose()}
        if($ownClient -and $Client){$Client.Dispose()};$cancel.Dispose()
        if($view){$view.Dispose()}
        if(-not $complete -and $created -and (Test-Path -LiteralPath $OutFile)){[IO.File]::Delete($OutFile)}
    }
}
