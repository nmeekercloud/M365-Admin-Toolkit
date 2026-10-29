BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    . (Join-Path $root 'Tools/Toolkit.Exit.ps1')
}
Describe 'Exit cleanup' {
    It 'requests all services and reports success' {
        Mock Disconnect-M365 {}
        Mock Write-Host {}
        Invoke-ToolkitExitCleanup | Should -BeTrue
        Should -Invoke Disconnect-M365 -Times 1 -ParameterFilter { $Service -contains 'All' }
    }
    It 'reports cleanup failure without throwing back into the menu loop' {
        Mock Disconnect-M365 { throw 'Simulated disconnect failure' }
        Mock Write-Warning {}
        Invoke-ToolkitExitCleanup | Should -BeFalse
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Simulated disconnect failure*' }
    }
}
