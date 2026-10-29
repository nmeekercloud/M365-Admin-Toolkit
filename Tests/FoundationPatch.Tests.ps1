BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
}
Describe 'Foundation path safeguards' {
    It 'rejects output under the toolkit root' {
        InModuleScope M365Toolkit.Core {
            { Assert-ToolkitExternalPath -Path (Join-Path $script:ToolkitRoot 'Exports') } | Should -Throw '*repository*'
        }
    }
    It 'rejects relative output paths' {
        InModuleScope M365Toolkit.Core {
            { Assert-ToolkitExternalPath -Path 'relative-output' } | Should -Throw '*absolute*'
        }
    }
    It 'exports the CSV helper' {
        Get-Command Export-M365Csv -Module M365Toolkit.Core | Should -Not -BeNullOrEmpty
    }
}
