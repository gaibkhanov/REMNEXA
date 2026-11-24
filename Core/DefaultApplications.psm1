Set-StrictMode -Version 2.0

function Test-RemnexaAssociationName {
    param([AllowEmptyString()][string]$Name)
    # Literal association names only. No paths, URIs, wildcards or control characters.
    return $Name -cmatch '\A(?:\.[\p{L}\p{N}_+][\p{L}\p{N}_+.-]{0,126}|https?|mailto)\z'
}

function ConvertTo-RemnexaAssociationDisplayText {
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$Maximum = 100)
    $clean = [regex]::Replace([string]$Text, '[\p{Cc}\p{Cf}]', ' ')
    if ($clean.Length -gt $Maximum) { return $clean.Substring(0, $Maximum - 1) + '…' }
    return $clean
}

function Get-RemnexaRegisteredExtensions {
    [CmdletBinding()]
    param()
    # HKCR is Windows' merged per-user/machine view. Only read names; never recurse.
    $classes = [Microsoft.Win32.Registry]::ClassesRoot
    $classes.GetSubKeyNames() | Where-Object { $_.StartsWith('.') }
    $user = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts', $false)
    if ($null -ne $user) {
        try { $user.GetSubKeyNames() } finally { $user.Dispose() }
    }
}

function Get-RemnexaAssociationCatalog {
    [CmdletBinding()]
    param([ValidateSet('Simple','Advanced')][string]$Mode = 'Simple')
    $common = @('.pdf','.docx','.doc','.odt','.xlsx','.pptx','.txt','.csv',
        '.jpg','.jpeg','.png','.gif','.webp','.heic','.svg',
        '.mp3','.wav','.flac','.m4a','.mp4','.mkv','.avi','.mov',
        '.htm','.html','.zip','.7z','http','https','mailto')
    $names = if ($Mode -eq 'Simple') { $common } else { @(@(Get-RemnexaRegisteredExtensions) + @('http','https','mailto') | Where-Object { Test-RemnexaAssociationName $_ } | Sort-Object -Unique) }
    foreach ($name in $names) {
        [pscustomobject]@{ Name = $name.ToLowerInvariant(); Kind = $(if ($name.StartsWith('.')) { 'File' } else { 'Protocol' }) }
    }
}

function Get-RemnexaCurrentAssociation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-RemnexaAssociationName $Name)) { throw 'Invalid association name.' }
    if (-not ('Remnexa.DefaultApplications.AssociationReader' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'DefaultApplications.cs') -ErrorAction Stop
    }
    $protocol = -not $Name.StartsWith('.')
    $reader = [Remnexa.DefaultApplications.AssociationReader]
    # ASSOCSTR_FRIENDLYAPPNAME = 4, ASSOCSTR_PROGID = 20.
    $application = $reader::Query($Name, $protocol, 4)
    $progId = $reader::Query($Name, $protocol, 20)
    # Windows' generic application chooser is not an assigned reader/player.
    $executable = $reader::Query($Name, $protocol, 2)
    if ([IO.Path]::GetFileName($executable) -ieq 'OpenWith.exe') { $application = '' }
    [pscustomobject]@{
        Name = $Name
        Application = ConvertTo-RemnexaAssociationDisplayText $application
        ProgId = ConvertTo-RemnexaAssociationDisplayText $progId
        Known = -not [string]::IsNullOrWhiteSpace($application)
    }
}

function Select-RemnexaAssociationPage {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Catalog = @(), [string]$Search = '', [int]$PageIndex = 0,
        [ValidateRange(1,100)][int]$PageSize = 15)
    $filtered = @($Catalog | Where-Object { $_.Name.IndexOf($Search, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $count = [int][Math]::Max(1, [Math]::Ceiling($filtered.Count / [double]$PageSize))
    $index = [int][Math]::Clamp($PageIndex, 0, $count - 1)
    [pscustomobject]@{
        Items = @($filtered | Select-Object -Skip ($index * $PageSize) -First $PageSize)
        Total = $filtered.Count; PageIndex = $index; PageCount = $count
        HasNext = $index + 1 -lt $count; HasPrevious = $index -gt 0
    }
}

function Open-RemnexaDefaultAppsSettings {
    [CmdletBinding()]
    param()
    # Only Microsoft's documented, fixed Settings URI. No registry content is launched.
    Start-Process -FilePath 'ms-settings:defaultapps' -ErrorAction Stop
}

Export-ModuleMember -Function @('Get-RemnexaAssociationCatalog', 'Get-RemnexaCurrentAssociation', 'Select-RemnexaAssociationPage', 'Open-RemnexaDefaultAppsSettings')
