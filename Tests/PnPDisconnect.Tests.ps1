BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    foreach ($name in @('Get-PnPConnection','Disconnect-PnPOnline')) {
        if (-not (Get-Command $name -ListImported -ErrorAction SilentlyContinue)) {
            if ($name -eq 'Get-PnPConnection') {
                function global:Get-PnPConnection { [CmdletBinding()] param() }
            }
            else {
                function global:Disconnect-PnPOnline { [CmdletBinding()] param([switch]$ClearPersistedLogin) }
            }
        }
    }
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
}
Describe 'PnP disconnect absence handling' {
    BeforeEach {
        Mock -ModuleName M365Toolkit.Core Write-M365Log {}
        Mock -ModuleName M365Toolkit.Core Get-ToolkitGraphContext { $null }
        Mock -ModuleName M365Toolkit.Core Get-ToolkitExchangeConnection { $null }
        Mock -ModuleName M365Toolkit.Core Disconnect-PnPOnline {}
        InModuleScope M365Toolkit.Core {
            $script:M365Session=ConvertTo-ToolkitSession -TenantId 'test-tenant' -TenantName 'Example' -InitialDomain 'contoso.onmicrosoft.com' -Account 'admin@contoso.com'
        }
    }
    AfterEach { InModuleScope M365Toolkit.Core { $script:M365Session=$null } }
    It 'treats the reported not-signed-in response as no global session' {
        Mock -ModuleName M365Toolkit.Core Get-PnPConnection { throw 'You are not signed in. Please use Connect-PnPOnline to connect.' }
        { Disconnect-M365 -Service All } | Should -Not -Throw
        Get-M365TenantInfo | Should -BeNullOrEmpty
        Should -Invoke -ModuleName M365Toolkit.Core Disconnect-PnPOnline -Times 0 -Exactly
    }
    It 'releases an owned ReturnConnection reference when no global session exists' {
        InModuleScope M365Toolkit.Core {
            $script:M365Session.SharePoint.Connected=$true
            $script:M365Session.SharePoint.Connection=[pscustomobject]@{Marker='owned-connection'}
        }
        Mock -ModuleName M365Toolkit.Core Get-PnPConnection { throw 'You are not signed in. Please use Connect-PnPOnline to connect.' }
        Disconnect-M365 -Service SharePoint
        InModuleScope M365Toolkit.Core {
            $script:M365Session.SharePoint.Connection | Should -BeNullOrEmpty
            $script:M365Session.SharePoint.Connected | Should -BeFalse
        }
    }
    It 'disconnects a global PnP session when one is present' {
        Mock -ModuleName M365Toolkit.Core Get-PnPConnection { [pscustomobject]@{Marker='global-session'} }
        Disconnect-M365 -Service All
        Should -Invoke -ModuleName M365Toolkit.Core Disconnect-PnPOnline -Times 1 -Exactly
    }
    It 'does not hide unexpected PnP errors or clear the entire tenant session' {
        Mock -ModuleName M365Toolkit.Core Get-PnPConnection { throw 'Unexpected provider failure' }
        { Disconnect-M365 -Service All } | Should -Throw '*Unexpected provider failure*'
        Get-M365TenantInfo | Should -Not -BeNullOrEmpty
    }
}
