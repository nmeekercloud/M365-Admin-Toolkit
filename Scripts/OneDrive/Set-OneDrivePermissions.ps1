#Requires -Version 7.4
<# .SYNOPSIS
Explicitly add/remove ONE secondary OneDrive site collection administrator.
.DESCRIPTION
Not file/folder Read/Edit sharing. No automatic operator elevation/provisioning.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$TargetUserPrincipalName,
 [ValidateSet('AddSiteAdministrator','RemoveSiteAdministrator')][string]$Action,
 [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Noninteractive export requires both ExportDirectory and ReportName.'}

. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveOutput.ps1')
foreach ($name in @('UserPrincipalName','TargetUserPrincipalName')) {
 if (-not (Get-Variable -Name $name -ValueOnly)) {
  if ($NoInteractive) {throw ($name+' is required.')}
  Set-Variable -Name $name -Value (([string](Read-Host ($name+' (Enter cancels)'))).Trim())
  if (-not (Get-Variable -Name $name -ValueOnly)) {return}
 }
}
if (-not $Action) {
 if ($NoInteractive) {throw 'Explicit Action is required.'}
 $choice=([string](Read-Host '[1] Add SECONDARY site admin [2] Remove SECONDARY site admin (Enter cancels)')).Trim()
 if (-not $choice) {return}
 $actions=@{'1'='AddSiteAdministrator';'2'='RemoveSiteAdministrator'}
 if (-not $actions.ContainsKey($choice)) {throw 'Invalid action.'};$Action=$actions[$choice]
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.OneDrivePermissions.Helpers.ps1')
$taskId='onedrive.set-onedrivepermissions'
$tenant=Initialize-ODPTask $root $taskId Changes
$owner=Get-ODPUser $UserPrincipalName;$target=Get-ODPUser $TargetUserPrincipalName
if ([string]$target['userPrincipalName'] -ieq [string]$tenant.Account) {throw 'Changing the signed-in operator through this task is blocked.'}
$ctx=$null;$fresh=$null
try {
 $ctx=Get-ODPContext $tenant $owner
 $admins=@(Get-ODPAdministrators $ctx)
 $claim='i:0#.f|membership|'+$target['userPrincipalName']
 $matches=@($admins | Where-Object {[string]$_.LoginName -ieq $claim})
 if ($matches.Count -gt 1) {throw 'Ambiguous administrator mapping.'}
 if ($Action -eq 'RemoveSiteAdministrator') {Assert-ODPRemoval -TargetUserId $target['id'] -OwnerUserId $owner['id'] -TargetUpn $target['userPrincipalName'] -OperatorUpn $tenant.Account -AdminCount $admins.Count -TargetIsPrimary ($matches.Count -eq 1 -and $matches[0].IsPrimaryOwner)}
 $result=[pscustomobject]@{SiteUrl=$ctx.Url;SiteId=$ctx.SiteId;OwnerUPN=$owner['userPrincipalName'];TargetUPN=$target['userPrincipalName'];TargetId=$target['id'];Action=$Action;Result='';Detail='';Backup=$null}
 Write-Host 'SITE COLLECTION ADMINISTRATOR access is full administrative access to this OneDrive, not file/folder Read or Edit sharing.' -ForegroundColor Yellow
 $admins | Format-Table -AutoSize -Wrap | Out-Host
 $result | Format-List SiteUrl,SiteId,OwnerUPN,TargetUPN,TargetId,Action | Out-Host
 if ($Action -eq 'AddSiteAdministrator' -and $matches.Count -eq 1) {$result.Result='AlreadyAdministrator';$result.Detail='No write sent';Show-M365Results -InputObject @($result) -Title 'OneDrive administrator outcome' -NoPaging:$NoInteractive;if ($PassThru) {$result};return}
 if ($Action -eq 'RemoveSiteAdministrator' -and $matches.Count -eq 0) {$result.Result='AlreadyAbsent';$result.Detail='No write sent';Show-M365Results -InputObject @($result) -Title 'OneDrive administrator outcome' -NoPaging:$NoInteractive;if ($PassThru) {$result};return}
 # Require a verified existing site-user identity; no implicit user provisioning in preview.
 $siteUsers=@(Get-PnPUser -Identity $claim -Connection $ctx.Connection -ErrorAction Stop)
 if ($siteUsers.Count -ne 1 -or [string]$siteUsers[0].LoginName -ine $claim -or [int]$siteUsers[0].Id -lt 1) {throw 'Target must already exist as a canonical site user. No invitation/provisioning performed.'}
 $targetSiteId=[int]$siteUsers[0].Id
 if ($matches.Count -eq 1 -and [int]$matches[0].SiteUserId -ne $targetSiteId) {throw 'Administrator/site-user mapping mismatch.'}
 if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action $Action -Target @('OneDrive '+$ctx.Url+' [site '+$ctx.SiteId+']','Owner '+$owner['userPrincipalName']+' ['+$owner['id']+']','Target '+$target['userPrincipalName']+' ['+$target['id']+']; site-user '+$targetSiteId) -Impact High)) {return}
 if (-not $PSCmdlet.ShouldProcess(($target['userPrincipalName']+' on '+$ctx.Url),$Action)) {$result.Result='Planned';$result.Detail='No write, backup or result file';if ($PassThru) {$result};return}
 # ShouldProcess governs every side effect below; re-resolve site/profile/user before write.
 $null=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('User.Read.All','Sites.Read.All') -TaskId $taskId -TaskName 'Verify OneDrive administrator plan' -NoPrompt
 $ownerNow=Get-ODPUser $owner['id'];$targetNow=Get-ODPUser $target['id']
 if ([string]$ownerNow['id'] -ine [string]$owner['id'] -or [string]$targetNow['id'] -ine [string]$target['id'] -or [string]$ownerNow['userPrincipalName'] -ine [string]$owner['userPrincipalName'] -or [string]$targetNow['userPrincipalName'] -ine [string]$target['userPrincipalName']) {throw 'User identity changed; rebuild plan.'}
 $fresh=Get-ODPContext $tenant $ownerNow
 if ($fresh.Url -ine $ctx.Url -or $fresh.SiteId -ine $ctx.SiteId -or $fresh.WebId -ine $ctx.WebId -or $fresh.PrimaryLogin -ine $ctx.PrimaryLogin) {throw 'OneDrive identity/primary owner changed; rebuild plan.'}
 $before=@(Get-ODPAdministrators $fresh)
 $siteUserNow=@(Get-PnPUser -Identity $claim -Connection $fresh.Connection -ErrorAction Stop)
 if ($siteUserNow.Count -ne 1 -or [int]$siteUserNow[0].Id -ne $targetSiteId -or [string]$siteUserNow[0].LoginName -ine $claim) {throw 'Site-user mapping changed; rebuild plan.'}
 $present=$targetSiteId -in @($before | ForEach-Object SiteUserId)
 if ($Action -eq 'RemoveSiteAdministrator') {Assert-ODPRemoval -TargetUserId $target['id'] -OwnerUserId $owner['id'] -TargetUpn $target['userPrincipalName'] -OperatorUpn $tenant.Account -AdminCount $before.Count -TargetIsPrimary ($targetSiteId -eq $fresh.PrimarySiteUserId)}
 if (($Action -eq 'AddSiteAdministrator' -and $present) -or ($Action -eq 'RemoveSiteAdministrator' -and -not $present)) {$result.Result='StateAlreadySatisfied';$result.Detail='State changed after preview; no write sent';Show-M365Results -InputObject @($result) -Title 'OneDrive administrator outcome' -NoPaging:$NoInteractive;if ($PassThru) {$result};return}
 $backup=Get-M365OutputPath -Type Backups -FileName ('OneDriveSiteAdmin-Before-'+[guid]::NewGuid().ToString('N')+'.json')
 @{TenantId=$tenant.TenantId;SiteUrl=$fresh.Url;SiteId=$fresh.SiteId;OwnerId=$owner['id'];TargetId=$target['id'];TargetLogin=$claim;Action=$Action;Administrators=$before} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $backup -Encoding utf8 -ErrorAction Stop
 $result.Backup=$backup
 try {
  if ($Action -eq 'AddSiteAdministrator') {$null=Add-PnPSiteCollectionAdmin -Owners $claim -Connection $fresh.Connection -ErrorAction Stop}
  else {$null=Remove-PnPSiteCollectionAdmin -Owners $claim -Connection $fresh.Connection -ErrorAction Stop}
  $verified=$false
  for ($attempt=0;$attempt -lt 4;$attempt++) {
   $after=@(Get-ODPAdministrators $fresh)
   $isPresent=$targetSiteId -in @($after | ForEach-Object SiteUserId)
   $othersBefore=@($before | Where-Object SiteUserId -ne $targetSiteId | ForEach-Object LoginName)
   $othersAfter=@($after | ForEach-Object LoginName)
   $missingOthers=@($othersBefore | Where-Object {$_ -notin $othersAfter})
   if (-not $missingOthers.Count -and (($Action -eq 'AddSiteAdministrator' -and $isPresent) -or ($Action -eq 'RemoveSiteAdministrator' -and -not $isPresent))) {$verified=$true;break}
   if ($attempt -lt 3) {Start-Sleep -Seconds 2}
  }
  if (-not $verified) {throw 'Administrator change/other-admin preservation not verified. Inspect actual state before retrying.'}
  $result.Result='Success';$result.Detail='Requested administrator state observed; previous other admins still present'
 } catch {$result.Result='Unverified';$result.Detail=$_.Exception.Message+' No task-level write retry; inspect actual administrator state.'}
 $export=Invoke-OD18Output -Tables @{'Outcome.csv'=@($result)} -Columns @{'Outcome.csv'=@('SiteUrl','SiteId','OwnerUPN','TargetUPN','TargetId','Action','Result','Detail','Backup')} -Manifest @{Task='onedrive.set-onedrivepermissions';TenantId=$tenant.TenantId;Status='OutcomeSummary';Outcome=$result.Result;Scope='One secondary site administrator; not file/folder sharing';Notes='Inspect Result/Detail; export success is not mutation verification. Required pre-change backup retained.'} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
 Write-Host ('Result export: '+$export.Status)
 Write-M365Log -Message ('OneDrive site-admin change outcome: '+$result.Result+'; action '+$Action+'; target '+$target['id']) -Level Info -Quiet
 if ($PassThru) {$result}
} finally {foreach ($c in @($ctx,$fresh)) {if ($c) {$c.Token=$null;$c.Connection=$null}}}
