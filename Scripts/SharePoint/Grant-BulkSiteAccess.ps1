#Requires -Version 7.4
<#
.SYNOPSIS
Add explicit CSV user/site/SharePoint-group membership pairs after full preflight.
.DESCRIPTION
Additive only. No site-user provisioning, invitations, direct role assignments,
site-admin grants or associated Owners group additions. Not an effective-access clone.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$CsvPath,[ValidateRange(1,10000)][int]$MaxRows=1000,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.BulkSharePointAccess.Helpers.ps1')
. (Join-Path $root 'Tools/Toolkit.BulkCsvTemplates.ps1')
$CsvPath=Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind SharePointAccess -CsvPath $CsvPath -NoInteractive:$NoInteractive
if (-not $CsvPath) { return }
$inputRows=@(Import-BSACsv -LiteralPath $CsvPath -MaxRows $MaxRows)
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
$null=Assert-M365TaskAccess -AccessMode Changes -TaskId 'sharepoint.grant-bulksiteaccess'
$scopes=@('Sites.Read.All','User.Read.All')
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes $scopes -TaskId 'sharepoint.grant-bulksiteaccess' -TaskName 'Bulk grant selected SharePoint group memberships'
if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Verified global-cloud tenant required.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$verifiedRoot=ConvertTo-BSAUrl -Value ([string]$rootSite['webUrl'])
$hostName=([uri]$verifiedRoot).Host
$core=Get-Module M365Toolkit.Core
$admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin -or ([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit SharePoint admin connection unavailable.' }
$raw=Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $admin -ErrorAction Stop
$token=if ($raw -is [Security.SecureString]) { ([pscredential]::new('token',$raw)).GetNetworkCredential().Password } else { [string]$raw }; $raw=$null
$siteCache=@{}; $userCache=@{}; $groupCache=@{}; $siteUserCache=@{}; $snapshots=@{}
$pairs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan=@()
try {
 Assert-BSAToken -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
 foreach ($inputRow in $inputRows) {
  $row=[pscustomobject]@{Record=$inputRow.Record;SiteUrl=$inputRow.SiteUrl;WebId='';SharePointGroupId=$inputRow.SharePointGroupId;GroupName='';UserPrincipalName=$inputRow.UserPrincipalName;UserId='';SiteUserId=0;LoginName='';Status='Invalid';Detail=''}
  try {
   $url=ConvertTo-BSAUrl -Value $inputRow.SiteUrl -AllowedHost $hostName
   if (-not $siteCache.ContainsKey($url)) {
    $site=Get-PnPTenantSite -Identity $url -Connection $admin -ErrorAction Stop
    if (([string]$site.Url).TrimEnd('/') -ine $url -or [string]$site.Template -like 'SPSPERS*') { throw 'Only exact non-OneDrive site collection URLs are supported.' }
    Assert-BSAToken -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
    $connection=Connect-PnPOnline -Url $url -AccessToken $token -ReturnConnection -ErrorAction Stop
    $web=Get-PnPWeb -Includes Id,Url,AssociatedOwnerGroup -Connection $connection -ErrorAction Stop
    $webId=[guid]::Empty
    if (([string]$web.Url).TrimEnd('/') -ine $url -or -not [guid]::TryParse([string]$web.Id,[ref]$webId) -or $webId -eq [guid]::Empty) { throw 'Site root-web identity mismatch.' }
    $ownerId=if ($web.AssociatedOwnerGroup) {[int]$web.AssociatedOwnerGroup.Id} else {-1}
    $siteCache[$url]=@{Connection=$connection;WebId=$webId.ToString('D');OwnerId=$ownerId}
   }
   $state=$siteCache[$url]; $connection=$state.Connection; $row.WebId=$state.WebId
   if (-not $userCache.ContainsKey($inputRow.UserPrincipalName)) { $userCache[$inputRow.UserPrincipalName]=Get-BSAUser $inputRow.UserPrincipalName }
   $user=$userCache[$inputRow.UserPrincipalName]
   if ([string]$user['userPrincipalName'] -ine $inputRow.UserPrincipalName) { throw 'CSV must use canonical UserPrincipalName, not an alias.' }
   if ([string]$user['userPrincipalName'] -ieq [string]$tenant.Account) { throw 'Changing signed-in account membership through this task is blocked.' }
   $row.UserId=[string]$user['id']; $row.UserPrincipalName=[string]$user['userPrincipalName']
   $siteUserKey=$row.WebId+'|'+$row.UserId
   if (-not $siteUserCache.ContainsKey($siteUserKey)) { $siteUserCache[$siteUserKey]=Get-BSASiteUser -Upn $row.UserPrincipalName -Connection $connection }
   $siteUser=$siteUserCache[$siteUserKey]; $row.SiteUserId=[int]$siteUser.Id; $row.LoginName=[string]$siteUser.LoginName
   $groupKey=$row.WebId+'|'+$row.SharePointGroupId
   if (-not $groupCache.ContainsKey($groupKey)) {
    $group=Get-PnPGroup -Identity $row.SharePointGroupId -Connection $connection -ErrorAction Stop
    if ([int]$group.Id -ne $row.SharePointGroupId) { throw 'Resolved SharePoint group ID mismatch.' }
    $members=@(Get-PnPGroupMember -Group $row.SharePointGroupId -Connection $connection -ErrorAction Stop)
    $groupCache[$groupKey]=@{Name=[string]$group.Title;MemberIds=@($members | ForEach-Object { [int]$_.Id })}
    $snapshots[$groupKey]=@{SiteUrl=$url;WebId=$row.WebId;GroupId=$row.SharePointGroupId;GroupName=[string]$group.Title;Members=@($members | Select-Object Id,LoginName)}
   }
   $row.GroupName=$groupCache[$groupKey].Name
   $duplicate=-not $pairs.Add(($groupKey+'|'+$row.UserId))
   $already=$row.SiteUserId -in $groupCache[$groupKey].MemberIds
   $row.Status=Get-BSARowState -GroupId $row.SharePointGroupId -OwnerGroupId $state.OwnerId -Duplicate $duplicate -AlreadyMember $already
   $row.Detail=switch ($row.Status) {
    'Eligible' {'Missing direct SharePoint group membership'}
    'OwnersExcluded' {'Associated Owners group excluded'}
    'Duplicate' {'Same resolved site/group/user pair already appears in CSV'}
    'AlreadyMember' {'Already a direct member'}
   }
  } catch { $row.Status='Invalid'; $row.Detail=$_.Exception.Message }
  $plan+=,$row
 }
 $plan | Format-Table Record,SiteUrl,SharePointGroupId,GroupName,UserPrincipalName,Status,Detail -AutoSize -Wrap | Out-Host
 if (@($plan | Where-Object Status -eq 'Invalid').Count) { throw 'Entire batch blocked by Invalid records. Fix all errors and rerun. No membership writes sent.' }
 $eligible=@($plan | Where-Object Status -eq 'Eligible')
 if (-not $eligible.Count) { Write-Host 'No eligible missing memberships.'; if ($PassThru) { $plan }; return }
 Write-Host 'Only Eligible rows will be added. Associated Owners excluded; custom groups can still grant Full Control or other powerful access.' -ForegroundColor Yellow
 Write-Host 'No direct role changes, invitations, site-admin grants, Entra membership changes or removals.' -ForegroundColor Yellow
 $eligible | Format-List Record,SiteUrl,WebId,SharePointGroupId,GroupName,UserPrincipalName,UserId,LoginName | Out-Host
 if (-not $WhatIfPreference) {
  $targets=@($eligible | ForEach-Object { $_.UserPrincipalName+' ['+$_.UserId+'] -> '+$_.SiteUrl+' | '+$_.GroupName+' ['+$_.SharePointGroupId+']' })
  if (-not (Confirm-M365Action -Action 'Add displayed eligible CSV SharePoint group memberships' -Target $targets -Impact High)) { return }
  $ConfirmPreference='None'
 }
 $results=@(); $stopped=$false; $backedUp=$false
 foreach ($row in $plan) {
  $result=[pscustomobject]@{Record=$row.Record;SiteUrl=$row.SiteUrl;WebId=$row.WebId;SharePointGroupId=$row.SharePointGroupId;GroupName=$row.GroupName;UserPrincipalName=$row.UserPrincipalName;UserId=$row.UserId;Result=$row.Status;Detail=$row.Detail}
  if ($row.Status -ne 'Eligible') { $results+=,$result; continue }
  if ($stopped) { $result.Result='NotRun'; $result.Detail='Earlier failed or uncertain addition stopped batch'; $results+=,$result; continue }
  if (-not $PSCmdlet.ShouldProcess(($row.LoginName+' -> '+$row.SiteUrl+' | '+$row.GroupName),'Add direct SharePoint group membership')) {
   $result.Result='Planned'; $result.Detail='No membership write requested'; $results+=,$result; continue
  }
  $writeStarted=$false
  try {
   $null=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes $scopes -TaskId 'sharepoint.grant-bulksiteaccess' -TaskName 'Verify bulk SharePoint access' -NoPrompt
   Assert-BSAToken -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
   $user=Get-BSAUser $row.UserId
   if ([string]$user['id'] -ine $row.UserId -or [string]$user['userPrincipalName'] -ine $row.UserPrincipalName -or [string]$user['userPrincipalName'] -ieq [string]$tenant.Account) { throw 'User identity changed or signed-in account targeted; rebuild plan.' }
   $connection=$siteCache[$row.SiteUrl].Connection
   $web=Get-PnPWeb -Includes Id,Url,AssociatedOwnerGroup -Connection $connection -ErrorAction Stop
   if (([string]$web.Url).TrimEnd('/') -ine $row.SiteUrl -or [string]$web.Id -ine $row.WebId) { throw 'Site root-web identity changed; rebuild plan.' }
   if ($web.AssociatedOwnerGroup -and [int]$web.AssociatedOwnerGroup.Id -eq $row.SharePointGroupId) { throw 'Group is now associated Owners; rebuild plan.' }
   $group=Get-PnPGroup -Identity $row.SharePointGroupId -Connection $connection -ErrorAction Stop
   if ([int]$group.Id -ne $row.SharePointGroupId -or [string]$group.Title -cne $row.GroupName) { throw 'Group identity/name changed; rebuild plan.' }
   $siteUser=Get-BSASiteUser -Upn $row.UserPrincipalName -Connection $connection
   if ([int]$siteUser.Id -ne $row.SiteUserId -or [string]$siteUser.LoginName -ine $row.LoginName) { throw 'Site-user mapping changed; rebuild plan.' }
   $before=@(Get-PnPGroupMember -Group $row.SharePointGroupId -Connection $connection -ErrorAction Stop)
   if ($row.SiteUserId -in @($before | ForEach-Object { [int]$_.Id })) { $result.Result='AlreadyMember'; $result.Detail='Membership appeared after preview; no write sent'; $results+=,$result; continue }
   if (-not $backedUp) {
    $backup=Get-M365OutputPath -Type Backups -FileName ('BulkSharePointAccess-Before-'+[guid]::NewGuid().ToString('N')+'.json')
    @{TenantId=$tenant.TenantId;Plan=$plan;OriginalGroupSnapshots=$snapshots} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $backup -Encoding utf8 -ErrorAction Stop
    Write-Host ('Backup: '+$backup); $backedUp=$true
   }
   $writeStarted=$true
   $null=Add-PnPGroupMember -LoginName $row.LoginName -Group $row.SharePointGroupId -Connection $connection -ErrorAction Stop
   $verified=$false
   for ($attempt=0;$attempt -lt 4;$attempt++) {
    $after=@(Get-PnPGroupMember -Group $row.SharePointGroupId -Connection $connection -ErrorAction Stop)
    if ($row.SiteUserId -in @($after | ForEach-Object { [int]$_.Id })) { $verified=$true; break }
    if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
   }
   if (-not $verified) { throw 'Addition returned but membership not yet visible. Inspect before rerunning.' }
   $result.Result='Success'; $result.Detail='Direct SharePoint group membership verified'
   Write-M365Log -Message ('Verified bulk SharePoint addition: user '+$row.UserId+' on '+$row.SiteUrl+' group '+$row.SharePointGroupId) -Level Change
  } catch {
   $result.Result=if ($writeStarted) {'Unverified'} else {'Failed'}; $result.Detail=$_.Exception.Message; $stopped=$true
   try { Write-M365Log -Message ('Bulk SharePoint membership stopped: '+$result.Detail) -Level Error } catch { }
  }
  $results+=,$result
 }
 . (Join-Path $root 'Tools/Toolkit.BulkSiteAccess.Output.ps1')
 $exportResult=Show-ToolkitBulkSiteAccessResult -Results @($results) -TenantId $tenant.TenantId -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
 Write-Host ('Result export: '+$exportResult.Status)
 if ($PassThru) { $results }
} finally { $token=$null; $siteCache.Clear(); $siteUserCache.Clear() }
