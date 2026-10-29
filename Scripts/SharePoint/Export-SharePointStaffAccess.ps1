#Requires -Version 7.4
<#
.SYNOPSIS
View/export root-web assignments and site collection administrators.
.DESCRIPTION
Selected site collections or all enumerated collections on the verified root host.
No subweb/list/item/share-link scan and no Entra group expansion. Read-only report.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$SiteUrls,[switch]$AllSites,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($AllSites -and $SiteUrls) { throw 'Choose SiteUrls or AllSites, not both.' }
if (-not $SiteUrls -and -not $AllSites) {
 if ($NoInteractive) { throw 'Specify SiteUrls or AllSites.' }
 $answer=([string](Read-Host 'Site collection URLs separated by semicolons; ALL for all; Enter cancels')).Trim()
 if (-not $answer) { return }
 if ($answer -ieq 'ALL') { $AllSites=$true } else { $SiteUrls=@($answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
. (Join-Path $root 'Tools/Toolkit.SharePointSiteAccess.Helpers.ps1')
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'sharepoint.export-sharepointstaffaccess'
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('Sites.Read.All') -TaskId 'sharepoint.export-sharepointstaffaccess' -TaskName 'View / Export Site Access'
if (-not $tenant.TenantId) { throw 'A verified tenant is required.' }
if ([string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Only the global cloud is supported in this version.' }
# Read existing provider connection without replacing global PnP context.
$core=Get-Module M365Toolkit.Core
$admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin) { throw 'Toolkit SharePoint admin connection is unavailable. Reconnect through the toolkit.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$rootUri=[uri]$rootSite['webUrl']; $allowedHost=$rootUri.Host
if ($rootUri.Scheme -ne 'https' -or $allowedHost -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $allowedHost -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported verified SharePoint root host.' }
$adminUri=[uri]$admin.Url
$expectedAdmin=$allowedHost.Replace('.sharepoint.com','-admin.sharepoint.com')
if ($adminUri.Scheme -ne 'https' -or $adminUri.Host -ine $expectedAdmin) { throw 'Toolkit admin connection URL does not match the verified SharePoint root.' }
if ($AllSites) { $sites=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop) }
else {
 $urls=@($SiteUrls | ForEach-Object { ConvertTo-SAUrl -Value $_ -AllowedHost $allowedHost } | Select-Object -Unique)
 $sites=@(foreach ($url in $urls) {
  $site=Get-PnPTenantSite -Identity $url -Connection $admin -ErrorAction Stop
  if (([string]$site.Url).TrimEnd('/') -ine $url) { throw 'Resolved site collection URL differs from requested URL.' }
  $site
 })
}
$sites=@($sites | Sort-Object Url -Unique)
if (-not $sites.Count) { Write-Host 'No enumerated site collections; no report created.'; return }
Write-Host ('Site collections selected: '+$sites.Count) -ForegroundColor Cyan
Write-Host 'Scope: site collection administrators + root-web role assignments + direct SharePoint group members.' -ForegroundColor Yellow
Write-Host 'Excludes subwebs, lists, folders, items, sharing links, Entra-group expansion and effective-user access.' -ForegroundColor Yellow
if (-not $PSCmdlet.ShouldProcess(($sites.Count.ToString()+' site collections'),'Read root-web access; optional export after display')) { return }
$rawToken=Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $admin -ErrorAction Stop
$token=if ($rawToken -is [Security.SecureString]) { ([pscredential]::new('token',$rawToken)).GetNetworkCredential().Password } else { [string]$rawToken }
$rawToken=$null
Assert-SATokenClaims -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
$access=[Collections.Generic.List[object]]::new()
$summary=[Collections.Generic.List[object]]::new()
$manifest=[ordered]@{Status='InProgress';TenantId=$tenant.TenantId;StartedUtc=[datetime]::UtcNow.ToString('o');FinishedUtc=$null;SelectedSites=$sites.Count;SuccessfulSites=0;FailedSites=0;SkippedSites=0;AccessRows=0;Scope='Site collection administrators and root-web assignments; direct SharePoint group members';Exclusions=@('Subweb/list/library/folder/item permissions','Sharing links','Entra group membership expansion','Effective access calculations','OneDrive enumeration','Cross-host/multi-geo sites','Transactional snapshot guarantees')}
try {
 foreach ($site in $sites) {
  $row=[pscustomobject]@{SiteUrl=[string]$site.Url;Title=[string]$site.Title;ReadStatus='';AccessRowCount=$null;Error='';ScanScope=$manifest.Scope}
  $siteRows=[Collections.Generic.List[object]]::new(); $connection=$null; $ok=$false
  try {
   $url=ConvertTo-SAUrl -Value $site.Url -AllowedHost $allowedHost
   if ([string]$site.Template -like 'SPSPERS*') { $row.ReadStatus='Excluded'; $row.Error='OneDrive site outside scope'; $manifest.SkippedSites++ }
   else {
    Assert-SATokenClaims -Token $token -TenantId $tenant.TenantId -Account $tenant.Account
    # Token-only site connection: cannot open a new interactive site sign-in.
    $connection=Connect-PnPOnline -Url $url -AccessToken $token -ReturnConnection -ErrorAction Stop
    $web=Get-PnPWeb -Includes RoleAssignments,Title,Url -Connection $connection -ErrorAction Stop
    if (([string]$web.Url).TrimEnd('/') -ine $url) { throw 'Root-web URL mismatch.' }
    foreach ($principal in @(Get-PnPSiteCollectionAdmin -Connection $connection -ErrorAction Stop)) {
     $siteRows.Add((ConvertTo-SAPrincipalRow -SiteUrl $url -SiteTitle $web.Title -Principal $principal -Origin 'SiteCollectionAdministrator' -Roles 'Site Collection Administrator'))
    }
    foreach ($assignment in $web.RoleAssignments) {
     $null=Get-PnPProperty -ClientObject $assignment -Property Member,RoleDefinitionBindings -Connection $connection -ErrorAction Stop
     $principal=$assignment.Member
     $null=Get-PnPProperty -ClientObject $principal -Property Id,LoginName,Title,PrincipalType -Connection $connection -ErrorAction Stop
     $roles=@($assignment.RoleDefinitionBindings | ForEach-Object Name) -join '; '
     $siteRows.Add((ConvertTo-SAPrincipalRow -SiteUrl $url -SiteTitle $web.Title -Principal $principal -Origin 'RootWebAssignment' -Roles $roles))
     if ([string]$principal.PrincipalType -eq 'SharePointGroup') {
      foreach ($member in @(Get-PnPGroupMember -Identity $principal.Id -Connection $connection -ErrorAction Stop)) {
       $siteRows.Add((ConvertTo-SAPrincipalRow -SiteUrl $url -SiteTitle $web.Title -Principal $member -Origin 'SharePointGroupMember' -ViaGroup $principal.Title -Roles $roles))
      }
     }
    }
    $ok=$true
   }
  } catch { $row.ReadStatus='Error'; $row.Error=$_.Exception.Message; $manifest.FailedSites++ }
  finally { $connection=$null }
  if ($ok) {
   foreach ($entry in $siteRows) { $access.Add($entry) }
   $row.ReadStatus='ReadSucceededWithinScope'; $row.AccessRowCount=$siteRows.Count
   $manifest.SuccessfulSites++; $manifest.AccessRows+=$siteRows.Count
  }
  $summary.Add($row)
  Write-Progress -Activity 'Read scoped SharePoint site access' -Status ($summary.Count.ToString()+' / '+$sites.Count) -PercentComplete (100*$summary.Count/$sites.Count)
 }
 Write-Progress -Activity 'Read scoped SharePoint site access' -Completed
 $partial=($manifest.FailedSites -gt 0 -or $manifest.SkippedSites -gt 0)
 $manifest.Status=if ($partial) {'PartialCoverage'} else {'CompletedWithinDeclaredScope'}
} catch {
 $manifest.Status='Interrupted'
 $manifest['ScanError']=$_.Exception.Message
 Write-Warning ('Site access retrieval interrupted; completed-site rows remain available: '+$_.Exception.Message)
} finally { $token=$null; Write-Progress -Activity 'Read scoped SharePoint site access' -Completed }
$manifest.FinishedUtc=[datetime]::UtcNow.ToString('o')
Show-M365Results -InputObject $access.ToArray() -Title 'SharePoint root-web access' -NoPaging:$NoInteractive
Show-M365Results -InputObject $summary.ToArray() -Title 'SharePoint site coverage' -NoPaging:$NoInteractive
[pscustomobject]$manifest | Format-List | Out-Host
Write-Host ('Status: '+$manifest.Status) -ForegroundColor Cyan
Write-Host 'AccessRowCount counts grant paths, not unique people. Failed-site partial grant rows are excluded; inspect site coverage and manifest exclusions.' -ForegroundColor Yellow
. (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
$columns=@{
 'Access.csv'=@('SiteUrl','SiteTitle','ScanScope','Origin','ViaSharePointGroup','PrincipalId','PrincipalType','Title','LoginName','RoleNames','Expansion')
 'Sites.csv'=@('SiteUrl','Title','ReadStatus','AccessRowCount','Error','ScanScope')
}
$export=Export-ToolkitReportBundle -Tables @{'Access.csv'=$access;'Sites.csv'=$summary} -Manifest $manifest -Columns $columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
Write-M365Log -Message ('Scoped SharePoint site access report: '+$manifest.SuccessfulSites+' read; '+$manifest.FailedSites+' failed; '+$manifest.SkippedSites+' excluded; export='+$export.Status) -Level Info -Quiet
if ($PassThru) { [pscustomobject]@{ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Status=$manifest.Status;Sites=$summary.ToArray();AccessRows=$manifest.AccessRows;Access=$access.ToArray();Manifest=[pscustomobject]$manifest} }