Describe 'REMNEXA source package integrity' {
    BeforeEach {
        $script:packageProject = Split-Path -Parent $PSScriptRoot
        $script:packageFixture = Join-Path ([IO.Path]::GetTempPath()) ('REMNEXA-PackageTest-' + [guid]::NewGuid().ToString('N'))
        $script:packageSource = Join-Path $script:packageFixture 'source'
        $script:packageOutput = Join-Path $script:packageFixture 'output'
        $script:packageGit = (Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if (-not $script:packageGit) { $script:packageGit = Join-Path $env:ProgramFiles 'Git\cmd\git.exe' }
        if (-not (Test-Path -LiteralPath $script:packageGit)) { throw 'Git is required for package fixtures.' }
        New-Item -ItemType Directory -Path $script:packageSource | Out-Null
        foreach ($relative in @('REMNEXA.ps1','REMNEXA.cmd','LICENSE','README.md','README.de.md','Core/PathSafety.psd1','locales/en.json','locales/de.json','config/antivirus.json','.gitignore')) {
            $path = Join-Path $script:packageSource $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            $value = 'source fixture'
            if ($relative -eq 'REMNEXA.ps1') { $value = '$script:CleanerVersion = ''2.2.0-rc.1''' }
            if ($relative -eq '.gitignore') { $value = "*.log`nruntime/" }
            [IO.File]::WriteAllText($path, $value, [Text.UTF8Encoding]::new($false))
        }
        & $script:packageGit -C $script:packageSource init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Fixture repository initialization failed.' }
        & $script:packageGit -C $script:packageSource add --all 2>$null
        & $script:packageGit -C $script:packageSource -c user.name=REMNEXA-Test -c user.email=test@example.invalid -c commit.gpgsign=false commit --quiet -m fixture
        if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed.' }
        [IO.File]::WriteAllText((Join-Path $script:packageSource 'private.log'), 'ignored local fixture')
        $script:packageBuilder = Join-Path $script:packageProject 'tools\New-RemnexaPackage.ps1'
        $script:packageVerifier = Join-Path $script:packageProject 'tools\Test-RemnexaPackage.ps1'
    }

    AfterEach {
        if ($script:packageFixture) {
            $resolved = [IO.Path]::GetFullPath($script:packageFixture)
            if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
                (Split-Path -Leaf $resolved) -like 'REMNEXA-PackageTest-*' -and (Test-Path -LiteralPath $resolved)) {
                Remove-Item -LiteralPath $resolved -Recurse -Force
            }
        }
    }

    It 'builds and verifies a tracked-source package without local logs or Git metadata' {
        $result = & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit
        $check = & $script:packageVerifier -Path $result.Package -ExpectedSha256 $result.SHA256
        if (-not $check.Passed -or $check.FilesVerified -ne 10 -or $check.WorkingTreeDirty) { throw 'Unexpected verification result.' }
        $sidecar = [IO.File]::ReadAllText($result.Checksum).Trim()
        if ($sidecar -cne ($result.SHA256 + '  ' + [IO.Path]::GetFileName($result.Package))) { throw 'Invalid checksum sidecar.' }
        $zip = [IO.Compression.ZipFile]::OpenRead($result.Package)
        try {
            if (@($zip.Entries | Where-Object { $_.FullName -match '/\.git/|private\.log' }).Count) { throw 'Private local content entered the package.' }
        }
        finally { $zip.Dispose() }
    }

    It 'refuses existing output without modifying it' {
        $result = & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit
        $rejected = $false
        try { & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit | Out-Null } catch { $rejected = $true }
        if (-not $rejected -or (Get-FileHash -LiteralPath $result.Package -Algorithm SHA256).Hash -ne $result.SHA256) { throw 'Existing package was not protected.' }
    }

    It 'ignores CI test reports even when Git compares filename case strictly' {
        [IO.File]::WriteAllText((Join-Path $script:packageSource '.gitignore'),[IO.File]::ReadAllText((Join-Path $script:packageProject '.gitignore')))
        & $script:packageGit -C $script:packageSource config core.ignorecase false
        foreach($name in @('testResults.xml','TestResults.xml','dist/pester-results.xml')){
            & $script:packageGit -C $script:packageSource check-ignore --quiet -- $name
            if($LASTEXITCODE -ne 0){throw ('Generated test report is not ignored: '+$name)}
        }
    }

    It 'selects one executable when Git is available in several PATH directories' {
        $gitRoot=Split-Path -Parent (Split-Path -Parent $script:packageGit)
        $directories=@(foreach($relative in @('bin','cmd','ucrt64/bin','mingw64/bin')){
            $directory=Join-Path $gitRoot $relative
            if(Test-Path -LiteralPath (Join-Path $directory 'git.exe')){$directory}
        })
        if($directories.Count -lt 2){throw 'This Windows Git fixture requires two executable locations.'}
        $originalPath=$env:PATH
        try{
            $env:PATH=($directories -join ';')+';'+$originalPath
            if(@(Get-Command git -CommandType Application).Count -lt 2){throw 'Multiple-PATH regression was not exercised.'}
            $result=& $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1'
            if(-not (& $script:packageVerifier -Path $result.Package -ExpectedSha256 $result.SHA256).Passed){throw 'Default Git resolution failed.'}
        }finally{$env:PATH=$originalPath}
    }

    It 'rejects dirty sources and a mismatched application version' {
        $rejected = $false
        try { & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '9.0.0' -GitPath $script:packageGit | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'A mismatched version was accepted.' }
        [IO.File]::AppendAllText((Join-Path $script:packageSource 'README.md'), 'changed')
        $rejected = $false
        try { & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Dirty source was accepted.' }
    }

    It 'rejects changed content even when the ZIP remains readable' {
        $result = & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit
        $zip = [IO.Compression.ZipFile]::Open($result.Package, [IO.Compression.ZipArchiveMode]::Update)
        try {
            $name = 'REMNEXA-2.2.0-rc.1/README.md'
            $zip.GetEntry($name).Delete()
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($name).Open())
            try { $writer.Write('tampered data!') } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        $rejected = $false
        try { & $script:packageVerifier -Path $result.Package | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Tampered content was accepted.' }
    }

    It 'rejects traversal and case-insensitive duplicate entries without extracting files' {
        foreach ($suffix in @('../outside.txt','readme.md')) {
            $out = Join-Path $script:packageOutput ([guid]::NewGuid().ToString('N'))
            $result = & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $out -Version '2.2.0-rc.1' -GitPath $script:packageGit
            $zip = [IO.Compression.ZipFile]::Open($result.Package, [IO.Compression.ZipArchiveMode]::Update)
            try {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry(('REMNEXA-2.2.0-rc.1/' + $suffix)).Open())
                try { $writer.Write('invalid fixture') } finally { $writer.Dispose() }
            }
            finally { $zip.Dispose() }
            $rejected = $false
            try { & $script:packageVerifier -Path $result.Package | Out-Null } catch { $rejected = $true }
            if (-not $rejected) { throw 'An unsafe or duplicate entry was accepted.' }
        }
    }

    It 'rejects an incorrect expected archive hash' {
        $result = & $script:packageBuilder -SourcePath $script:packageSource -OutputDirectory $script:packageOutput -Version '2.2.0-rc.1' -GitPath $script:packageGit
        $rejected = $false
        try { & $script:packageVerifier -Path $result.Package -ExpectedSha256 ('0' * 64) | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'An incorrect expected digest was accepted.' }
    }
}
