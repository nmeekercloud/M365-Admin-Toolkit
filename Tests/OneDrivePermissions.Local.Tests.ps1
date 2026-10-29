#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.OneDrivePermissions.Helpers.ps1')
function Assert-ODPTest([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
Assert-ODPTest ((ConvertTo-ODPClaimUpn 'i:0#.f|membership|test.user@contoso.com') -eq 'test.user@contoso.com') 'Claim normalization failed.'
Assert-ODPTest ((Assert-ODPPersonalUrl 'https://contoso-my.sharepoint.com/personal/test_user_contoso_com/' 'contoso.sharepoint.com') -eq 'https://contoso-my.sharepoint.com/personal/test_user_contoso_com') 'Personal URL validation failed.'
foreach ($bad in @('https://other-my.sharepoint.com/personal/test','https://contoso.sharepoint.com/sites/Test','https://contoso-my.sharepoint.com/personal/test/Documents','https://contoso-my.sharepoint.com/personal/test?x=1','http://contoso-my.sharepoint.com/personal/test')) {
 $failed=$false;try {$null=Assert-ODPPersonalUrl $bad 'contoso.sharepoint.com'} catch {$failed=$true};Assert-ODPTest $failed 'Invalid/cross-tenant URL accepted.'
}
foreach ($case in @(
 @{TargetUserId='owner';OwnerUserId='owner';TargetUpn='owner@contoso.com';OperatorUpn='operator@contoso.com';AdminCount=3;TargetIsPrimary=$false},
 @{TargetUserId='target';OwnerUserId='owner';TargetUpn='target@contoso.com';OperatorUpn='target@contoso.com';AdminCount=3;TargetIsPrimary=$false},
 @{TargetUserId='target';OwnerUserId='owner';TargetUpn='target@contoso.com';OperatorUpn='operator@contoso.com';AdminCount=1;TargetIsPrimary=$false},
 @{TargetUserId='target';OwnerUserId='owner';TargetUpn='target@contoso.com';OperatorUpn='operator@contoso.com';AdminCount=3;TargetIsPrimary=$true})) {
 $failed=$false;try {Assert-ODPRemoval @case} catch {$failed=$true};Assert-ODPTest $failed 'Protected administrator removal was not blocked.'
}
Assert-ODPRemoval -TargetUserId target -OwnerUserId owner -TargetUpn 'target@contoso.com' -OperatorUpn 'operator@contoso.com' -AdminCount 3 -TargetIsPrimary $false
$safe=ConvertTo-ODPSafeCsv ([pscustomobject]@{Title='=BAD()';Id=0})
Assert-ODPTest ($safe.Title.StartsWith("'=") -and $safe.Id -eq 0) 'CSV text safety failed.'
$ctx=@{Url='https://contoso-my.sharepoint.com/personal/test';SiteId='11111111-1111-4111-8111-111111111111'}
$r=New-ODPAccessRow -Context $ctx -Principal ([pscustomobject]@{Id=7;PrincipalType='SecurityGroup';Title='Test Group';LoginName='synthetic'}) -Origin RootWebAssignment -Roles Read
Assert-ODPTest ($r.Limitations -like '*no Entra-group expansion*' -and $r.Scope -like '*root-web*') 'Scope/limitations absent.'
$claims=@{tid='11111111-1111-4111-8111-111111111111';upn='operator@contoso.com';exp=([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+600)}
$payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress))).TrimEnd('=').Replace('+','-').Replace('/','_');$jwt='header.'+$payload+'.synthetic-signature'
Assert-ODPToken $jwt $claims.tid $claims.upn
$failed=$false;try {Assert-ODPToken $jwt '22222222-2222-4222-8222-222222222222' $claims.upn} catch {$failed=$true};Assert-ODPTest $failed 'Token tenant mismatch accepted.'
$view=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Get-OneDrivePermissions.ps1'))
$manage=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Set-OneDrivePermissions.ps1'))
Assert-ODPTest (-not $view.Contains('Add-PnP') -and -not $view.Contains('Remove-PnP')) 'View task must not mutate permissions.'
Assert-ODPTest ($manage.IndexOf('Confirm-M365Action') -lt $manage.IndexOf('Add-PnPSiteCollectionAdmin')) 'Approval must precede write.'
Assert-ODPTest ($manage.IndexOf('$PSCmdlet.ShouldProcess') -lt $manage.IndexOf('Get-M365OutputPath')) 'WhatIf guard must precede backups.'
Assert-ODPTest (-not $manage.Contains('Set-PnPTenantSite') -and -not $manage.Contains('Ensure-PnPUser') -and -not $manage.Contains('Remove-PnPUser')) 'Unexpected replacement/provisioning/deletion operation.'
Write-Host 'OneDrive permissions helper tests passed. Synthetic data only; no tenant calls.' -ForegroundColor Green
