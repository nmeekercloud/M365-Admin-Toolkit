#Requires -Version 7.4
<# .SYNOPSIS
View existing OneDrive site administrators and scoped root-web access.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$ExportCsv,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Noninteractive export requires both ExportDirectory and ReportName.'}
if ($NoInteractive -and $ExportCsv -and -not ($ExportDirectory -and $ReportName)) {throw 'Noninteractive ExportCsv requires ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveOutput.ps1')
if (-not $UserPrincipalName) {
 if ($NoInteractive) {throw 'UserPrincipalName is required.'}
 $UserPrincipalName=([string](Read-Host 'OneDrive owner UPN (Enter cancels)')).Trim();if (-not $UserPrincipalName) {return}
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.OneDrivePermissions.Helpers.ps1')
$tenant=Initialize-ODPTask $root 'onedrive.get-onedrivepermissions' ReadOnly
$owner=Get-ODPUser $UserPrincipalName;$ctx=$null
try {
 $ctx=Get-ODPContext $tenant $owner
 $admins=@(Get-ODPAdministrators $ctx)
 $rows=[Collections.Generic.List[object]]::new();$gaps=[Collections.Generic.List[object]]::new()
 foreach ($a in $admins) {
  $principal=[pscustomobject]@{Id=$a.SiteUserId;LoginName=$a.LoginName;Title=$a.Title;PrincipalType='User'}
  $rows.Add((New-ODPAccessRow -Context $ctx -Principal $principal -Origin SiteCollectionAdministrator -Roles $(if ($a.IsPrimaryOwner) {'Primary site administrator'} else {'Secondary site administrator'})))
 }
 try {
  $null=Get-PnPProperty -ClientObject $ctx.Web -Property RoleAssignments -Connection $ctx.Connection -ErrorAction Stop
  foreach ($assignment in $ctx.Web.RoleAssignments) {
   $null=Get-PnPProperty -ClientObject $assignment -Property Member,RoleDefinitionBindings -Connection $ctx.Connection -ErrorAction Stop
   $p=$assignment.Member
   $null=Get-PnPProperty -ClientObject $p -Property Id,Title,LoginName,PrincipalType -Connection $ctx.Connection -ErrorAction Stop
   $roles=@($assignment.RoleDefinitionBindings | ForEach-Object Name) -join '; '
   $rows.Add((New-ODPAccessRow -Context $ctx -Principal $p -Origin RootWebAssignment -Roles $roles))
   if ([string]$p.PrincipalType -eq 'SharePointGroup') {
    try {
     foreach ($member in @(Get-PnPGroupMember -Group $p.Id -Connection $ctx.Connection -ErrorAction Stop)) {$rows.Add((New-ODPAccessRow -Context $ctx -Principal $member -Origin DirectSharePointGroupMember -ViaGroup $p.Title -Roles $roles))}
    } catch {$gaps.Add([pscustomobject]@{Stage='SharePointGroupMembers';Object=[string]$p.Id;Error=$_.Exception.Message})}
   }
  }
 } catch {$gaps.Add([pscustomobject]@{Stage='RootWebAssignments';Object=$ctx.Url;Error=$_.Exception.Message})}
 $status=if ($gaps.Count) {'PartialCoverage'} else {'CompletedWithinDeclaredScope'}
 Write-Host ('Owner: '+$owner['userPrincipalName']+' | OneDrive: '+$ctx.Url) -ForegroundColor Cyan
 Write-Host 'Scope excludes files, folders, links, Entra-group expansion and effective user access. No automatic elevation.' -ForegroundColor Yellow
 $manifest=@{Task='onedrive.get-onedrivepermissions';Status=$status;TenantId=$tenant.TenantId;OwnerId=$owner['id'];SiteId=$ctx.SiteId;SiteUrl=$ctx.Url;Scope='Site administrators/root web only';Gaps=$gaps.ToArray();Limitations=@('No file/folder/link scan','No Entra-group expansion','Not effective access','No auto-provisioning/elevation')}
 $export=Invoke-OD18Output -Tables @{'Access.csv'=$rows;'Administrators.csv'=$admins;'Gaps.csv'=$gaps} -Columns @{
  'Access.csv'=@('SiteUrl','SiteId','Scope','Origin','ViaSharePointGroup','PrincipalId','PrincipalType','Title','LoginName','Roles','Limitations')
  'Administrators.csv'=@('SiteUserId','LoginName','Title','IsPrimaryOwner')
  'Gaps.csv'=@('Stage','Object','Error')
 } -Manifest $manifest -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
 $folder=$export.ReportFolder
 Write-Host ('Result export: '+$export.Status)
 if ($WhatIfPreference) {Write-Host 'WhatIf: reads performed; no export files written.'}
 Write-M365Log -Message ('Scoped OneDrive access read: '+$status+'; '+$gaps.Count+' gaps.') -Level Info -Quiet
 if ($PassThru) {[pscustomobject]@{Status=$status;SiteUrl=$ctx.Url;SiteId=$ctx.SiteId;Administrators=$admins;Access=$rows.ToArray();Gaps=$gaps.ToArray();ReportFolder=$folder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest}}
} finally {if ($ctx) {$ctx.Token=$null;$ctx.Connection=$null}}
