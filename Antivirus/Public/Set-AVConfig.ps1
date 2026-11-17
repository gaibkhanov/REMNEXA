function Set-AVConfig {
    <#
    .SYNOPSIS
    Aendert und speichert die ClamAV-Konfiguration.

    .DESCRIPTION
    Aktualisiert nur die angegebenen Eigenschaften. Unbekannte Eigenschaften
    werden abgewiesen, um Tippfehler in sicherheitsrelevanten Pfaden zu vermeiden.

    .PARAMETER Values
    Hashtable mit den zu aendernden Konfigurationswerten.

    .PARAMETER Path
    Optionaler Pfad zu einer alternativen JSON-Konfigurationsdatei.

    .PARAMETER PassThru
    Gibt die gespeicherte Konfiguration zurueck.

    .EXAMPLE
    Set-AVConfig -Values @{ IncludePUA = $true; MaxFileSize = '200M' } -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Values,
        [string]$Path = $script:AVConfigPath,
        [switch]$PassThru
    )

    $resolvedPath = Expand-AVPath $Path
    $config = Get-AVConfig -Path $resolvedPath
    $knownNames = @($config.PSObject.Properties.Name)
    foreach ($name in $Values.Keys) {
        if ($knownNames -notcontains [string]$name) {
            throw "Unbekannte Antivirus-Einstellung '$name'."
        }
        if ($name -eq 'MaxFileSize') { Test-AVMaxFileSize ([string]$Values[$name]) }
        $config.$name = $Values[$name]
    }
    [void](Get-AVUpdateOptions $config)

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Antivirus-Konfiguration speichern')) {
        $directory = Split-Path -Parent $resolvedPath
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        $operationId = [guid]::NewGuid().ToString('N')
        $fileName = [IO.Path]::GetFileName($resolvedPath)
        $temporaryPath = Join-Path $directory ('.' + $fileName + '.remnexa.' + $operationId + '.tmp')
        $backupPath = Join-Path $directory ('.' + $fileName + '.remnexa.backup.' + $operationId + '.tmp')
        $json = $config | ConvertTo-Json -Depth 8
        try {
            [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                [IO.File]::Replace($temporaryPath, $resolvedPath, $backupPath)
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                [IO.File]::Move($temporaryPath, $resolvedPath)
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
        Write-AVLog -Message "Antivirus-Konfiguration gespeichert: $resolvedPath" -Event 'Configuration'
    }
    if ($PassThru) { return $config }
}
