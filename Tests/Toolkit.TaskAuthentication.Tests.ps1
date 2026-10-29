#Requires -Version 7.4
# Pester 5; no tenant authentication is performed by these tests.
BeforeAll {
    $root=Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    $TenantDomain=$null
    . (Join-Path $root 'Tools/Toolkit.Catalog.ps1')
    . (Join-Path $root 'Tools/Toolkit.ConnectionProfiles.ps1')
    $script:catalog=@(Get-ToolkitCatalog -Root $root)
}
AfterAll { Remove-Module M365Toolkit.Core -Force -ErrorAction SilentlyContinue }
Describe 'Complete task authentication plans' {
    It 'preserves declared access for every Ready menu task' {
        foreach ($task in @($script:catalog | ForEach-Object { $_.Tasks } | Where-Object Status -eq 'Ready')) {
            $plan=Get-ToolkitTaskConnectionPlan -Task $task -Catalog $script:catalog
            foreach ($scope in $task.GraphScopes) { $plan.GraphScopes | Should -Contain $scope }
            foreach ($service in $task.Services) { $plan.Services | Should -Contain $service }
        }
    }
    It 'includes creation, licensing and group permissions without unrelated providers' {
        $module=Get-Module M365Toolkit.Core
        $req=& $module { Get-ToolkitTaskAuthenticationRequirements -TaskId 'users.new-user' }
        foreach ($scope in @('User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All')) { $req.GraphScopes | Should -Contain $scope }
        @($req.Services | Where-Object { $_ -ne 'Graph' }).Count | Should -Be 0
    }
    It 'unions all seven implemented offboarding children including archive' {
        $module=Get-Module M365Toolkit.Core
        $req=& $module { Get-ToolkitTaskAuthenticationRequirements -TaskId 'users.disable-user' }
        $req.TaskIds.Count | Should -Be 8
        foreach ($id in @('users.disable-user','users.block-access','exchange.convert-shared','exchange.set-mailboxforwarding','exchange.set-mailboxautoreply','exchange.set-mailboxdelegates','users.remove-licenses','onedrive.backup-onedrive')) { $req.TaskIds | Should -Contain $id }
        $req.Services | Should -Contain 'SharePoint'
        $req.Services | Should -Contain 'ExchangeOnline'
        foreach ($scope in @('User.EnableDisableAccount.All','User.RevokeSessions.All','LicenseAssignment.ReadWrite.All')) { $req.GraphScopes | Should -Contain $scope }
    }
    It 'covers all supported CSV actions and license preservation' {
        $module=Get-Module M365Toolkit.Core
        $req=& $module { Get-ToolkitTaskAuthenticationRequirements -TaskId 'users.invoke-bulkusermanagement' }
        foreach ($scope in @('User.ReadWrite.All','User.EnableDisableAccount.All','User.RevokeSessions.All')) { $req.GraphScopes | Should -Contain $scope }
        $license=& $module { Get-ToolkitTaskAuthenticationRequirements -TaskId 'users.remove-licenses' }
        $license.Services | Should -Contain 'ExchangeOnline'
    }
    It 'rejects cyclic, missing or non-Ready dependencies' {
        InModuleScope M365Toolkit.Core {
            $defs=@{
                a=@{Status='Ready';Services=@('Graph');GraphScopes=@();AuthenticationDependencies=@('b')}
                b=@{Status='Ready';Services=@('Graph');GraphScopes=@();AuthenticationDependencies=@('a')}
            }
            $policy=@{SchemaVersion=1;Tasks=@{}}
            { Get-ToolkitTaskAuthenticationRequirements -TaskId a -Definitions $defs -Policy $policy } | Should -Throw '*cycle*'
            $defs.Remove('b')
            { Get-ToolkitTaskAuthenticationRequirements -TaskId a -Definitions $defs -Policy $policy } | Should -Throw '*missing*'
            $defs.b=@{Status='Planned';Services=@('Graph');GraphScopes=@()}
            { Get-ToolkitTaskAuthenticationRequirements -TaskId a -Definitions $defs -Policy $policy } | Should -Throw '*not Ready*'
        }
    }
}
Describe 'Mid-task assertions never authenticate' {
    BeforeEach {
        InModuleScope M365Toolkit.Core {
            $script:M365Session=[pscustomobject]@{TenantId='tenant-id';Account='admin@contoso.com';VerifiedDomains=@('contoso.com');InitialDomain='contoso.com';SharePoint=[pscustomobject]@{Connected=$false}}
            $script:ToolkitActiveTaskAuthentication=[pscustomobject]@{TaskId='users.new-user';Services=@('Graph');GraphScopes=@('User.Read','User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All')}
            Mock Get-ToolkitSetting { param($Path,$Default) if ($Path -eq 'Graph.BaseScopes') { @('User.Read') } else { $Default } }
            Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='tenant-id';Account='admin@contoso.com';Scopes=@('User.Read','User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All')} }
            Mock Get-M365TenantInfo { $script:M365Session }
            Mock Write-M365Log {}
            Mock Connect-M365 { throw 'Unexpected connection attempt' }
        }
    }
    AfterEach {
        InModuleScope M365Toolkit.Core { $script:ToolkitActiveTaskAuthentication=$null; $script:M365Session=$null }
    }
    It 'reuses the session for licensing and groups' {
        InModuleScope M365Toolkit.Core {
            $null=Assert-M365Connection -GraphScopes @('User.ReadWrite.All','LicenseAssignment.Read.All')
            $null=Assert-M365Connection -GraphScopes @('User.ReadWrite.All','Group.Read.All','GroupMember.ReadWrite.All')
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'stops undeclared scope expansion without prompting' {
        InModuleScope M365Toolkit.Core {
            { Assert-M365Connection -GraphScopes @('Directory.ReadWrite.All') } | Should -Throw '*undeclared access*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'stops if the Graph context disappears' {
        InModuleScope M365Toolkit.Core {
            Mock Get-ToolkitGraphContext { $null }
            { Assert-M365Connection -GraphScopes @('User.ReadWrite.All') } | Should -Throw '*Not connected*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'stops if a granted scope disappears' {
        InModuleScope M365Toolkit.Core {
            Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='tenant-id';Account='admin@contoso.com';Scopes=@('User.Read')} }
            { Assert-M365Connection -GraphScopes @('User.ReadWrite.All') } | Should -Throw '*no longer available*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'keeps tenant mismatch protections' {
        InModuleScope M365Toolkit.Core {
            Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='wrong-tenant';Account='admin@contoso.com';Scopes=@('User.Read')} }
            { Assert-M365Connection } | Should -Throw '*not the verified tenant*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'keeps account mismatch protections' {
        InModuleScope M365Toolkit.Core {
            Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='tenant-id';Account='other@contoso.com';Scopes=@('User.Read')} }
            { Assert-M365Connection } | Should -Throw '*account changed*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'does not authenticate Exchange during a preservation step' {
        InModuleScope M365Toolkit.Core {
            $script:ToolkitActiveTaskAuthentication.Services=@('Graph','ExchangeOnline')
            Mock Get-ToolkitExchangeConnection { $null }
            { Assert-M365Connection -Service ExchangeOnline } | Should -Throw '*no longer available*'
            Should -Invoke Connect-M365 -Times 0 -Exactly
        }
    }
    It 'allows a new connection at a new task boundary' {
        InModuleScope M365Toolkit.Core {
            $script:ToolkitActiveTaskAuthentication=$null
            Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='tenant-id';Account='admin@contoso.com';Scopes=@('User.Read')} }
            Mock Connect-M365 {}
            $null=Assert-M365Connection -GraphScopes @('User.ReadWrite.All')
            Should -Invoke Connect-M365 -Times 1 -Exactly
        }
    }
}
Describe 'Nested explicit Connect-M365 calls' {
    BeforeEach {
        InModuleScope M365Toolkit.Core {
            $script:ToolkitActiveTaskAuthentication=[pscustomobject]@{TaskId='test.task';Services=@('Graph');GraphScopes=@('User.Read')}
            Mock Assert-M365Connection {}
            Mock Get-M365TenantInfo { [pscustomobject]@{TenantId='tenant-id'} }
            Mock Connect-ToolkitGraph { throw 'Unexpected provider authentication' }
        }
    }
    AfterEach {
        InModuleScope M365Toolkit.Core { $script:ToolkitActiveTaskAuthentication=$null }
    }
    It 'delegates to a noninteractive assertion' {
        InModuleScope M365Toolkit.Core {
            $null=Connect-M365 -Service Graph -GraphScopes @('User.Read') -PassThru
            Should -Invoke Assert-M365Connection -Times 1 -Exactly -ParameterFilter { $NoPrompt }
            Should -Invoke Connect-ToolkitGraph -Times 0 -Exactly
        }
    }
}
Describe 'Dispatcher guard lifetime' {
    It 'restores the guard even when workflow execution fails' {
        $module=Get-Module M365Toolkit.Core
        $task=@($script:catalog | ForEach-Object { $_.Tasks } | Where-Object Id -eq 'users.new-user')[0].PSObject.Copy()
        $task.Path=Join-Path $TestDrive 'ThrowingTask.ps1'
        Set-Content -LiteralPath $task.Path -Value "throw 'synthetic task failure'"
        Mock Assert-M365TaskAccess {}
        Mock Assert-M365Connection { [pscustomobject]@{TenantId='tenant-id'} }
        $script:ToolkitConnectionMode='OnDemand'; $script:ToolkitPreferredTenant=$null
        { Invoke-ToolkitPreparedTask -Task $task } | Should -Throw '*synthetic task failure*'
        $active=& $module { $script:ToolkitActiveTaskAuthentication }
        $active | Should -BeNullOrEmpty
    }
}
