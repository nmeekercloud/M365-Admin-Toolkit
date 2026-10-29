BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    . (Join-Path $root 'Tools/Toolkit.NumericMenus.ps1')
}
Describe 'Shared connection explanations' {
    BeforeEach {
        InModuleScope M365Toolkit.Core {
            $script:M365Session=$null
            $script:Settings.Graph.BaseScopes=@('User.Read')
        }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
    }
    AfterEach { InModuleScope M365Toolkit.Core { $script:M365Session=$null } }
    It 'requires an explicit yes before an initial connection' {
        Mock -ModuleName M365Toolkit.Core Read-Host { '' }
        InModuleScope M365Toolkit.Core {
            Confirm-ToolkitConnectionExpansion -Services @('Graph') -Scopes @('User.Read') -GraphContext $null -TaskName 'Test task'
        } | Should -BeFalse
    }
    It 'does not start Graph authentication after cancellation' {
        Mock -ModuleName M365Toolkit.Core Read-Host { 'n' }
        Mock -ModuleName M365Toolkit.Core Get-ToolkitGraphContext { $null }
        Mock -ModuleName M365Toolkit.Core Connect-ToolkitGraph { throw 'Must not authenticate' }
        { Connect-M365 -TenantDomain contoso.com } | Should -Throw '*cancelled*'
        Should -Invoke -ModuleName M365Toolkit.Core Connect-ToolkitGraph -Times 0
    }
    It 'does not prompt when the verified Graph context already has the required access' {
        Mock -ModuleName M365Toolkit.Core Read-Host { throw 'Unexpected prompt' }
        InModuleScope M365Toolkit.Core {
            $script:M365Session=ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName Contoso -InitialDomain contoso.onmicrosoft.com -Account admin@contoso.com
            $ctx=[pscustomobject]@{TenantId=$script:M365Session.TenantId;Account='admin@contoso.com';Scopes=@('User.Read','Domain.Read.All')}
            Confirm-ToolkitConnectionExpansion -Services @('Graph') -Scopes @('User.Read','Domain.Read.All') -GraphContext $ctx -TaskName Test
        } | Should -BeTrue
        Should -Invoke -ModuleName M365Toolkit.Core Read-Host -Times 0
    }
    It 'requests approval for additional scopes' {
        Mock -ModuleName M365Toolkit.Core Read-Host { 'y' }
        InModuleScope M365Toolkit.Core {
            $script:M365Session=ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName Contoso -InitialDomain contoso.onmicrosoft.com -Account admin@contoso.com
            $ctx=[pscustomobject]@{TenantId=$script:M365Session.TenantId;Account='admin@contoso.com';Scopes=@('User.Read')}
            Confirm-ToolkitConnectionExpansion -Services @('Graph') -Scopes @('User.Read','Domain.Read.All') -GraphContext $ctx -TaskName Test
        } | Should -BeTrue
        Should -Invoke -ModuleName M365Toolkit.Core Read-Host -Times 1
    }
    It 'refuses an externally changed Graph account' {
        Mock -ModuleName M365Toolkit.Core Read-Host { throw 'Must stop before prompting' }
        {
            InModuleScope M365Toolkit.Core {
                $script:M365Session=ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName Contoso -InitialDomain contoso.onmicrosoft.com -Account admin@contoso.com
                $ctx=[pscustomobject]@{TenantId=$script:M365Session.TenantId;Account='other@contoso.com';Scopes=@('User.Read')}
                Confirm-ToolkitConnectionExpansion -Services @('Graph') -Scopes @('User.Read') -GraphContext $ctx -TaskName Test
            }
        } | Should -Throw '*account changed*'
    }
    It 'refuses Exchange reuse under a different account' {
        Mock -ModuleName M365Toolkit.Core Get-ToolkitExchangeConnection {
            [pscustomobject]@{TenantID='11111111-2222-3333-4444-555555555555';UserPrincipalName='other@contoso.com'}
        }
        {
            InModuleScope M365Toolkit.Core {
                $script:M365Session=ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName Contoso -InitialDomain contoso.onmicrosoft.com -Account admin@contoso.com
                $ctx=[pscustomobject]@{TenantId=$script:M365Session.TenantId;Account='admin@contoso.com';Scopes=@('User.Read')}
                Confirm-ToolkitConnectionExpansion -Services @('Graph','ExchangeOnline') -Scopes @('User.Read') -GraphContext $ctx -TaskName Test
            }
        } | Should -Throw '*different account*'
    }
    It 'keeps NoPrompt noninteractive when access is missing' {
        Mock -ModuleName M365Toolkit.Core Read-Host { throw 'Must not prompt' }
        Mock -ModuleName M365Toolkit.Core Get-ToolkitGraphContext { $null }
        { Assert-M365Connection -NoPrompt } | Should -Throw '*Not connected*'
        Should -Invoke -ModuleName M365Toolkit.Core Read-Host -Times 0
    }
    It 'a subsequent standalone task assertion does not reconnect unnecessarily' {
        Mock -ModuleName M365Toolkit.Core Read-Host { throw 'Unexpected prompt' }
        Mock -ModuleName M365Toolkit.Core Connect-M365 { throw 'Unexpected reconnection' }
        InModuleScope M365Toolkit.Core {
            $script:M365Session=ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName Contoso -InitialDomain contoso.onmicrosoft.com -Account admin@contoso.com
        }
        Mock -ModuleName M365Toolkit.Core Get-ToolkitGraphContext {
            [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com';Scopes=@('User.Read','Domain.Read.All')}
        }
        $null=Assert-M365Connection -Service Graph -GraphScopes @('Domain.Read.All')
        Should -Invoke -ModuleName M365Toolkit.Core Connect-M365 -Times 0
    }
}
Describe 'Separate SharePoint and OneDrive main-menu categories' {
    It 'shows both categories directly and keeps their original task paths' {
        $sp=[pscustomobject]@{Id='sharepoint';Name='SharePoint Administration';Order=30;Tasks=@([pscustomobject]@{Path='Scripts/SharePoint/example.ps1'})}
        $od=[pscustomobject]@{Id='onedrive';Name='OneDrive Administration';Order=40;Tasks=@([pscustomobject]@{Path='Scripts/OneDrive/example.ps1'})}
        $entries=@(Get-ToolkitMainMenuEntries -Catalog @($sp,$od))
        $cats=@($entries | Where-Object Action -eq Category)
        $cats.Count | Should -Be 2
        $cats[0].Category.Id | Should -Be 'sharepoint'
        $cats[1].Category.Id | Should -Be 'onedrive'
        $cats[0].Label | Should -Be 'SharePoint Administration'
        $cats[1].Label | Should -Be 'OneDrive Administration'
        $cats[0].Category.Tasks[0].Path | Should -Be 'Scripts/SharePoint/example.ps1'
        $cats[1].Category.Tasks[0].Path | Should -Be 'Scripts/OneDrive/example.ps1'
        @($cats | Where-Object Label -eq 'SharePoint & OneDrive').Count | Should -Be 0
    }
    It 'keeps numeric keys sequential with custom categories' {
        $cats=@([pscustomobject]@{Id='custom';Name='Custom';Order=10;Tasks=@()})
        $entries=@(Get-ToolkitMainMenuEntries -Catalog $cats)
        @($entries.Key) | Should -Be @('1','2','3','4','5','6')
    }
    It 'preserves a standalone category when its counterpart is absent' {
        $sp=[pscustomobject]@{Id='sharepoint';Name='SharePoint Administration';Order=30;Tasks=@()}
        @((Get-ToolkitMainMenuEntries -Catalog @($sp)) | Where-Object Action -eq Category).Count | Should -Be 1
    }
    It 'renumbers controls after both direct categories without duplicate keys' {
        $sp=[pscustomobject]@{Id='sharepoint';Name='SharePoint';Order=30;Tasks=@()}
        $od=[pscustomobject]@{Id='onedrive';Name='OneDrive';Order=40;Tasks=@()}
        $entries=@(Get-ToolkitMainMenuEntries -Catalog @($sp,$od))
        @($entries.Key) | Should -Be @('1','2','3','4','5','6','7')
        @($entries | Where-Object Action -eq Disconnect).Count | Should -Be 1
    }
}
