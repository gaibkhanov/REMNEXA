function Move-ToClamAVQuarantine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Signature,
        [Parameter(Mandatory = $true)][string]$QuarantinePath
    )

    $source = [IO.Path]::GetFullPath($Path)
    $destinationRoot = [IO.Path]::GetFullPath($QuarantinePath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Funddatei nicht gefunden: '$source'." }
    if ($source.Equals($destinationRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-AVPathIsWithin -Path $source -Parent $destinationRoot)) {
        throw "Die Datei '$source' befindet sich bereits in der Quarantaene."
    }

    New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop | Out-Null
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $extension = [IO.Path]::GetExtension($source)
    $quarantineId = $timestamp + '-' + $hash.Substring(0, 16)
    $quarantinedName = $quarantineId + $extension + '.quarantine'
    $quarantinedPath = Join-Path $destinationRoot $quarantinedName
    $manifestPath = Join-Path $destinationRoot ($quarantineId + '.json')
    if ((Test-Path -LiteralPath $quarantinedPath) -or (Test-Path -LiteralPath $manifestPath)) {
        $quarantineId += '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $quarantinedPath = Join-Path $destinationRoot ($quarantineId + $extension + '.quarantine')
        $manifestPath = Join-Path $destinationRoot ($quarantineId + '.json')
    }

    $file = Get-Item -LiteralPath $source -ErrorAction Stop
    $manifest = [PSCustomObject]@{
        SchemaVersion   = 1
        QuarantineId    = $quarantineId
        Status          = 'Quarantined'
        OriginalPath    = $source
        QuarantinedPath = $quarantinedPath
        ManifestPath    = $manifestPath
        Signature       = $Signature
        Sha256          = $hash
        SizeBytes       = [int64]$file.Length
        QuarantinedAt   = [DateTimeOffset]::Now.ToString('o')
        RestoredAt      = $null
    }

    try {
        Move-Item -LiteralPath $source -Destination $quarantinedPath -ErrorAction Stop
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
        Write-AVLog -Message "Fund in Quarantaene verschoben: '$source' ($Signature)." -Level 'Warning' -Event 'Quarantine' -Data $manifest
        return $manifest
    }
    catch {
        if ((Test-Path -LiteralPath $quarantinedPath -PathType Leaf) -and -not (Test-Path -LiteralPath $source)) {
            try { Move-Item -LiteralPath $quarantinedPath -Destination $source -ErrorAction Stop } catch { }
        }
        Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'Quarantine'
        throw
    }
}

function Resolve-AVQuarantineManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Identifier,
        [Parameter(Mandatory = $true)][string]$QuarantinePath
    )

    if (Test-Path -LiteralPath $Identifier -PathType Leaf) {
        $candidate = [IO.Path]::GetFullPath($Identifier)
        if ([IO.Path]::GetExtension($candidate) -eq '.json') {
            if (-not (Test-AVPathIsWithin -Path $candidate -Parent $QuarantinePath)) {
                throw "Das Manifest liegt ausserhalb des konfigurierten Quarantaene-Ordners: '$candidate'."
            }
            return $candidate
        }
        $byFile = Get-ChildItem -LiteralPath $QuarantinePath -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object {
            try { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).QuarantinedPath -eq $candidate } catch { $false }
        } | Select-Object -First 1
        if ($byFile) { return $byFile.FullName }
    }
    $byId = Join-Path $QuarantinePath ($Identifier + '.json')
    if (Test-Path -LiteralPath $byId -PathType Leaf) { return $byId }
    throw "Kein Quarantaene-Manifest fuer '$Identifier' gefunden."
}
