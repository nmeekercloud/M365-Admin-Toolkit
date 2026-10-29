#Requires -Version 7.4
<#
.SYNOPSIS
Copy selected direct SharePoint group memberships on explicit site collections.
.DESCRIPTION
Additive only, no permission clone, no associated Owners groups/site-admin grants.
Requires source and target already present in each site's User Information List.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$SourceUserPrincipalName,[string]$TargetUserPrincipalName,[string[]]$SiteUrls,
      [string]$Selection,[switch]$AllEligible,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($AllEligible -and $Selection) { throw 'Choose Selection or AllEligible.' }
foreach ($name in @('SourceUserPrincipalName','TargetUserPrincipalName')) {
 if (-not (Get-Variable -Name $name -ValueOnly)) {
  if ($NoInteractive) { throw ($name+' is required.') }
  Set-Variable -Name $name -Value (([string](Read-Host ($name+' (Enter cancels)'))).Trim())
  if (-not (Get-Variable -Name $name -ValueOnly)) { return }
 }
}
if (-not $SiteUrls) {
 if ($NoInteractive) { throw 'Explicit SiteUrls are required; no automatic all-sites mutation.' }
 $answer=([string](Read-Host 'Site collection URLs separated by semicolons (Enter cancels)')).Trim()
 if (-not $answer) { return }
 $SiteUrls=@($answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
. (Join-Path $root 'Tools/Toolkit.CopySharePointGroups.Helpers.ps1')
$null=Assert-M365TaskAccess -AccessMode Changes -TaskId 'sharepoint.copy-sitepermissions'
$scopes=@('Sites.Read.All','User.Read.All')
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes $scopes -TaskId 'sharepoint.copy-sitepermissions' -TaskName 'Copy selected SharePoint group memberships'
if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Verified global-cloud tenant required.' }
$source=Get-CSUser $SourceUserPrincipalName; $target=Get-CSUser $TargetUserPrincipalName
if ([string]$source['id'] -ieq [string]$target['id']) { throw 'Source and target must be different users.' }
if ([string]$target['userPrincipalName'] -ieq [string]$tenant.Account) { throw 'Changing signed-in account membership through this task is blocked.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$rootUri=[uri]$rootSite['webUrl']; $hostName=$rootUri.Host
if ($rootUri.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported SharePoint root host.' }
$urls=@($SiteUrls | ForEach-Object { ConvertTo-CSUrl -Value $_ -AllowedHost $hostName } | Sort-Object -Unique)
$core=Get-Module M365Toolkit.Core
$admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit SharePoint admin connection unavailable.' }
$raw=Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $admin -ErrorAction Stop
$token=if ($raw -is [Security.SecureString]) { ([pscredential]::new('token',$raw)).GetNetworkCredential().Password } else { [string]$raw }; $raw=$null
Assert-CSToken -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
$connections=@{}; $snapshots=@{}; $plan=@(); $siteErrors=@(); $number=0
try {
 foreach ($url in $urls) {
  try {
   $site=Get-PnPTenantSite -Identity $url -Connection $admin -ErrorAction Stop
   if (([string]$site.Url).TrimEnd('/') -ine $url -or [string]$site.Template -like 'SPSPERS*') { throw 'Only exact non-OneDrive site collections are supported.' }
   $connection=Connect-PnPOnline -Url $url -AccessToken $token -ReturnConnection -ErrorAction Stop
   $connections[$url]=$connection
   $web=Get-PnPWeb -Includes Url,AssociatedOwnerGroup -Connection $connection -ErrorAction Stop
   if (([string]$web.Url).TrimEnd('/') -ine $url) { throw 'Root-web URL mismatch.' }
   $sourceSp=Get-CSSiteUser -Upn $source['userPrincipalName'] -Connection $connection
   $targetSp=Get-CSSiteUser -Upn $target['userPrincipalName'] -Connection $connection
   $ownerId=if ($web.AssociatedOwnerGroup) { [int]$web.AssociatedOwnerGroup.Id } else { -1 }
   foreach ($group in @(Get-PnPGroup -Connection $connection -ErrorAction Stop | Sort-Object Id)) {
    $members=@(Get-PnPGroupMember -Group $group.Id -Connection $connection -ErrorAction Stop)
    if ([int]$sourceSp.Id -notin @($members | ForEach-Object { [int]$_.Id })) { continue }
    $number++
    $status='Eligible'; $reason='Missing direct SharePoint group membership'
    if ([int]$group.Id -eq $ownerId) { $status='Excluded'; $reason='Associated Owners group excluded' }
    elseif ([int]$targetSp.Id -in @($members | ForEach-Object { [int]$_.Id })) { $status='AlreadyMember'; $reason='Target already directly in this group' }
    $entry=[pscustomobject]@{Number=$number;SiteUrl=$url;GroupId=[int]$group.Id;GroupName=[string]$group.Title;SourceSiteUserId=[int]$sourceSp.Id;TargetSiteUserId=[int]$targetSp.Id;TargetLoginName=[string]$targetSp.LoginName;Status=$status;Detail=$reason}
    $plan+=,$entry
    $snapshots[($url+'|'+$group.Id)]=@($members | Select-Object Id,LoginName)
   }
  } catch { $siteErrors+=[pscustomobject]@{SiteUrl=$url;Error=$_.Exception.Message} }
 }
 Write-Host ('Source: '+$source['userPrincipalName']+' ['+$source['id']+']') -ForegroundColor Cyan
 Write-Host ('Target: '+$target['userPrincipalName']+' ['+$target['id']+']') -ForegroundColor Cyan
 $plan | Format-Table Number,SiteUrl,GroupId,GroupName,Status -AutoSize -Wrap | Out-Host
 if ($siteErrors.Count) { $siteErrors | Format-Table -Wrap | Out-Host; throw 'Site preflight failed. Both users must already exist in each site; all reads must succeed. No membership writes sent.' }
 if (-not @($plan | Where-Object Status -eq 'Eligible').Count) { Write-Host 'No eligible missing direct SharePoint group memberships.'; return }
 Write-Host 'No full permission clone. No Entra group, direct role, owner/site-admin, file/link or nested permissions copied.' -ForegroundColor Yellow
 Write-Host 'Other selected groups can still grant powerful permissions, including custom Full Control grants. Review each site/group.' -ForegroundColor Yellow
 if ($AllEligible) { $Selection='ALL' }
 if (-not $Selection) {
  if ($NoInteractive) { throw 'Specify Selection or AllEligible with NoInteractive.' }
  while ($true) {
   $Selection=([string](Read-Host 'Plan numbers separated by commas; ALL for eligible; Enter cancels')).Trim()
   if (-not $Selection) { return }
   try { $selected=@(Select-CSRows -Plan $plan -Selection $Selection); break } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
  }
 } else { $selected=@(Select-CSRows -Plan $plan -Selection $Selection) }
 if (-not $selected.Count) { return }
 # Display every resolved target before core confirmation (core prompt itself truncates long lists).
 $selected | Format-List SiteUrl,GroupId,GroupName,TargetLoginName | Out-Host
 if (-not $WhatIfPreference) {
  $targets=@($selected | ForEach-Object { $target['userPrincipalName']+' -> '+$_.SiteUrl+' | '+$_.GroupName+' ['+$_.GroupId+']' })
  if (-not (Confirm-M365Action -Action 'Add selected direct SharePoint group memberships' -Target $targets -Impact High)) { return }
  $ConfirmPreference='None'
 }
 $results=@(); $stopped=$false; $backedUp=$false
 foreach ($row in $selected) {
  $result=[pscustomobject]@{SiteUrl=$row.SiteUrl;GroupId=$row.GroupId;GroupName=$row.GroupName;Target=$target['userPrincipalName'];Result='';Detail=''}
  if ($stopped) { $result.Result='NotRun'; $result.Detail='Earlier failed/uncertain addition stopped batch'; $results+=,$result; continue }
  if (-not $PSCmdlet.ShouldProcess(($row.TargetLoginName+' -> '+$row.SiteUrl+' | '+$row.GroupName),'Add direct SharePoint group membership')) { $result.Result='Planned'; $result.Detail='No membership write requested'; $results+=,$result; continue }
  $writeStarted=$false
  try {
   $null=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes $scopes -TaskId 'sharepoint.copy-sitepermissions' -TaskName 'Verify SharePoint copy access' -NoPrompt
   Assert-CSToken -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
   $freshSource=Get-CSUser $source['id']; $freshTarget=Get-CSUser $target['id']
   if ([string]$freshSource['id'] -ine [string]$source['id'] -or [string]$freshTarget['id'] -ine [string]$target['id'] -or [string]$freshSource['userPrincipalName'] -ine [string]$source['userPrincipalName'] -or [string]$freshTarget['userPrincipalName'] -ine [string]$target['userPrincipalName']) { throw 'User identity changed; rebuild plan.' }
   $connection=$connections[$row.SiteUrl]
   $web=Get-PnPWeb -Includes Url,AssociatedOwnerGroup -Connection $connection -ErrorAction Stop
   if (([string]$web.Url).TrimEnd('/') -ine $row.SiteUrl) { throw 'Site context changed.' }
   if ($web.AssociatedOwnerGroup -and [int]$web.AssociatedOwnerGroup.Id -eq $row.GroupId) { throw 'Group is now associated Owners; excluded.' }
   $freshGroup=Get-PnPGroup -Identity $row.GroupId -Connection $connection -ErrorAction Stop
   if ([int]$freshGroup.Id -ne $row.GroupId -or [string]$freshGroup.Title -cne $row.GroupName) { throw 'Group identity/name changed; rebuild plan.' }
   $sourceSp=Get-CSSiteUser -Upn $source['userPrincipalName'] -Connection $connection
   $targetSp=Get-CSSiteUser -Upn $target['userPrincipalName'] -Connection $connection
   if ([int]$sourceSp.Id -ne $row.SourceSiteUserId -or [int]$targetSp.Id -ne $row.TargetSiteUserId -or [string]$targetSp.LoginName -ine $row.TargetLoginName) { throw 'Site-user mapping changed; rebuild plan.' }
   $members=@(Get-PnPGroupMember -Group $row.GroupId -Connection $connection -ErrorAction Stop)
   if ([int]$sourceSp.Id -notin @($members | ForEach-Object { [int]$_.Id })) { throw 'Source no longer directly in selected group.' }
   if ([int]$targetSp.Id -in @($members | ForEach-Object { [int]$_.Id })) { $result.Result='AlreadyMember'; $result.Detail='Membership appeared after preview; no add sent'; $results+=,$result; continue }
   if (-not $backedUp) {
    $backup=Get-M365OutputPath -Type Backups -FileName ('CopySharePointGroups-Before-'+[guid]::NewGuid().ToString('N')+'.json')
    @{TenantId=$tenant.TenantId;SourceId=$source['id'];TargetId=$target['id'];Selected=$selected;OriginalMembershipSnapshots=$snapshots} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $backup -Encoding utf8 -ErrorAction Stop
    Write-Host ('Backup: '+$backup); $backedUp=$true
   }
   $writeStarted=$true
   $null=Add-PnPGroupMember -LoginName $row.TargetLoginName -Group $row.GroupId -Connection $connection -ErrorAction Stop
   $verified=$false
   for ($attempt=0;$attempt -lt 4;$attempt++) {
    $after=@(Get-PnPGroupMember -Group $row.GroupId -Connection $connection -ErrorAction Stop)
    if ($row.TargetSiteUserId -in @($after | ForEach-Object { [int]$_.Id })) { $verified=$true; break }
    if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
   }
   if (-not $verified) { throw 'Add returned but direct membership not yet visible; inspect before retrying.' }
   $result.Result='Success'; $result.Detail='Direct SharePoint group membership verified'
   Write-M365Log -Message ('Verified SharePoint group addition on '+$row.SiteUrl+' group '+$row.GroupId) -Level Change
  } catch {
   $result.Result=if ($writeStarted) {'Unverified'} else {'Failed'}; $result.Detail=$_.Exception.Message; $stopped=$true
   try { Write-M365Log -Message ('SharePoint copy stopped: '+$result.Detail) -Level Error } catch { }
  }
  $results+=,$result
 }
 . (Join-Path $root 'Tools/Toolkit.CopySitePermissions.Output.ps1')
 $exportResult=Show-ToolkitCopySitePermissionsResult -Results @($results) -TenantId $tenant.TenantId -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
 Write-Host ('Result export: '+$exportResult.Status)
 if ($PassThru) { $results }
} finally { $token=$null; $connections.Clear() }
