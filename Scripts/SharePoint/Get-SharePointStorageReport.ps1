#Requires -Version 7.4
<#
.SYNOPSIS
Read selected/all SharePoint site storage metrics and export scoped reports.
.DESCRIPTION
Site quotas are limits, not reserved tenant storage. No quota or permission writes.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$SiteUrls,[switch]$AllSites,[ValidateRange(0,100)][decimal]$WarningPercent=80,
 [ValidateRange(0,100)][decimal]$CriticalPercent=90,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($WarningPercent -ge $CriticalPercent) { throw 'WarningPercent must be lower than CriticalPercent.' }
if ($AllSites -and $SiteUrls) { throw 'Choose SiteUrls or AllSites.' }
if (-not $AllSites -and -not $SiteUrls) {
 if ($NoInteractive) { throw 'SiteUrls or AllSites is required.' }
 $answer=([string](Read-Host 'Site collection URLs separated by semicolons; ALL for all; Enter cancels')).Trim()
 if (-not $answer) { return }
 if ($answer -ieq 'ALL') { $AllSites=$true } else { $SiteUrls=@($answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.SharePointStorage.Helpers.ps1')
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'sharepoint.get-sharepointstoragereport'
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('Sites.Read.All') -TaskId 'sharepoint.get-sharepointstoragereport' -TaskName 'Site storage report'
if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Verified global-cloud tenant required.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$rootUri=[uri]$rootSite['webUrl']; $hostName=$rootUri.Host
if ($rootUri.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported verified SharePoint root.' }
$core=Get-Module M365Toolkit.Core; $admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin -or ([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit admin connection unavailable.' }
if ($AllSites) { $targets=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop | Where-Object { [string]$_.Template -notlike 'SPSPERS*' } | ForEach-Object { [string]$_.Url } | Sort-Object -Unique) }
else { $targets=@($SiteUrls | ForEach-Object { ConvertTo-SSRUrl $_ $hostName } | Sort-Object -Unique) }
if (-not $targets.Count) { Write-Host 'No selected sites; no report created.'; return }
Write-Host ('Selected sites: '+$targets.Count+' | Warning: '+$WarningPercent+'% | Critical: '+$CriticalPercent+'%') -ForegroundColor Cyan
Write-Host 'Storage telemetry is rounded and may lag; site quota/headroom is not reserved or free tenant-pool capacity.' -ForegroundColor Yellow
if (-not $PSCmdlet.ShouldProcess(($targets.Count.ToString()+' site collections'),'Read storage metrics; optional export after display')) { return }
$manifest=[ordered]@{Status='InProgress';TenantId=$tenant.TenantId;StartedUtc=[datetime]::UtcNow.ToString('o');FinishedUtc=$null;SelectedSites=$targets.Count;WarningPercent=$WarningPercent;CriticalPercent=$CriticalPercent;ReadErrors=0;RowsWithGaps=0;Scope='Selected or enumerated same-root-host SharePoint site collections; OneDrive excluded';Notes=@('Storage is service-reported rounded binary MB; GiB=MB/1024.','Telemetry may lag; not a live disk/file crawl.','Quota/headroom describes site limit, not reserved capacity or tenant pool availability.','Summed site quotas/headroom are deliberately not represented as tenant capacity.','Missing/invalid metrics remain null, not zero.','No quota, permission or retention changes.','OneDrive, deleted-site inventory and cross-host/multi-geo scans excluded.','Not a transactionally consistent snapshot.')}
$rows=[Collections.Generic.List[object]]::new()
try {

 foreach ($url in $targets) {
  $settings=$null; $errorText=''
  try {
   $normalized=ConvertTo-SSRUrl $url $hostName
   $settings=Get-PnPTenantSite -Identity $normalized -Detailed -Connection $admin -ErrorAction Stop
   if ($null -eq $settings -or ([string]$settings.Url).TrimEnd('/') -ine $normalized -or [string]$settings.Template -like 'SPSPERS*') { throw 'Only exact non-OneDrive site collection storage is supported.' }
  } catch { $settings=$null; $errorText=$_.Exception.Message }
  $row=ConvertTo-SSRRow -Url $url -Settings $settings -WarningPercent $WarningPercent -CriticalPercent $CriticalPercent -ErrorText $errorText
  $rows.Add($row)
  if ($row.ReadStatus -eq 'Error') { $manifest.ReadErrors++ } elseif ($row.ReadStatus -ne 'ReadSucceeded') { $manifest.RowsWithGaps++ }
  Write-Progress -Activity 'Read SharePoint storage' -Status ($rows.Count.ToString()+' / '+$targets.Count) -PercentComplete (100*$rows.Count/$targets.Count)
 }
} catch {
 $manifest.Status='Interrupted'
 $manifest['ScanError']=$_.Exception.Message
 Write-Warning ('Storage retrieval interrupted; collected results remain available: '+$_.Exception.Message)
} finally { Write-Progress -Activity 'Read SharePoint storage' -Completed }
$sorted=@($rows.ToArray() | Sort-Object @{Expression={if ($null -eq $_.StorageUsageCurrentMB) { [decimal]-1 } else { [decimal]$_.StorageUsageCurrentMB }};Descending=$true},SiteUrl)
$knownUsage=@($rows.ToArray() | Where-Object { $_.ReadStatus -ne 'Error' -and $null -ne $_.StorageUsageCurrentMB })
$total=[decimal]0; foreach ($row in $knownUsage) { $total+=[decimal]$row.StorageUsageCurrentMB }
$summary=[pscustomobject]@{SelectedSites=$targets.Count;SitesWithKnownUsage=$knownUsage.Count;KnownSelectedUsageGiB=[Math]::Round($total/1024,3);AllSelectedUsageKnown=($knownUsage.Count -eq $targets.Count);ReadErrors=$manifest.ReadErrors;RowsWithGaps=$manifest.RowsWithGaps;AtWarning=@($rows.ToArray() | Where-Object UtilizationStatus -eq 'Warning').Count;AtCritical=@($rows.ToArray() | Where-Object UtilizationStatus -eq 'Critical').Count;OverSiteQuota=@($rows.ToArray() | Where-Object UtilizationStatus -eq 'OverSiteQuota').Count;Interpretation='Known usage for selected sites only; not tenant total/free capacity or sum of reserved quotas'}
if ($manifest.Status -ne 'Interrupted') { $manifest.Status=if ($manifest.ReadErrors -gt 0 -or $manifest.RowsWithGaps -gt 0) {'PartialMetricCoverage'} else {'CompletedWithinDeclaredScope'} }
$manifest.FinishedUtc=[datetime]::UtcNow.ToString('o')
Show-M365Results -InputObject $sorted -Title 'SharePoint site storage' -NoPaging:$NoInteractive
$summary | Format-List | Out-Host
[pscustomobject]$manifest | Format-List | Out-Host
Write-Host ('Status: '+$manifest.Status) -ForegroundColor Cyan
$storageColumns=@('SiteUrl','Title','Template','Owner','LockState','LastContentModifiedDate','ReadStatus','Error','StorageUsageCurrentMB','StorageQuotaMB','StorageQuotaWarningLevelMB','UsedGiB','QuotaGiB','HeadroomToSiteQuotaGiB','OverSiteQuotaGiB','UtilizationPercent','UtilizationStatus','MetricIssues','UnavailableProperties','Interpretation')
. (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
$export=Export-ToolkitReportBundle -Tables @{'SiteStorage.csv'=$sorted} -Manifest $manifest -Columns @{'SiteStorage.csv'=$storageColumns} -JsonFiles @{'Summary.json'=$summary} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
Write-M365Log -Message ('SharePoint storage read: '+$targets.Count+' selected sites; '+$manifest.ReadErrors+' errors; '+$manifest.RowsWithGaps+' rows with gaps; export='+$export.Status) -Level Info -Quiet
if ($PassThru) { [pscustomobject]@{ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Status=$manifest.Status;Summary=$summary;Sites=$sorted;Manifest=[pscustomobject]$manifest} }
