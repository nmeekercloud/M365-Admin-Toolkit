#Requires -Version 7.4
<#
.SYNOPSIS
View group inventory and direct members; optionally export a named report bundle.
.DESCRIPTION
Read-only Graph. No nested expansion. Summary explicitly distinguishes failed,
hidden-skipped and successful member reads. Known v1.0 limitations always noted.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$GroupIds,[string]$Search,[switch]$AllGroups,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if (($AllGroups -and ($GroupIds -or $Search)) -or ($GroupIds -and $Search)) { throw 'Choose GroupIds, Search or AllGroups, not a combination.' }
# Omitted GroupIds is valid for Search/AllGroups; explicitly empty IDs are not.
if ($PSBoundParameters.ContainsKey('GroupIds') -and (-not $GroupIds -or $GroupIds.Count -eq 0)) {
 throw 'GroupIds was supplied but contains no IDs.'
}
$normalized=@(foreach ($value in $GroupIds) {
 $g=[guid]::Empty
 if (-not [guid]::TryParse($value,[ref]$g) -or $g -eq [guid]::Empty) { throw ('Invalid GroupId: '+$value) }
 $g.ToString('D')
})
$GroupIds=@($normalized | Select-Object -Unique)
if (-not $GroupIds.Count -and -not $AllGroups -and -not $Search) {
 if ($NoInteractive) { throw 'Specify GroupIds, Search or AllGroups with NoInteractive.' }
 $Search=([string](Read-Host 'Group name/email search; ALL exports all; Enter cancels')).Trim()
 if (-not $Search) { return }
 if ($Search -ieq 'ALL') { $AllGroups=$true; $Search='' }
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
. (Join-Path $root 'Tools/Toolkit.ExportGroupMemberships.Helpers.ps1')
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'groups.export-groupmemberships'
$tenant=Assert-M365Connection -Service Graph -GraphScopes @('Group.Read.All','User.ReadBasic.All') -TaskId 'groups.export-groupmemberships' -TaskName 'Export group memberships'
if (-not $tenant.TenantId) { throw 'A verified tenant is required.' }
if ([string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Only the global Graph endpoint is supported.' }
$select='id,displayName,mail,groupTypes,mailEnabled,securityEnabled,visibility,onPremisesSyncEnabled'
if ($GroupIds.Count) {
 $groups=@(foreach ($id in $GroupIds) {
  $group=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/groups/'+$id+'?$select='+$select) -OutputType Hashtable -ErrorAction Stop
  if ($group -isnot [System.Collections.IDictionary] -or [string]$group['id'] -ine $id) { throw 'Group lookup ID mismatch.' }
  $group
 })
} else {
 $groups=@(Get-EGCollection -Uri ('https://graph.microsoft.com/v1.0/groups?$select='+$select+'&$top=999') -ExpectedPath '/v1.0/groups')
 if ($Search) {
  $groups=@($groups | Where-Object {
   ([string]$_['displayName']).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
   ([string]$_['mail']).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0
  })
 }
}
$groups=@($groups | Sort-Object { [string]$_['displayName'] },{ [string]$_['id'] })
if (-not $groups.Count) { Write-Host 'No matching Graph groups; no report files created.'; return }
Write-Host ('Selected groups: '+$groups.Count) -ForegroundColor Cyan
Write-Host 'Direct members only. Graph v1.0 may omit service principals; Exchange dynamic distribution groups are not included.' -ForegroundColor Yellow
Write-Host 'Hidden-membership groups are skipped and recorded; no extra permission is requested.' -ForegroundColor Yellow
if (-not $PSCmdlet.ShouldProcess(($groups.Count.ToString()+' selected groups'),'Read direct memberships; optional export after display')) { return }
$memberBuffer=[Collections.Generic.List[object]]::new()
$manifest=[ordered]@{RunStatus='InProgress';TenantId=$tenant.TenantId;StartedUtc=[datetime]::UtcNow.ToString('o');FinishedUtc=$null;SelectedGroupCount=$groups.Count;SuccessfulGroupReads=0;FailedGroupReads=0;HiddenGroupsSkipped=0;ReturnedMemberRows=0;Scope='Direct';Warnings=@('Graph v1.0 may omit service principals.','Not an effective-access inventory.','Nested groups are not expanded.','Exchange dynamic distribution groups are not included.','Some member properties may be inaccessible.','Hidden-membership groups are not exported.','Not a transactionally consistent tenant snapshot.');Files=@('Groups.csv','Members.csv','Run.json')}
$summary=[Collections.Generic.List[object]]::new()
try {
 foreach ($group in $groups) {
  $row=[pscustomobject]@{GroupId=[string]$group['id'];GroupName=[string]$group['displayName'];Mail=[string]$group['mail'];GroupType=(Get-EGType $group);MembershipMode=$(if ('DynamicMembership' -in @($group['groupTypes'])) {'Dynamic'} else {'Assigned'});Visibility=[string]$group['visibility'];SyncEnabled=$group['onPremisesSyncEnabled'];ReadStatus='';ReturnedMemberCount=$null;LimitedInformationCount=$null;Error='';Coverage='Graph v1.0; service principals may be omitted; direct members only'}
  if ([string]$group['visibility'] -ieq 'HiddenMembership') {
   $row.ReadStatus='HiddenSkipped'; $row.Error='Additional hidden-membership permission/role review required'; $manifest.HiddenGroupsSkipped++
  } else {
   $readOK=$false; $members=@()
   try {
    $path='/v1.0/groups/'+$group['id']+'/members'
    $members=@(Get-EGCollection -Uri ('https://graph.microsoft.com'+$path) -ExpectedPath $path)
    $readOK=$true
   } catch { $row.ReadStatus='Error'; $row.Error=$_.Exception.Message; $manifest.FailedGroupReads++ }
   if ($readOK) {
    $memberRows=@($members | ForEach-Object { ConvertTo-EGMember -Group $group -Member $_ })
    # Buffer only after a complete per-group API read; partial failed reads are not emitted.
    foreach ($memberRow in $memberRows) { $memberBuffer.Add($memberRow) }
    $row.ReadStatus='ReadSucceeded'; $row.ReturnedMemberCount=$memberRows.Count
    $row.LimitedInformationCount=@($memberRows | Where-Object Information -eq 'Limited information returned').Count
    $manifest.SuccessfulGroupReads++; $manifest.ReturnedMemberRows+=$memberRows.Count
   }
  }
  $summary.Add($row)
  Write-Progress -Activity 'Export direct group memberships' -Status ($summary.Count.ToString()+' / '+$groups.Count) -PercentComplete (100*$summary.Count/$groups.Count)
 }
 Write-Progress -Activity 'Export direct group memberships' -Completed
 $partial=($manifest.FailedGroupReads -gt 0 -or $manifest.HiddenGroupsSkipped -gt 0)
 $manifest.RunStatus=if ($partial) {'PartialCoverage'} else {'CompletedWithKnownLimitations'}
} catch {
 $manifest.RunStatus='Interrupted'
 $manifest['ScanError']=$_.Exception.Message
 Write-Warning ('Membership retrieval interrupted; collected rows remain available: '+$_.Exception.Message)
} finally { Write-Progress -Activity 'Export direct group memberships' -Completed }
$manifest.FinishedUtc=[datetime]::UtcNow.ToString('o')
Show-M365Results -InputObject $memberBuffer.ToArray() -Title 'Direct group members' -NoPaging:$NoInteractive
Show-M365Results -InputObject $summary.ToArray() -Title 'Group membership coverage' -NoPaging:$NoInteractive
[pscustomobject]$manifest | Format-List | Out-Host
Write-Host ('Run status: '+$manifest.RunStatus) -ForegroundColor Cyan
Write-Host 'A zero returned count is not proof of zero effective access. Inspect coverage and Graph v1.0 limitations.' -ForegroundColor Yellow
. (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
$columns=@{
 'Members.csv'=@('GroupId','GroupName','GroupMail','MembershipScope','ObjectType','ObjectId','DisplayName','UserPrincipalName','Mail','Information','Coverage')
 'Groups.csv'=@('GroupId','GroupName','Mail','GroupType','MembershipMode','Visibility','SyncEnabled','ReadStatus','ReturnedMemberCount','LimitedInformationCount','Error','Coverage')
}
$export=Export-ToolkitReportBundle -Tables @{'Members.csv'=$memberBuffer;'Groups.csv'=$summary} -Manifest $manifest -Columns $columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
Write-Host ('Export status: '+$export.Status)
Write-M365Log -Message ('Group membership report: '+$manifest.RunStatus+'; '+$manifest.SuccessfulGroupReads+' group reads; '+$manifest.FailedGroupReads+' failures; '+$manifest.HiddenGroupsSkipped+' hidden skipped; export='+$export.Status) -Level Info -Quiet
if ($PassThru) { [pscustomobject]@{ReportFolder=$export.ReportFolder;RunStatus=$manifest.RunStatus;Groups=$summary.ToArray();ReturnedMemberRows=$manifest.ReturnedMemberRows;Members=$memberBuffer.ToArray();ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
