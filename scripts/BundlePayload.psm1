Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../Core/PathSafety.psd1') -Force

function Assert-RemnexaBundleArchive {
    param([string]$Path,[string]$SHA256)
    if($SHA256 -notmatch '^[a-f0-9]{64}$' -or -not(Test-Path -LiteralPath $Path -PathType Leaf) -or -not(Get-RemnexaPathSafety $Path).IsSafe){throw 'Missing or unsafe pinned bundle archive.'}
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $SHA256){throw 'Bundle archive checksum mismatch.'}
}

function Assert-RemnexaBundleRuntime {
    param([string]$Directory,[string]$Archive,$Pin)
    Assert-RemnexaBundleArchive $Archive $Pin.sha256
    if(-not(Get-RemnexaPathSafety $Directory).IsSafe){throw 'Unsafe runtime payload.'}
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    $expectedFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try{
        foreach($entry in $zip.Entries){
            if(-not $entry.Name -or $entry.FullName -match '^preview[\\/]'){continue}
            [void]$expectedFiles.Add($entry.FullName.Replace('\','/'))
            $path=Join-Path $Directory $entry.FullName
            if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or -not(Get-RemnexaPathSafety $path).IsSafe){throw 'Runtime differs from the pinned official archive.'}
            $stream=$entry.Open();try{$expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()}finally{$stream.Dispose()}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'Runtime content differs from the pinned official archive.'}
        }
    }finally{$zip.Dispose()}
    foreach($file in Get-ChildItem -LiteralPath $Directory -File -Recurse -Force){
        $relative=[IO.Path]::GetRelativePath($Directory,$file.FullName).Replace('\','/')
        if($relative -eq '.upstream-sha256' -or $relative -match '^preview/'){continue}
        if(-not $expectedFiles.Contains($relative)){throw 'Unexpected file in the bundled runtime.'}
    }
}

function Add-RemnexaClamBundle {
    param([string]$Archive,[string]$SourceArchive,[string]$DatabasePath,[string]$VerificationPath,[string]$PackageDirectory,$Pins)
    Assert-RemnexaBundleArchive $Archive $Pins.clamAV.sha256
    Assert-RemnexaBundleArchive $SourceArchive $Pins.clamAVSource.sha256
    if($Pins.clamAV.version -ne $Pins.clamAVSource.version){throw 'ClamAV binary/source versions do not match.'}
    if(-not(Get-RemnexaPathSafety $PackageDirectory).IsSafe -or -not(Get-RemnexaPathSafety $DatabasePath).IsSafe -or -not(Get-RemnexaPathSafety $VerificationPath).IsSafe){throw 'Unsafe complete package input.'}
    $verification=Get-Content -LiteralPath $VerificationPath -Raw|ConvertFrom-Json -DateKind String
    if($verification.FreshClamExitCode -ne 0){throw 'Signature preparation did not succeed.'}
    $prepared=[DateTimeOffset]::Parse($verification.PreparedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
    if(([DateTimeOffset]::UtcNow-$prepared).TotalHours -gt 24 -or $prepared -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){throw 'Refresh the signature snapshot before building Complete (maximum 24 hours).'}
    $target=Join-Path $PackageDirectory 'app/ClamAV';[void][IO.Directory]::CreateDirectory($target)
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try{
        $engines=@($zip.Entries|Where-Object{$_.FullName.Replace('\','/') -match '(^|/)clamscan\.exe$'})
        if($engines.Count -ne 1){throw 'Ambiguous ClamAV archive root.'}
        $prefix=$engines[0].FullName.Substring(0,$engines[0].FullName.Length-'clamscan.exe'.Length)
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in $zip.Entries){
            $path=$entry.FullName.Replace('\','/')
            if($path -match '(^/|:|(^|/)\.\.(/|$))' -or -not $seen.Add($path) -or (($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000){throw 'Unsafe ClamAV archive entry.'}
            if(-not $entry.Name -or -not $entry.FullName.StartsWith($prefix,[StringComparison]::Ordinal)){continue}
            $relative=$entry.FullName.Substring($prefix.Length).Replace('\','/')
            # Debug symbols, linker libraries and headers are build artifacts.
            if($relative -match '(?i)(\.pdb$|\.lib$|^include/)'){continue}
            $file=Join-Path $target $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$file,$false)
        }
    }finally{$zip.Dispose()}
    foreach($required in @('clamscan.exe','freshclam.exe','sigtool.exe','libclamav.dll','libfreshclam.dll','vcruntime140.dll','msvcp140.dll','COPYING.txt','COPYING')){
        if(-not(Test-Path -LiteralPath (Join-Path $target $required))){throw ('Missing required portable ClamAV component: '+$required)}
    }
    $dbTarget=Join-Path $target 'database';[void][IO.Directory]::CreateDirectory($dbTarget)
    $databases=@()
    foreach($name in @('main','daily','bytecode')){
        $records=@($verification.Databases|Where-Object{$_.Name -match ('^'+$name+'\.(cvd|cld)$')})
        if($records.Count -ne 1 -or $records[0].SHA256 -notmatch '^[a-f0-9]{64}$'){throw 'Incomplete verified signature snapshot.'}
        $record=$records[0];$file=Join-Path $DatabasePath $record.Name
        if(-not(Get-RemnexaPathSafety $file).IsSafe -or (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.SHA256){throw 'Signature snapshot changed after verification.'}
        $copied=Join-Path $dbTarget $record.Name
        [IO.File]::Copy($file,$copied)
        if((Get-FileHash $copied -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.SHA256){throw 'Signature snapshot changed during copying.'}
        $databases+=[ordered]@{Name=$record.Name;SHA256=$record.SHA256;Bytes=(Get-Item -LiteralPath $file).Length}
    }
    foreach($file in Get-ChildItem -LiteralPath $DatabasePath -File){
        if($file.Name -match '^(main|daily|bytecode)-[0-9]+\.cvd\.sign$'){
            if(-not(Get-RemnexaPathSafety $file.FullName).IsSafe){throw 'Unsafe signature proof.'}
            [IO.File]::Copy($file.FullName,(Join-Path $dbTarget $file.Name))
        }
    }
    # Relative configuration survives extraction or movement of the user folder.
    $freshclam="DatabaseDirectory database`nDatabaseMirror database.clamav.net`nDNSDatabaseInfo current.cvd.clamav.net`nConnectTimeout 10`nReceiveTimeout 30`nMaxAttempts 2`n"
    [IO.File]::WriteAllText((Join-Path $target 'freshclam.conf'),$freshclam,[Text.UTF8Encoding]::new($false))
    $legal=Join-Path $PackageDirectory 'app/licenses/clamav';[void][IO.Directory]::CreateDirectory($legal)
    $sourceName='clamav-'+$Pins.clamAVSource.version+'.tar.gz'
    [IO.File]::Copy($SourceArchive,(Join-Path $legal $sourceName))
    $notice=@"
ClamAV $($Pins.clamAV.version) - unmodified official Windows runtime payload.
GPLv2: app/ClamAV/COPYING.txt; component licenses: app/ClamAV/COPYING/.
The matching upstream ClamAV source distribution accompanies this package:
app/licenses/clamav/$sourceName
SHA-256: $($Pins.clamAVSource.sha256)
Source: $($Pins.clamAVSource.uri)
ClamAV's supplied third-party notices and runtime files retain their licenses.
UnRAR has separate restrictions; see app/ClamAV/COPYING/COPYING.unrar.
Microsoft runtime libraries retain Microsoft's terms; they are not MIT/GPL.
The REMNEXA frontend license does not relicense these components.
Signature snapshot prepared by FreshClam: $($verification.PreparedAtUtc).
No scan logs, freshclam.dat, personal paths or local configuration are bundled.
"@
    [IO.File]::WriteAllText((Join-Path $legal 'README.txt'),$notice,[Text.UTF8Encoding]::new($false))
    [ordered]@{Version=$Pins.clamAV.version;ArchiveSHA256=$Pins.clamAV.sha256;SourceArchiveSHA256=$Pins.clamAVSource.sha256;SourcePath=('app/licenses/clamav/'+$sourceName);SignaturesPreparedAtUtc=$verification.PreparedAtUtc;Databases=$databases}
}

Export-ModuleMember -Function Assert-RemnexaBundleArchive,Assert-RemnexaBundleRuntime,Add-RemnexaClamBundle
