function Show-RemnexaExtrasMenu {
    while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader (T 'ExtrasTitle')
        Write-Host ('  [1] ' + (T 'DATitle'))
        Write-Host ('  [0] ' + (T 'BackHome'))
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim()
        switch ($answer) {
            '0' { return }
            '1' { Show-RemnexaDefaultApplications }
            default { Write-Status (T 'DAInvalid') 'Warning' }
        }
    }
}

function Show-RemnexaDefaultApplicationDetails {
    param([Parameter(Mandatory)][string]$Name)
    while ($true) {
        Clear-RemnexaScreen
        Show-BrandHeader (T 'DATitle')
        $association = Get-RemnexaCurrentAssociation -Name $Name
        $application = if ($association.Known) { $association.Application } else { T 'DAUnknown' }
        Write-Host (T 'DASelected' @($Name)) -ForegroundColor Cyan
        Write-Host (T 'DACurrent' @($application))
        if ($association.ProgId) { Write-Host (T 'DAIdentifier' @($association.ProgId)) -ForegroundColor DarkGray }
        Write-Host ''
        Write-Host (T 'DAWindowsHint' @($Name)) -ForegroundColor DarkGray
        Write-Host (T 'DANoAdmin') -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ('  [1] ' + (T 'DAOpenSettings'))
        Write-Host ('  [R] ' + (T 'DARefresh'))
        Write-Host ('  [0] ' + (T 'DABackList'))
        $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
        switch ($answer) {
            '0' { return }
            'R' { continue }
            '1' {
                try {
                    Open-RemnexaDefaultAppsSettings
                    Write-Status (T 'DASettingsOpened' @($Name)) 'Info'
                } catch { Write-Status (T 'DASettingsFailed') 'Warning' }
                [void](Read-RemnexaInput (T 'DAAfterSettings'))
            }
            default { Write-Status (T 'DAInvalid') 'Warning' }
        }
    }
}

function Show-RemnexaDefaultApplications {
    $mode = 'Simple'; $search = ''; $pageIndex = 0; $reload = $true; $catalog = @()
    while ($true) {
        try {
            if ($reload) { $catalog = @(Get-RemnexaAssociationCatalog -Mode $mode); $reload = $false }
            $page = Select-RemnexaAssociationPage -Catalog $catalog -Search $search -PageIndex $pageIndex
            $pageIndex = $page.PageIndex
            Clear-RemnexaScreen
            Show-BrandHeader (T 'DATitle')
            $modeText = if ($mode -eq 'Simple') { T 'DASimple' } else { T 'DAAdvanced' }
            Write-Host (T 'DAMode' @($modeText)) -ForegroundColor Cyan
            Write-Host (T 'DAReadOnly') -ForegroundColor DarkGray
            if ($mode -eq 'Advanced') { Write-Host (T 'DAAdvancedHint') -ForegroundColor DarkGray }
            if ($search) { Write-Host (T 'DASearchActive' @($search)) }
            Write-Host (T 'DAPage' @(($pageIndex + 1), $page.PageCount, $page.Total)) -ForegroundColor DarkGray
            Write-Host ''
            for ($i = 0; $i -lt $page.Items.Count; $i++) {
                $association = Get-RemnexaCurrentAssociation -Name $page.Items[$i].Name
                $application = if ($association.Known) { $association.Application } else { T 'DAUnknown' }
                Write-Host ('  [{0,2}] {1,-14} {2}' -f ($i + 1), $association.Name, $application)
            }
            if (-not $page.Items.Count) { Write-Host (T 'DANoMatches') -ForegroundColor DarkGray }
            Write-Host ''
            if ($page.HasNext) { Write-Host ('  [N] ' + (T 'DANext')) }
            if ($page.HasPrevious) { Write-Host ('  [P] ' + (T 'DAPrevious')) }
            $otherMode = if ($mode -eq 'Simple') { T 'DAAdvanced' } else { T 'DASimple' }
            Write-Host ('  [M] ' + (T 'DASwitchMode' @($otherMode)))
            Write-Host ('  [S] ' + (T 'DASearch'))
            Write-Host ('  [R] ' + (T 'DARefresh'))
            Write-Host ('  [W] ' + (T 'DAOpenSettings'))
            Write-Host ('  [0] ' + (T 'DAExtrasBack'))
            $answer = (Read-RemnexaInput (T 'SelectPrompt')).Trim().ToUpperInvariant()
            switch ($answer) {
                '0' { return }
                'N' { if ($page.HasNext) { $pageIndex++ }; continue }
                'P' { if ($page.HasPrevious) { $pageIndex-- }; continue }
                'M' { $mode = if ($mode -eq 'Simple') { 'Advanced' } else { 'Simple' }; $search = ''; $pageIndex = 0; $reload = $true; continue }
                'S' {
                    $inputText = Read-RemnexaInput (T 'DASearchPrompt')
                    # Filter is literal and never used as a Registry path, regex or command.
                    $search = [regex]::Replace($inputText.Trim(), '[\p{Cc}\p{Cf}]', '')
                    if ($search.Length -gt 128) { $search = $search.Substring(0,128) }
                    $pageIndex = 0; continue
                }
                'R' { $reload = $true; continue }
                'W' {
                    try { Open-RemnexaDefaultAppsSettings } catch { Write-Status (T 'DASettingsFailed') 'Warning' }
                    [void](Read-RemnexaInput (T 'DAAfterSettings')); continue
                }
                default {
                    $choice = ConvertFrom-RemnexaMenuChoice -InputText $answer -Maximum $page.Items.Count
                    if ($null -ne $choice -and $choice -gt 0) { Show-RemnexaDefaultApplicationDetails -Name $page.Items[$choice - 1].Name }
                    else { Write-Status (T 'DAInvalid') 'Warning' }
                }
            }
        } catch {
            Write-Status (T 'DAReadFailed') 'Warning'
            [void](Read-RemnexaInput (T 'SystemSnapshotContinue'))
            return
        }
    }
}
