function Update-ClamAVEngine {
    <#
    .SYNOPSIS
    Aktualisiert die portable ClamAV-Scan-Engine.

    .DESCRIPTION
    Ermittelt das aktuelle offizielle Cisco-Talos-Windows-Paket, prueft den von
    GitHub gelieferten SHA-256-Wert, uebernimmt die vorhandene Signaturdatenbank
    und ersetzt die portable Engine transaktional. Bei einem Fehler wird die
    vorherige Installation wiederhergestellt.

    .PARAMETER ConfigPath
    Optionaler Pfad zu einer alternativen Antivirus-Konfiguration.

    .PARAMETER DownloadUri
    Optionale direkte offizielle ZIP-Adresse. Ohne Angabe wird das neueste
    offizielle Cisco-Talos-Release automatisch ermittelt.

    .PARAMETER Force
    Installiert das aktuelle Paket erneut, auch wenn die Versionsnummer bereits
    mit dem neuesten Release uebereinstimmt.

    .PARAMETER UpdateSignatures
    Aktualisiert nach dem Engine-Update zusaetzlich die Signaturdatenbank.

    .EXAMPLE
    Update-ClamAVEngine

    .EXAMPLE
    Update-ClamAVEngine -UpdateSignatures
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string]$ConfigPath = $script:AVConfigPath,
        [string]$DownloadUri,
        [switch]$Force,
        [switch]$UpdateSignatures
    )

    $config = Get-AVConfig -Path $ConfigPath
    $statusBefore = Get-ClamAVStatus -ConfigPath $ConfigPath
    if (-not $statusBefore.Installed) {
        throw "ClamAV ist noch nicht installiert. Bitte zuerst Initialize-ClamAV ausfuehren."
    }

    $asset = Resolve-ClamAVReleaseAsset -DownloadUri $(if ($DownloadUri) { $DownloadUri } else { [string]$config.DownloadUri })
    if (-not $Force -and $asset.Version -and $statusBefore.Version -eq $asset.Version) {
        Write-AVLog -Message "ClamAV-Engine ist bereits aktuell: $($statusBefore.Version)." -Level 'Success' -Event 'EngineUpdate'
        return [PSCustomObject]@{
            Updated         = $false
            UpdateStatus    = 'Current'
            PreviousVersion = $statusBefore.Version
            CurrentVersion  = $statusBefore.Version
            LatestVersion   = $asset.Version
            ClamScanPath    = $statusBefore.ClamScanPath
            DatabasePath    = $statusBefore.DatabasePath
        }
    }

    $target = [IO.Path]::GetFullPath((Split-Path -Parent $statusBefore.ClamScanPath)).TrimEnd('\')
    $driveRoot = [IO.Path]::GetPathRoot($target).TrimEnd('\')
    if ($target.Equals($driveRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsicherer ClamAV-Zielpfad '$target'. Das Laufwerksstammverzeichnis darf nicht aktualisiert werden."
    }
    if (-not $PSCmdlet.ShouldProcess($target, "ClamAV-Engine auf Version $($asset.Version) aktualisieren")) {
        return
    }

    $parent = Split-Path -Parent $target
    $leaf = Split-Path -Leaf $target
    $operationId = [guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $parent ('.' + $leaf + '.update.' + $operationId)
    $backupRoot = Join-Path $parent ('.' + $leaf + '.backup.' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-ClamAV-Update-' + $operationId)
    $archivePath = Join-Path $temporaryRoot 'clamav.zip'
    $extractPath = Join-Path $temporaryRoot 'extract'
    $targetMoved = $false
    try {
        New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop | Out-Null
        Write-AVLog -Message "ClamAV-Engine-Update gestartet: $($statusBefore.Version) -> $($asset.Version)." -Event 'EngineUpdate'
        Write-Progress -Activity 'ClamAV-Engine-Update' -Status 'Offizielles Paket wird heruntergeladen' -PercentComplete 10
        Invoke-WebRequest -Uri $asset.Uri -OutFile $archivePath -UseBasicParsing -ErrorAction Stop
        if ($asset.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actualHash -ne $Matches[1]) {
                throw 'Die SHA-256-Pruefung des ClamAV-Updates ist fehlgeschlagen. Die vorhandene Installation bleibt unveraendert.'
            }
        }

        Write-Progress -Activity 'ClamAV-Engine-Update' -Status 'Paket wird vorbereitet' -PercentComplete 35
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force -ErrorAction Stop
        $newClamScan = Get-ChildItem -LiteralPath $extractPath -Filter 'clamscan.exe' -File -Recurse -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $newClamScan) { throw 'Das Update-Paket enthaelt keine clamscan.exe.' }
        $newSourceRoot = Split-Path -Parent $newClamScan.FullName
        New-Item -ItemType Directory -Path $stagingRoot -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $newSourceRoot '*') -Destination $stagingRoot -Recurse -Force -ErrorAction Stop

        $databasePath = Expand-AVPath ([string]$config.DatabasePath)
        if (Test-Path -LiteralPath $databasePath -PathType Container) {
            if ($databasePath.Equals($target, [StringComparison]::OrdinalIgnoreCase) -or (Test-AVPathIsWithin -Path $databasePath -Parent $target)) {
                $databaseRelative = $databasePath.Substring($target.Length).TrimStart('\')
                $stagingDatabase = Join-Path $stagingRoot $databaseRelative
                New-Item -ItemType Directory -Path $stagingDatabase -Force -ErrorAction Stop | Out-Null
                Copy-Item -Path (Join-Path $databasePath '*') -Destination $stagingDatabase -Recurse -Force -ErrorAction Stop
            }
        }
        [void](New-FreshClamConfiguration -ClamAVPath $stagingRoot -DatabasePath $databasePath)

        Write-Progress -Activity 'ClamAV-Engine-Update' -Status 'Engine wird sicher ersetzt' -PercentComplete 70
        Move-Item -LiteralPath $target -Destination $backupRoot -ErrorAction Stop
        $targetMoved = $true
        Move-Item -LiteralPath $stagingRoot -Destination $target -ErrorAction Stop

        $statusAfter = Get-ClamAVStatus -ConfigPath $ConfigPath
        if (-not $statusAfter.Installed -or [string]::IsNullOrWhiteSpace([string]$statusAfter.Version)) {
            throw 'Die aktualisierte ClamAV-Engine konnte nach dem Austausch nicht gestartet werden.'
        }
        if ($asset.Version -and $statusAfter.Version -ne $asset.Version) {
            throw "Versionspruefung fehlgeschlagen: erwartet $($asset.Version), erkannt $($statusAfter.Version)."
        }

        if ($UpdateSignatures) { $statusAfter = Update-ClamAVSignature -ConfigPath $ConfigPath }
        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction Stop
        }
        $targetMoved = $false
        Write-Progress -Activity 'ClamAV-Engine-Update' -Status 'Aktualisierung abgeschlossen' -PercentComplete 100
        Write-AVLog -Message "ClamAV-Engine aktualisiert: $($statusBefore.Version) -> $($statusAfter.Version)." -Level 'Success' -Event 'EngineUpdate'
        return [PSCustomObject]@{
            Updated         = $true
            UpdateStatus    = 'Updated'
            PreviousVersion = $statusBefore.Version
            CurrentVersion  = $statusAfter.Version
            LatestVersion   = $asset.Version
            ClamScanPath    = $statusAfter.ClamScanPath
            DatabasePath    = $statusAfter.DatabasePath
        }
    }
    catch {
        if ($targetMoved -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
            try {
                if (Test-Path -LiteralPath $target -PathType Container) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop }
                Move-Item -LiteralPath $backupRoot -Destination $target -ErrorAction Stop
                $targetMoved = $false
            }
            catch {
                Write-Warning "Automatische Wiederherstellung fehlgeschlagen. Sicherung: '$backupRoot'."
            }
        }
        Write-AVLog -Message $_.Exception.Message -Level 'Error' -Event 'EngineUpdate'
        throw
    }
    finally {
        Write-Progress -Activity 'ClamAV-Engine-Update' -Completed
        if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
