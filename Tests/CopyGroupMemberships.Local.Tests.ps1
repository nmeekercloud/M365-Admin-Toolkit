[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
. (Join-Path $root 'Tools/Toolkit.CopyGroupMemberships.Helpers.ps1')
function Assert-CGTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function New-CGTestGroup {
 @{id='11111111-1111-4111-8111-111111111111';groupTypes=@();mailEnabled=$false;securityEnabled=$true;isAssignableToRole=$false;onPremisesSyncEnabled=$false}
}
$group=New-CGTestGroup
Assert-CGTest ([string]::IsNullOrEmpty((Get-UMGroupReason $group))) 'Static cloud security should be eligible.'
$group=New-CGTestGroup; $group.groupTypes=@('Unified'); $group.mailEnabled=$true; $group.securityEnabled=$false
Assert-CGTest ([string]::IsNullOrEmpty((Get-UMGroupReason $group))) 'Static Microsoft 365 should be eligible.'
foreach ($kind in @('Dynamic','Synced','Role','MailSecurity','MissingMetadata')) {
 $group=New-CGTestGroup
 switch ($kind) {
  'Dynamic' {$group.groupTypes=@('DynamicMembership')}
  'Synced' {$group.onPremisesSyncEnabled=$true}
  'Role' {$group.isAssignableToRole=$true}
  'MailSecurity' {$group.mailEnabled=$true}
  'MissingMetadata' {$group.Remove('mailEnabled')}
 }
 Assert-CGTest (-not [string]::IsNullOrEmpty((Get-UMGroupReason $group))) ('Must skip '+$kind)
}
$plan=@([pscustomobject]@{Number=1;Id='11111111-1111-4111-8111-111111111111';Status='Eligible'},[pscustomobject]@{Number=2;Id='22222222-2222-4222-8222-222222222222';Status='Already a direct member'})
Assert-CGTest (@(Select-CGPlanIds -Plan $plan -Selection ALL).Count -eq 1) 'ALL must exclude skipped rows.'
Assert-CGTest (@(Select-CGPlanIds -Plan $plan -Selection '1,1').Count -eq 1) 'Selection deduplication failed.'
foreach ($bad in @('2','-1','abc','999999999999999999999999')) {
 $failed=$false; try { $null=@(Select-CGPlanIds -Plan $plan -Selection $bad) } catch { $failed=$true }
 Assert-CGTest $failed ('Must reject '+$bad)
}
$safe=ConvertTo-CGCsvSafeRow ([pscustomobject]@{Group='=BAD()';Detail='plain'})
Assert-CGTest ($safe.Group.StartsWith("'=") -and $safe.Detail -eq 'plain') 'CSV safety failed.'
$script:CGCalls=0
function Invoke-UMGraph {
 param($Path)
 $script:CGCalls++
 if ($script:CGCalls -eq 1) { return @{value=@(@{id='11111111-1111-4111-8111-111111111111'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/users/33333333-3333-4333-8333-333333333333/memberOf/microsoft.graph.group?$skiptoken=next'} }
 return @{value=@(@{id='11111111-1111-4111-8111-111111111111'},@{id='22222222-2222-4222-8222-222222222222'})}
}
try {
 $ids=@(Get-CGDirectGroups -UserId '33333333-3333-4333-8333-333333333333')
 Assert-CGTest ($ids.Count -eq 2 -and $script:CGCalls -eq 2) 'Membership pagination/deduplication failed.'
} finally { Remove-Item Function:Invoke-UMGraph -ErrorAction SilentlyContinue }
$source=[IO.File]::ReadAllText((Join-Path $root 'Scripts/Groups/Copy-GroupMemberships.ps1'))
Assert-CGTest ($source.Contains("/members/`$ref")) 'Membership reference endpoint missing.'
Assert-CGTest (-not $source.Contains('-Method DELETE')) 'Copy task must not remove memberships or users.'
Assert-CGTest ($source.Contains("Result='Planned'") -and $source.Contains("Result='AlreadyMember'")) 'Result states missing.'
Write-Host 'Copy-membership local tests passed. No tenant access or writes.' -ForegroundColor Green
