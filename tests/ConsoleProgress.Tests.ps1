BeforeDiscovery {Import-Module (Join-Path $PSScriptRoot '../Core/Progress.psd1') -Force}
Describe 'One progress presentation per interactive operation' {
    InModuleScope Progress {
        BeforeEach {
            $script:ProgressActive.Clear()
            Set-RemnexaProgressRendering $true
            Mock Write-Host {}
            Mock Write-Progress {}
        }
        AfterEach {$script:ProgressActive.Clear();Set-RemnexaProgressRendering $false}
        It 'refreshes one native slot without printing forced frames or nested completion banners' {
            Mock Test-RemnexaInteractiveProgress {$true}
            $parent=New-RemnexaProgress -Activity engine
            Update-RemnexaProgress $parent -Status download -Force
            $child=New-RemnexaProgress -Activity download -Total 100 -Unit bytes
            Update-RemnexaProgress $child -Completed 50 -Force
            Complete-RemnexaProgress $child -Outcome Cancelled
            Should -Invoke Write-Host -Times 0
            Complete-RemnexaProgress $parent -Outcome Cancelled
            Should -Invoke Write-Host -Times 1 -Exactly
            Should -Invoke Write-Progress -Times 0 -ParameterFilter {$Id -ne 999 -or $Status -match '\[\|?\.*#*\]'}
        }
        It 'does not print successful nested task banners into redirected output' {
            Mock Test-RemnexaInteractiveProgress {$false}
            $parent=New-RemnexaProgress -Activity parent
            $child=New-RemnexaProgress -Activity status
            Complete-RemnexaProgress $child
            Complete-RemnexaProgress $parent
            Should -Invoke Write-Host -Times 2 -Exactly
            Should -Invoke Write-Progress -Times 0
        }
    }
}
