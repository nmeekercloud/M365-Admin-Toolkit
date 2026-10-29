BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $TenantDomain=''
    . (Join-Path $root 'Tools/Toolkit.ConnectionProfiles.ps1')
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    function New-PlanTask {
        param($Id='tenant.domains',$Scopes=@('Domain.Read.All'),$Status='Ready',$Access='ReadOnly',$Review='Reviewed',$Services=@('Graph'))
        [pscustomobject]@{Id=$Id;Name=$Id;Status=$Status;AccessMode=$Access;PermissionReview=$Review;Services=$Services;GraphScopes=$Scopes}
    }
}
Describe 'Task-first connection plans' {
    BeforeEach {
        $read=New-PlanTask
        $fixture=@([pscustomobject]@{Id='tenant';Tasks=@($read)})
    }
    It 'does not request an upfront preset in any mode' {
        foreach ($mode in @('Administration','Reporting','OnDemand')) {
            $plan=Get-ToolkitConnectionPlan -Catalog $fixture -Mode $mode
            @($plan.Services).Count | Should -Be 0
            @($plan.GraphScopes).Count | Should -Be 0
        }
    }
    It 'uses the selected task and identity baseline' {
        $plan=Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture
        $plan.Services | Should -Contain 'Graph'
        $plan.Services | Should -Not -Contain 'SharePoint'
        $plan.GraphScopes | Should -Contain 'User.Read'
        $plan.GraphScopes | Should -Contain 'Domain.Read.All'
    }
    It 'bundles a reviewed Ready read task in the same group' {
        $fixture[0].Tasks+=New-PlanTask -Id tenant.details -Scopes @('Organization.Read.All')
        $plan=Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture
        $plan.GraphScopes | Should -Contain 'Organization.Read.All'
    }
    It 'excludes planned, disabled, change and unreviewed companions' {
        $fixture[0].Tasks+=New-PlanTask -Id tenant.planned -Status Planned -Scopes @('planned.scope')
        $fixture[0].Tasks+=New-PlanTask -Id tenant.disabled -Status Disabled -Scopes @('disabled.scope')
        $fixture[0].Tasks+=New-PlanTask -Id tenant.write -Access Changes -Scopes @('User.ReadWrite.All')
        $fixture[0].Tasks+=New-PlanTask -Id tenant.unreviewed -Review Unreviewed -Scopes @('unreviewed.scope')
        $plan=Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture
        @($plan.GraphScopes).Count | Should -Be 2
    }
    It 'never adds PnP from a companion task' {
        $fixture[0].Tasks+=New-PlanTask -Id tenant.pnp -Services @('Graph','SharePoint') -Scopes @('Sites.Read.All')
        $plan=Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture
        $plan.Services | Should -Not -Contain 'SharePoint'
        $plan.GraphScopes | Should -Not -Contain 'Sites.Read.All'
    }
    It 'does not bundle another category' {
        $fixture+=[pscustomobject]@{Id='users';Tasks=@((New-PlanTask -Id users.list -Scopes @('User.Read.All')))}
        (Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture).GraphScopes | Should -Not -Contain 'User.Read.All'
    }
    It 'does not bundle for a change task' {
        $change=New-PlanTask -Id tenant.change -Access Changes -Scopes @('User.ReadWrite.All')
        $fixture[0].Tasks+=$change
        (Get-ToolkitTaskConnectionPlan -Task $change -Catalog $fixture).GraphScopes | Should -Not -Contain 'Domain.Read.All'
    }
    It 'shares the permission group across SharePoint and OneDrive without adding providers' {
        $sp=New-PlanTask -Id sp.read -Scopes @('Sites.Read.All')
        $od=New-PlanTask -Id od.read -Scopes @('Files.Read.All')
        $cats=@([pscustomobject]@{Id='sharepoint';Tasks=@($sp)},[pscustomobject]@{Id='onedrive';Tasks=@($od)})
        $plan=Get-ToolkitTaskConnectionPlan -Task $sp -Catalog $cats
        $plan.PermissionGroup | Should -Be 'sharepoint-onedrive'
        $plan.GraphScopes | Should -Contain 'Files.Read.All'
        $plan.Services | Should -Not -Contain 'SharePoint'
    }
    It 'bounds bundles rather than growing an unlimited preset' {
        foreach ($i in 1..9) { $fixture[0].Tasks+=New-PlanTask -Id ('tenant.'+$i) -Scopes @('scope.'+$i) }
        @((Get-ToolkitTaskConnectionPlan -Task $read -Catalog $fixture).GraphScopes).Count | Should -Be 2
    }
}
Describe 'Task policy guard' {
    AfterEach { Set-M365TaskPolicy -Mode OnDemand }
    It 'blocks change tasks in Reporting' {
        Set-M365TaskPolicy -Mode Reporting
        { Assert-M365TaskAccess -AccessMode Changes -TaskId example.change } | Should -Throw '*blocked*'
    }
    It 'allows read tasks in Reporting' {
        Set-M365TaskPolicy -Mode Reporting
        { Assert-M365TaskAccess -AccessMode ReadOnly -TaskId example.read } | Should -Not -Throw
    }
    It 'mode initialization does not connect' {
        Mock Connect-M365 { throw 'Unexpected authentication' }
        $null=Initialize-ToolkitConnectionProfile -Mode OnDemand -TargetTenant contoso.com
        Should -Invoke Connect-M365 -Times 0
    }
}
