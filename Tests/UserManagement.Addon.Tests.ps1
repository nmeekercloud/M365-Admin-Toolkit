#Requires -Version 7.4
BeforeAll {
    $root=Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
    # Stub the Graph command so tests never import Graph or authenticate.
    function Invoke-MgGraphRequest { param($Method,$Uri,$OutputType,$Body,$ContentType) throw 'Unexpected live Graph call in offline test.' }
}
Describe 'User Management group safety' {
    BeforeEach {
        $group=@{id='11111111-1111-1111-1111-111111111111';groupTypes=@();mailEnabled=$false;securityEnabled=$true;isAssignableToRole=$false;onPremisesSyncEnabled=$null}
    }
    It 'allows a static cloud security group' { Get-UMGroupReason $group | Should -Be '' }
    It 'allows a static Microsoft 365 group' {
        $group.groupTypes=@('Unified'); $group.mailEnabled=$true
        Get-UMGroupReason $group | Should -Be ''
    }
    It 'rejects role-assignable groups' {
        $group.isAssignableToRole=$true
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
    It 'allows an explicit null role flag for an otherwise complete ordinary group' {
        $group.isAssignableToRole=$null
        Get-UMGroupReason $group | Should -Be ''
    }
    It 'rejects malformed role status instead of coercing it to false' {
        $group.isAssignableToRole='false'
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
    It 'rejects dynamic groups' {
        $group.groupTypes=@('Unified','DynamicMembership')
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
    It 'rejects synchronized groups' {
        $group.onPremisesSyncEnabled=$true
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
    It 'rejects Exchange-managed groups' {
        $group.mailEnabled=$true
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
    It 'fails closed if metadata is missing' {
        $group.Remove('isAssignableToRole')
        Get-UMGroupReason $group | Should -Not -BeNullOrEmpty
    }
}
Describe 'User Management account safety' {
    BeforeEach {
        $user=@{userPrincipalName='test@contoso.com';userType='Member';onPremisesSyncEnabled=$false}
        $tenant=[pscustomobject]@{Account='admin@contoso.com'}
    }
    It 'permits a separate cloud member' { { Assert-UMCloudMember -User $user -Tenant $tenant } | Should -Not -Throw }
    It 'rejects guests' { $user.userType='Guest'; { Assert-UMCloudMember -User $user -Tenant $tenant } | Should -Throw }
    It 'permits synchronized tenant Members while leaving per-operation authority checks intact' { $user.onPremisesSyncEnabled=$true; { Assert-UMCloudMember -User $user -Tenant $tenant } | Should -Not -Throw }
    It 'blocks self modification case insensitively' {
        $user.userPrincipalName='ADMIN@contoso.com'
        { Assert-UMCloudMember -User $user -Tenant $tenant } | Should -Throw
    }
    It 'allows self only when explicitly requested for a read source' {
        $user.userPrincipalName=$tenant.Account
        { Assert-UMCloudMember -User $user -Tenant $tenant -AllowSelf } | Should -Not -Throw
    }
}
Describe 'CSV field handling' {
    It 'only maps allowed nonblank profile fields' {
        $row=[pscustomobject]@{DisplayName=' Test ';Department='';JobTitle='Engineer';OfficeLocation=' ';Password='SECRET';accountEnabled='true'}
        $body=New-UMProfileBody $row
        $body.Count | Should -Be 2
        $body['displayName'] | Should -Be 'Test'
        $body['jobTitle'] | Should -Be 'Engineer'
        $body.ContainsKey('Password') | Should -BeFalse
        $body.ContainsKey('accountEnabled') | Should -BeFalse
    }
    It 'deduplicates and trims comma or semicolon inputs' {
        $list=@(ConvertTo-UMList ' a, b; a, ,')
        $list.Count | Should -Be 2
        $list[0] | Should -Be 'a'
    }
}
Describe 'Graph transport and pagination' {
    It 'rejects foreign next-link hosts' {
        { Invoke-UMGraph -Path 'https://example.com/v1.0/users' } | Should -Throw
    }
    It 'follows Graph next links without dropping items' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -like '*skiptoken*') { return @{value=@(@{id='2'})} }
            return @{value=@(@{id='1'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/users?$skiptoken=next'}
        }
        $items=@(Get-UMCollection '/users')
        $items.Count | Should -Be 2
        $items[0]['id'] | Should -Be '1'
        $items[1]['id'] | Should -Be '2'
        Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
    }
    It 'serializes membership bodies without changing the endpoint' {
        Mock Invoke-MgGraphRequest { return @{} }
        $null=Invoke-UMGraph -Method POST -Path '/groups/test/members/$ref' -Body @{'@odata.id'='https://graph.microsoft.com/v1.0/directoryObjects/test'}
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/v1.0/groups/test/members/$ref' -and
            ($Body | ConvertFrom-Json).'@odata.id' -eq 'https://graph.microsoft.com/v1.0/directoryObjects/test'
        }
    }
}
Describe 'Task integration and syntax' {
    It 'has four change tasks with Ready scripts' {
        $names=@('New-User','Disable-User','Copy-UserAccess','Invoke-BulkUserManagement')
        foreach ($name in $names) {
            $def=Import-PowerShellDataFile (Join-Path $root "Scripts/Users/$name.task.psd1")
            $def.Status | Should -Be 'Ready'
            $def.AccessMode | Should -Be 'Changes'
            # Not claimed as externally reviewed or suitable for Reporting bundles.
            $def.PermissionReview | Should -Be 'Unreviewed'
            $path=Join-Path $root ('Scripts/Users/'+$def.Script)
            Test-Path $path | Should -BeTrue
            $tokens=$null; $errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
            $source=Get-Content $path -Raw
            $source | Should -Match 'SupportsShouldProcess'
            if ($name -eq 'Disable-User') {
                # Dispatcher approves the frozen plan, then passes bound approval to children.
                $source | Should -Match 'Type DELETE to confirm'
                $source | Should -Match 'Execute this plan'
                $source | Should -Match 'if \(-not \$WhatIfPreference\)'
                $source | Should -Match 'WorkflowApproval'
                $source | Should -Match 'WhatIf=\[bool\]\$WhatIfPreference'
                $source.IndexOf('Execute this plan') | Should -BeLessThan $source.IndexOf('$output=@(&')
            } else {
                $source | Should -Match 'Confirm-M365Action'
            }
            $source | Should -Match 'ShouldProcess'
            $source | Should -Match 'Initialize-UMTask'
        }
    }
}
