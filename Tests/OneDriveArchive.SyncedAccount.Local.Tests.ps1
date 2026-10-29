#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.OneDriveArchive.AccountGuard.ps1')
. (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
function Assert-ODASTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function New-ODASTestUser {
    @{id='22222222-2222-4222-8222-222222222222';userType='Member';userPrincipalName='test.user@contoso.com';onPremisesSyncEnabled=$true}
}
$tenant=[pscustomobject]@{TenantId='11111111-1111-4111-8111-111111111111';Account='operator@contoso.com'}
$u=New-ODASTestUser
Assert-ODArchiveMember -User $u -Tenant $tenant
$u.onPremisesSyncEnabled=$false
Assert-ODArchiveMember -User $u -Tenant $tenant
$u.onPremisesSyncEnabled=$null
Assert-ODArchiveMember -User $u -Tenant $tenant
$u.Remove('onPremisesSyncEnabled')
Assert-ODArchiveMember -User $u -Tenant $tenant
foreach ($case in @('Guest','UnknownType','Self','BadId','MissingUpn','UnverifiedTenant')) {
    $u=New-ODASTestUser;$t=$tenant
    switch ($case) {
        'Guest' {$u.userType='Guest'}
        'UnknownType' {$u.Remove('userType')}
        'Self' {$u.userPrincipalName='OPERATOR@CONTOSO.COM'}
        'BadId' {$u.id='not-a-guid'}
        'MissingUpn' {$u.userPrincipalName=''}
        'UnverifiedTenant' {$t=[pscustomobject]@{TenantId='';Account='operator@contoso.com'}}
    }
    $failed=$false;try { Assert-ODArchiveMember -User $u -Tenant $t } catch { $failed=$true }
    Assert-ODASTest $failed ('Archive guard must reject '+$case)
}
$u=New-ODASTestUser
# Blanket synchronized-user rejection removed by the shared eligibility update.
Assert-UMCloudMember -User $u -Tenant $tenant
$scriptText=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Backup-OneDrive.ps1'))
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$tokens,[ref]$parseErrors)
Assert-ODASTest (@($parseErrors).Count -eq 0) 'Patched archive must parse.'
$commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
$newGuardCalls=@($commands | Where-Object {$_.GetCommandName() -eq 'Assert-ODArchiveMember'})
$oldGuardCalls=@($commands | Where-Object {$_.GetCommandName() -eq 'Assert-UMCloudMember'})
Assert-ODASTest ($newGuardCalls.Count -eq 1 -and $oldGuardCalls.Count -eq 0) 'Archive must use ONLY its archive-specific guard.'
Assert-ODASTest ($scriptText.IndexOf('Assert-ODArchiveMember -User $user -Tenant $tenant') -lt $scriptText.IndexOf('if ($PlanOnly)')) 'Guard must apply before planning/execution split.'
foreach ($required in @('Test-WF6DApproval','Test-ODSameTenantUrl','$PSCmdlet.ShouldProcess','Get-ODFingerprint','OD-Move-SingleSourceItem','Remove-PnPSiteCollectionAdmin')) {
    Assert-ODASTest ($scriptText.Contains($required)) ('Expected existing archive safeguard/engine reference missing: '+$required)
}
Write-Host 'Archive account-eligibility regression tests passed. Synthetic users; no tenant/network calls.' -ForegroundColor Green
