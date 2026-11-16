Describe 'REMNEXA local AI data contracts' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\AiContracts.psd1') -Force -ErrorAction Stop
    }

    AfterEach { Remove-Module AiContracts -ErrorAction SilentlyContinue }

    It 'includes only explicitly provided allowlisted facts with bounded values' {
        $request = New-RemnexaAiRequest -Question 'Why is memory use high?' -SystemFacts ([ordered]@{
            WindowsVersion = 'Windows 11'
            CpuPercent = 22
            MemoryPercent = 91
            StartupNames = @('Updater', 'Audio service')
            DiagnosticNotes = @('Memory use is elevated.')
        })
        if ($request.SchemaVersion -ne 1 -or $request.SystemFacts.Count -ne 5 -or $request.SystemFacts.MemoryPercent -ne 91) {
            throw 'The AI request did not preserve its validated, explicitly supplied facts.'
        }

        $rejected = $false
        try { New-RemnexaAiRequest -Question 'Explain this issue.' -SystemFacts ([ordered]@{ Password = 'should not pass' }) }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'An unallowlisted system fact was accepted.' }
    }

    It 'rejects unsafe or oversized input values' {
        $rejectedPath = $false
        try { New-RemnexaAiRequest -Question 'Review startup.' -SystemFacts ([ordered]@{ StartupNames = @('C:\Users\person\app.exe') }) }
        catch { $rejectedPath = $true }
        if (-not $rejectedPath) { throw 'A startup path was accepted where display names are required.' }

        $rejectedPercent = $false
        try { New-RemnexaAiRequest -Question 'Review memory.' -SystemFacts ([ordered]@{ MemoryPercent = 101 }) }
        catch { $rejectedPercent = $true }
        if (-not $rejectedPercent) { throw 'An out-of-range memory percentage was accepted.' }

        $rejectedLength = $false
        try { New-RemnexaAiRequest -Question ('x' * 2001) }
        catch { $rejectedLength = $true }
        if (-not $rejectedLength) { throw 'An oversized question was accepted.' }
    }

    It 'parses bounded advice as inert data and accepts no command field' {
        $json = '{"Summary":"Review memory pressure.","Observations":["The supplied snapshot reports high memory use."],"Recommendations":[{"Title":"Review startup apps","Explanation":"Check whether unused apps need to start with Windows.","RiskLevel":"Low"}]}'
        $response = ConvertFrom-RemnexaAiResponse -InputJson $json
        if (-not $response.IsAdvisoryOnly -or $response.Recommendations.Count -ne 1) {
            throw 'A valid advisory response was not parsed.'
        }

        $withCommand = '{"Summary":"Advice","Observations":[],"Recommendations":[{"Title":"Run this","Explanation":"Try it","RiskLevel":"High","Command":"Remove-Item C:\\"}]}'
        $rejected = $false
        try { ConvertFrom-RemnexaAiResponse -InputJson $withCommand }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'A generated command field was accepted.' }
    }

    It 'rejects malformed JSON, unsupported risk levels, and excessive response size' {
        $rejectedJson = $false
        try { ConvertFrom-RemnexaAiResponse -InputJson '{ malformed' }
        catch { $rejectedJson = $true }
        if (-not $rejectedJson) { throw 'Malformed JSON was accepted.' }

        $badRisk = '{"Summary":"Advice","Observations":[],"Recommendations":[{"Title":"A","Explanation":"B","RiskLevel":"Critical"}]}'
        $rejectedRisk = $false
        try { ConvertFrom-RemnexaAiResponse -InputJson $badRisk }
        catch { $rejectedRisk = $true }
        if (-not $rejectedRisk) { throw 'An unsupported risk level was accepted.' }

        $rejectedSize = $false
        try { ConvertFrom-RemnexaAiResponse -InputJson ('x' * 16385) }
        catch { $rejectedSize = $true }
        if (-not $rejectedSize) { throw 'An oversized model response was accepted.' }
    }
}
