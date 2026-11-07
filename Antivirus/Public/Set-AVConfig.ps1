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

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Antivirus-Konfiguration speichern')) {
        $directory = Split-Path -Parent $resolvedPath
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedPath -Encoding UTF8 -ErrorAction Stop
        Write-AVLog -Message "Antivirus-Konfiguration gespeichert: $resolvedPath" -Event 'Configuration'
    }
    if ($PassThru) { return $config }
}
