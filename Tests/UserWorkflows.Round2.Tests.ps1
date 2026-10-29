#Requires -Version 7.4
BeforeAll {
    $root=Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
    . (Join-Path $root 'Tools/Toolkit.UserWorkflows.ps1')
}
Describe 'License picker arithmetic and eligibility' {
    It 'calculates counts and hides identifiers from the display shape' {
        $skus=@(@{skuId='test-sku';skuPartNumber='SPB';prepaidUnits=@{enabled=10};consumedUnits=6;capabilityStatus='Enabled';appliesTo='User'})
        $row=@(Get-WFLicenseRows $skus)[0]
        $row.Available | Should -Be 4
        $row.Assigned | Should -Be 6
        $row.Eligible | Should -BeTrue
        $row.Product | Should -Match 'Business Premium'
        $row.Id | Should -Be 'test-sku'
    }
    It 'does not allow exhausted, suspended or company-based products' {
        $skus=@(
            @{skuId='a';skuPartNumber='a';prepaidUnits=@{enabled=2};consumedUnits=4;capabilityStatus='Enabled';appliesTo='User'},
            @{skuId='b';skuPartNumber='b';prepaidUnits=@{enabled=5};consumedUnits=0;capabilityStatus='Suspended';appliesTo='User'},
            @{skuId='c';skuPartNumber='c';prepaidUnits=@{enabled=5};consumedUnits=0;capabilityStatus='Enabled';appliesTo='Company'}
        )
        $rows=@(Get-WFLicenseRows $skus)
        @($rows | Where-Object Eligible).Count | Should -Be 0
        ($rows | Where-Object Id -eq 'a').Available | Should -Be 0
    }
    It 'falls back to the technical product name' { Get-WFProductName 'UNKNOWN_PRODUCT' | Should -Be 'UNKNOWN_PRODUCT' }
}
Describe 'Numbered selection safety' {
    BeforeEach {
        $rows=@([pscustomobject]@{Number=1;Eligible=$true;Id='a'},[pscustomobject]@{Number=2;Eligible=$false;Id='b'},[pscustomobject]@{Number=3;Eligible=$true;Id='c'})
    }
    It 'accepts multiple eligible numbers and deduplicates' {
        Mock Read-Host { '1,3,1' }
        $selected=@(Read-WFSelection -Rows $rows)
        $selected.Count | Should -Be 2
        @($selected.Id) | Should -Be @('a','c')
    }
    It 'rejects unavailable entries' { Mock Read-Host { '2' }; { Read-WFSelection -Rows $rows } | Should -Throw }
    It 'rejects malformed input instead of partially applying it' { Mock Read-Host { '1,invalid' }; { Read-WFSelection -Rows $rows } | Should -Throw }
    It 'skips on Enter' { Mock Read-Host { '' }; @(Read-WFSelection -Rows $rows).Count | Should -Be 0 }
    It 'ALL means only eligible entries' { Mock Read-Host { 'ALL' }; @(Read-WFSelection -Rows $rows -AllowAll).Count | Should -Be 2 }
}
Describe 'Direct versus inherited licensing' {
    It 'keeps group-only and unknown sources ineligible' {
        $user=@{assignedLicenses=@(@{skuId='a'},@{skuId='b'},@{skuId='c'});licenseAssignmentStates=@(@{skuId='a';assignedByGroup=$null},@{skuId='a';assignedByGroup='group'},@{skuId='b';assignedByGroup='group'})}
        $skus=@(@{skuId='a';skuPartNumber='a'},@{skuId='b';skuPartNumber='b'},@{skuId='c';skuPartNumber='c'})
        $rows=@(Get-WFLicenseAssignmentRows $user $skus)
        ($rows | Where-Object Id -eq 'a').Eligible | Should -BeTrue
        ($rows | Where-Object Id -eq 'a').Inherited | Should -BeTrue
        ($rows | Where-Object Id -eq 'b').Eligible | Should -BeFalse
        ($rows | Where-Object Id -eq 'c').Eligible | Should -BeFalse
    }
}
Describe 'Shared CONFIRM standard' {
    BeforeAll {
        Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    }
    It 'accepts CONFIRM for every impact and not Y' {
        Mock -ModuleName M365Toolkit.Core Write-Host {}
        Mock -ModuleName M365Toolkit.Core Write-M365Log {}
        foreach ($impact in @('Low','Medium','High')) {
            Mock -ModuleName M365Toolkit.Core Read-Host { 'confirm' }
            Confirm-M365Action -Action 'Test' -Impact $impact | Should -BeTrue
            Mock -ModuleName M365Toolkit.Core Read-Host { 'y' }
            Confirm-M365Action -Action 'Test' -Impact $impact | Should -BeFalse
        }
    }
    It 'uses amber rather than red for confirmation output' {
        Mock -ModuleName M365Toolkit.Core Read-Host { '' }
        Mock -ModuleName M365Toolkit.Core Write-M365Log {}
        Mock -ModuleName M365Toolkit.Core Write-Host {}
        $null=Confirm-M365Action -Action 'Test' -Impact High
        Should -Invoke -ModuleName M365Toolkit.Core Write-Host -Times 0 -Exactly -ParameterFilter { $ForegroundColor -eq 'Red' }
        Should -Invoke -ModuleName M365Toolkit.Core Write-Host -Times 1 -ParameterFilter { $ForegroundColor -eq 'DarkYellow' }
    }
}
Describe 'Dispatch and integration contracts' {
    It 'validates all new standalone scripts and keeps changes out of reporting bundles' {
        foreach ($rel in @('Users/Block-UserAccess','Users/Remove-UserLicenses','Exchange/Set-MailboxForwarding','Exchange/Set-MailboxAutoReply','Exchange/Set-MailboxDelegates','Exchange/ConvertTo-SharedMailbox')) {
            $path=Join-Path $root ('Scripts/'+$rel+'.ps1')
            $tokens=$null; $errors=$null
            [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
            $def=Import-PowerShellDataFile (Join-Path $root ('Scripts/'+$rel+'.task.psd1'))
            $def.AccessMode | Should -Be 'Changes'
            $def.PermissionReview | Should -Be 'Unreviewed'
            $def.Status | Should -Be 'Ready'
            $source=Get-Content -LiteralPath $path -Raw
            $source | Should -Match 'SupportsShouldProcess'
            $source | Should -Match 'ShouldProcess\('
            $source | Should -Match 'Confirm-M365Action'
            $source | Should -Match 'PassThru'
        }
    }
    It 'passes WhatIf through the child splat and stops after incomplete planning or execution' {
        $source=Get-Content (Join-Path $root 'Scripts/Users/Disable-User.ps1') -Raw
        $source | Should -Match 'WhatIf=\[bool\]\$WhatIfPreference'
        $source | Should -Match '@childArgs'
        $source | Should -Match "PlanKind -ne 'OffboardingArchive'"
        $source | Should -Match 'Archive planning cancelled or incomplete'
        $source | Should -Match 'No workflow steps executed'
        $source | Should -Match 'Earlier step stopped the workflow'
        $source | Should -Match "Status -ne 'Success'"
        $source.IndexOf('Archive planning cancelled or incomplete') | Should -BeLessThan $source.IndexOf('$output=@(&')
    }
    It 'new user uses pickers rather than interactive GUID prompts' {
        $source=Get-Content (Join-Path $root 'Scripts/Users/New-User.ps1') -Raw
        $source | Should -Match 'Select-WFLicenses'
        $source | Should -Match 'Select-WFNewUserGroups'
        $source | Should -Not -Match "Read-Host 'Optional license SKU GUIDs"
    }
}
