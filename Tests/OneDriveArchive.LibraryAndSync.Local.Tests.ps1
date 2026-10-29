#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.OneDriveArchive.SourceLibrary.ps1')
. (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
function Assert-ODSLTest([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function New-ODSLTestList([string]$Id,[int]$Template,[string]$Root,[bool]$Hidden=$false,[string]$Base='DocumentLibrary') {
 [pscustomobject]@{Id=$Id;Title=('Test '+$Template);BaseType=$Base;BaseTemplate=$Template;Hidden=$Hidden;RootFolder=[pscustomobject]@{ServerRelativeUrl=$Root}}
}
$webRoot='/personal/test_user_contoso_com'
$a=New-ODSLTestList '11111111-1111-4111-8111-111111111111' 700 ($webRoot+'/Dokumente')
$b=New-ODSLTestList '22222222-2222-4222-8222-222222222222' 101 ($webRoot+'/Other')
$hidden=New-ODSLTestList '33333333-3333-4333-8333-333333333333' 101 ($webRoot+'/Hidden') $true
$outside=New-ODSLTestList '44444444-4444-4444-8444-444444444444' 101 '/sites/Other/Documents'
$c=@(Get-ODSourceLibraryCandidates -Lists @($a,$b,$hidden,$outside) -WebRoot $webRoot)
Assert-ODSLTest ($c.Count -eq 2) 'Must include 700/101 document libraries, exclude hidden and wrong-web roots.'
$chosen=Select-ODSourceLibraryCandidate $c
Assert-ODSLTest ($chosen.Id -eq [string]$a.Id) 'Localized template 700 personal library should be recognized.'
$chosen=Select-ODSourceLibraryCandidate -Candidates $c -LibraryId $b.Id
Assert-ODSLTest ($chosen.Id -eq [string]$b.Id) 'Explicit source-library ID must match exactly.'
$d=New-ODSLTestList '55555555-5555-4555-8555-555555555555' 101 ($webRoot+'/Another')
$ambiguous=@(Get-ODSourceLibraryCandidates @($b,$d) $webRoot)
Assert-ODSLTest ($null -eq (Select-ODSourceLibraryCandidate $ambiguous)) 'Ambiguity must require user selection, not arbitrary first library.'
$failed=$false;try {$null=Select-ODSourceLibraryCandidate -Candidates $c -LibraryId '66666666-6666-4666-8666-666666666666'} catch {$failed=$true}
Assert-ODSLTest $failed 'Unknown library ID must reject.'
$tenant=[pscustomobject]@{TenantId='77777777-7777-4777-8777-777777777777';Account='operator@contoso.com'}
$user=@{id='88888888-8888-4888-8888-888888888888';userType='Member';userPrincipalName='test.user@contoso.com';onPremisesSyncEnabled=$true}
Assert-UMCloudMember -User $user -Tenant $tenant
$user.onPremisesSyncEnabled=$false;Assert-UMCloudMember -User $user -Tenant $tenant
$user.userType='Guest';$failed=$false;try {Assert-UMCloudMember -User $user -Tenant $tenant} catch {$failed=$true}
Assert-ODSLTest $failed 'Guest protection must remain.'
$user.userType='Member';$user.userPrincipalName=$tenant.Account;$failed=$false;try {Assert-UMCloudMember -User $user -Tenant $tenant} catch {$failed=$true}
Assert-ODSLTest $failed 'Self-target protection must remain.'
Assert-UMCloudMember -User $user -Tenant $tenant -AllowSelf
$group=@{id='99999999-9999-4999-8999-999999999999';groupTypes=@();mailEnabled=$false;securityEnabled=$true;isAssignableToRole=$false;onPremisesSyncEnabled=$true}
Assert-ODSLTest ((Get-UMGroupReason $group) -eq 'Synchronized group') 'Synced-GROUP modification exclusion must remain.'
$archive=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Backup-OneDrive.ps1'))
Assert-ODSLTest ($archive.Contains('Resolve-ODArchiveSourceLibrary') -and -not $archive.Contains('Cannot uniquely identify the OneDrive document library.')) 'Archive must use new source resolver.'
Assert-ODSLTest ($archive.Contains('if ([string]$sourceList.RootFolder.ServerRelativeUrl -cne $SourceRoot)') -and $archive.Contains('SourceFingerprint')) 'Execution identity/inventory checks must remain.'
Write-Host 'Library/shared-eligibility helper regression tests passed. Synthetic data; no tenant calls.' -ForegroundColor Green
