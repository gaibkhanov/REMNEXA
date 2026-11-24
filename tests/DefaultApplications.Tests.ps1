BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'Core/DefaultApplications.psm1') -Force
}

Describe 'Read-only Windows default application catalog' {
    It 'includes common documents, media, web and mail in simple mode without enumerating the Registry' {
        InModuleScope DefaultApplications {
            Mock Get-RemnexaRegisteredExtensions { throw 'Simple mode must not enumerate all extensions.' }
            $catalog = @(Get-RemnexaAssociationCatalog)
            $catalog[0].Name | Should -Be '.pdf'
            foreach ($name in @('.pdf','.docx','.jpg','.mp3','.html','http','https','mailto')) {
                $catalog.Name | Should -Contain $name
            }
            @($catalog | Where-Object Name -eq 'https')[0].Kind | Should -Be 'Protocol'
            Should -Invoke Get-RemnexaRegisteredExtensions -Times 0
        }
    }
    It 'merges registered extensions, deduplicates names and excludes unsafe registry names' {
        InModuleScope DefaultApplications {
            Mock Get-RemnexaRegisteredExtensions { @('.pdf','.PDF','.unknown-format','.日本語','..','.bad/path','.pdf?x=1',".a`n",'http','not-an-extension') }
            $catalog = @(Get-RemnexaAssociationCatalog -Mode Advanced)
            @($catalog | Where-Object Name -eq '.pdf').Count | Should -Be 1
            $catalog.Name | Should -Contain '.unknown-format'
            $catalog.Name | Should -Contain '.日本語'
            $catalog.Count | Should -Be 6
        }
    }
    It 'rejects paths and URI/command injection before querying Windows' {
        foreach ($name in @('../pdf','..','file:///example','.pdf?x=1','https:evil','.txt;calc.exe',".pdf`n",'')) {
            { Get-RemnexaCurrentAssociation -Name $name } | Should -Throw
        }
    }
    It 'sanitizes untrusted display labels without executing application commands' {
        InModuleScope DefaultApplications {
            $text = ConvertTo-RemnexaAssociationDisplayText ("Reader`e[2J`n" + [char]0x202e + ('x' * 200)) -Maximum 50
            $text.Length | Should -Be 50
            $text | Should -Not -Match '[\p{Cc}\p{Cf}]'
        }
    }
    It 'opens only the fixed documented Settings URI without elevation or registry writes' {
        InModuleScope DefaultApplications {
            Mock Start-Process {}
            Open-RemnexaDefaultAppsSettings
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -ceq 'ms-settings:defaultapps' -and -not $Verb -and -not $ArgumentList }
        }
    }
    It 'preserves the user association when reading the real Windows Shell API' -Tag Windows11Client {
        $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice'
        $before = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue | Select-Object ProgId, Hash | ConvertTo-Json -Compress
        foreach ($name in @('.pdf','.txt','https','.remnexa-nonexistent-test-format')) {
            $result = Get-RemnexaCurrentAssociation -Name $name
            $result.Name | Should -Be $name
            $result.Known | Should -BeOfType [bool]
            if ($result.Known) { $result.Application | Should -Not -BeNullOrEmpty }
        }
        $after = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue | Select-Object ProgId, Hash | ConvertTo-Json -Compress
        $after | Should -BeExactly $before
    }
}

Describe 'Default application filtering and page boundaries' {
    It 'shows neither page option for zero or one page and clamps invalid page indices' {
        foreach ($count in @(0,1,15)) {
            $catalog = @(for ($i=0; $i -lt $count; $i++) { [pscustomobject]@{Name=".f$i"} })
            $page = Select-RemnexaAssociationPage $catalog -PageIndex 99
            $page.PageCount | Should -Be 1
            $page.PageIndex | Should -Be 0
            $page.HasNext | Should -BeFalse
            $page.HasPrevious | Should -BeFalse
            $page.Items.Count | Should -Be $count
        }
    }
    It 'includes every entry exactly once across page boundaries and searches literally' {
        $catalog = @(for ($i=0; $i -lt 31; $i++) { [pscustomobject]@{Name=".f$i"} })
        $first = Select-RemnexaAssociationPage $catalog -PageIndex 0
        $middle = Select-RemnexaAssociationPage $catalog -PageIndex 1
        $last = Select-RemnexaAssociationPage $catalog -PageIndex 2
        $first.HasNext | Should -BeTrue; $first.HasPrevious | Should -BeFalse
        $middle.HasNext | Should -BeTrue; $middle.HasPrevious | Should -BeTrue
        $last.HasNext | Should -BeFalse; $last.HasPrevious | Should -BeTrue
        @($first.Items + $middle.Items + $last.Items | Select-Object -ExpandProperty Name -Unique).Count | Should -Be 31
        (Select-RemnexaAssociationPage $catalog -Search '*').Total | Should -Be 0
        (Select-RemnexaAssociationPage @([pscustomobject]@{Name='.PDF'}) -Search 'pdf').Total | Should -Be 1
    }
}

Describe 'Extras console navigation' {
    BeforeAll {
        Import-Module (Join-Path $root 'Core/MenuChoices.psd1') -Force
        Import-Module (Join-Path $root 'Core/Localization.psd1') -Force
        $script:extrasTexts = Import-RemnexaLocalization (Join-Path $root 'locales') @('de','en','es','fr','ru','tr') de
        . (Join-Path $root 'Core/ExtrasConsole.ps1')
        function T { param($Key,$Values=@()); $text=$script:extrasTexts[$Key][0]; if($Values.Count){return ($text -f $Values)}; $text }
        function Clear-RemnexaScreen {}
        function Show-BrandHeader { param($Section) }
        function Read-RemnexaInput { param($Prompt) }
        function Write-Status { param($Message,$Type) }
    }
    BeforeEach {
        $script:messages = [Collections.Generic.List[string]]::new()
        $script:answers = [Collections.Generic.Queue[string]]::new()
        Mock Write-Host { param($Object); [void]$script:messages.Add([string]$Object) }
        Mock Read-RemnexaInput { if(-not $script:answers.Count){throw 'Unexpected prompt.'}; $script:answers.Dequeue() }
        Mock Get-RemnexaCurrentAssociation { param($Name); [pscustomobject]@{Name=$Name;Known=$true;Application='Test Reader';ProgId='Test.Reader'} }
        Mock Open-RemnexaDefaultAppsSettings {}
        Mock Write-Status { param($Message,$Type); [void]$script:messages.Add([string]$Message) }
    }
    It 'switches mode, filters, opens settings only on request and rereads the selection' {
        Mock Get-RemnexaAssociationCatalog { @([pscustomobject]@{Name='.pdf';Kind='File'},[pscustomobject]@{Name='.jpg';Kind='File'}) }
        foreach($answer in @('M','S','pdf','1','1','','0','0')){$script:answers.Enqueue($answer)}
        Show-RemnexaDefaultApplications
        $script:answers.Count | Should -Be 0
        Should -Invoke Get-RemnexaAssociationCatalog -ParameterFilter {$Mode -eq 'Advanced'} -Times 1
        Should -Invoke Open-RemnexaDefaultAppsSettings -Times 1
        Should -Invoke Get-RemnexaCurrentAssociation -ParameterFilter {$Name -eq '.pdf'} -Times 2
        ($script:messages -join "`n") | Should -Match 'Suche dort nach .pdf'
        @($script:messages | Where-Object {$_ -match '^  \[[NP]\]'}).Count | Should -Be 0
    }
    It 'never opens Windows Settings just by browsing or on an invalid selection' {
        Mock Get-RemnexaAssociationCatalog { @([pscustomobject]@{Name='.pdf';Kind='File'}) }
        foreach($answer in @('9','N','P','S','missing','0')){$script:answers.Enqueue($answer)}
        Show-RemnexaDefaultApplications
        Should -Invoke Open-RemnexaDefaultAppsSettings -Times 0
        ($script:messages -join "`n") | Should -Match 'Keine passenden Einträge'
        @($script:messages | Where-Object {$_ -match '^  \[[NP]\]'}).Count | Should -Be 0
    }
    It 'advertises only existing next and previous pages' {
        Mock Get-RemnexaAssociationCatalog { for($i=0;$i -lt 16;$i++){[pscustomobject]@{Name=".f$i";Kind='File'}} }
        foreach($answer in @('N','P','0')){$script:answers.Enqueue($answer)}
        Show-RemnexaDefaultApplications
        @($script:messages | Where-Object {$_ -match '^  \[N\]'}).Count | Should -Be 2
        @($script:messages | Where-Object {$_ -match '^  \[P\]'}).Count | Should -Be 1
    }
    It 'keeps Extras reachable from the home menu without renumbering existing entries' {
        $source = [IO.File]::ReadAllText((Join-Path $root 'REMNEXA.ps1'))
        $source | Should -Match "'E' \{Show-RemnexaExtrasMenu;continue mainLoop\}"
        $source | Should -Match "\[E\].*ExtrasTitle"
    }
    It 'has all new labels with matching placeholders in all six languages' {
        $reference = Get-Content (Join-Path $root 'locales/en.json') -Raw | ConvertFrom-Json -AsHashtable
        $keys = @($reference.Keys | Where-Object {$_ -like 'DA*' -or $_ -eq 'ExtrasTitle'})
        foreach($language in @('de','en','es','fr','ru','tr')) {
            $texts = Get-Content (Join-Path $root "locales/$language.json") -Raw | ConvertFrom-Json -AsHashtable
            foreach($key in $keys) {
                $texts[$key] | Should -Not -BeNullOrEmpty
                $actual = @([regex]::Matches($texts[$key],'\{\d+\}') | ForEach-Object Value) -join ','
                $expected = @([regex]::Matches($reference[$key],'\{\d+\}') | ForEach-Object Value) -join ','
                $actual | Should -Be $expected
            }
        }
    }
}
