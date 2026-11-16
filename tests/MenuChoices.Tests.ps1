Describe 'REMNEXA numbered menu choices' {
    BeforeEach {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module -Name (Join-Path $projectRoot 'Core\MenuChoices.psd1') -Force -ErrorAction Stop
    }

    AfterEach {
        Remove-Module MenuChoices -ErrorAction SilentlyContinue
    }

    It 'accepts an explicit return choice and displayed item numbers' {
        if ((ConvertFrom-RemnexaMenuChoice -InputText '0' -Maximum 4) -ne 0) { throw 'Zero should return from the submenu.' }
        if ((ConvertFrom-RemnexaMenuChoice -InputText ' 3 ' -Maximum 4) -ne 3) { throw 'A displayed item number should be accepted.' }
    }

    It 'rejects empty, nonnumeric, negative, and out-of-range input' {
        foreach ($inputText in @('', 'abc', '-1', '5')) {
            if ($null -ne (ConvertFrom-RemnexaMenuChoice -InputText $inputText -Maximum 4)) {
                throw "Invalid choice '$inputText' was accepted."
            }
        }
    }
}
