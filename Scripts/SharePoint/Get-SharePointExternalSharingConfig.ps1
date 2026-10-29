#Requires -Version 7.4
<#
.SYNOPSIS
Report tenant/site external-sharing CONFIGURATION, not discovered sharing.
.DESCRIPTION
Read-only admin-center calls; no site membership, permission or link crawl.
Capability ceiling compares only tenant/site SharingCapability, not all policies.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$SiteUrls,[switch]$AllSites,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($AllSites -and $SiteUrls) { throw 'Choose SiteUrls or AllSites, not both.' }
if (-not $AllSites -and -not $SiteUrls) {
 if ($NoInteractive) { throw 'Specify SiteUrls or AllSites.' }
 $answer=([string](Read-Host 'Site collection URLs separated by semicolons; ALL for all; Enter cancels')).Trim()
 if (-not $answer) { return }
 if ($answer -ieq 'ALL') { $AllSites=$true } else { $SiteUrls=@($answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.SharePointSharingConfig.Helpers.ps1')
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'sharepoint.get-sharepointexternalsharingconfig'
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('Sites.Read.All') -TaskId 'sharepoint.get-sharepointexternalsharingconfig' -TaskName 'External sharing configuration report'
if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Verified global-cloud tenant required.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$rootUri=[uri]$rootSite['webUrl']; $rootHost=$rootUri.Host
if ($rootUri.Scheme -ne 'https' -or $rootHost -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $rootHost -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported verified SharePoint root host.' }
$core=Get-Module M365Toolkit.Core
$admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin -or ([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $rootHost.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit admin connection unavailable.' }
if ($AllSites) {
 $enumerated=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop)
 $targets=@($enumerated | Where-Object { [string]$_.Template -notlike 'SPSPERS*' } | ForEach-Object { [string]$_.Url } | Sort-Object -Unique)
} else { $targets=@($SiteUrls | ForEach-Object { ConvertTo-ESCUrl -Value $_ -AllowedHost $rootHost } | Sort-Object -Unique) }
if (-not $targets.Count) { Write-Host 'No sites selected; no report created.'; return }
Write-Host ('Selected sites: '+$targets.Count) -ForegroundColor Cyan
Write-Host 'CONFIGURATION only. No proof of external users, actual sharing, links or effective access.' -ForegroundColor Yellow
if (-not $PSCmdlet.ShouldProcess(($targets.Count.ToString()+' sites and tenant settings'),'Read sharing configuration; optional export after display')) { return }
$tenantFields=@('SharingCapability','OneDriveSharingCapability','SharingDomainRestrictionMode','SharingAllowedDomainList','SharingBlockedDomainList','DefaultSharingLinkType','DefaultLinkPermission','RequireAcceptingAccountMatchInvitedAccount','PreventExternalUsersFromResharing','RequireAnonymousLinksExpireInDays')
$siteFields=@('SharingCapability','SharingDomainRestrictionMode','SharingAllowedDomainList','SharingBlockedDomainList','DefaultSharingLinkType','DefaultLinkPermission','OverrideTenantAnonymousLinkExpirationPolicy','AnonymousLinkExpirationInDays','OverrideTenantExternalUserExpirationPolicy','ExternalUserExpirationInDays')
$manifest=[ordered]@{Status='InProgress';TenantId=$tenant.TenantId;StartedUtc=[datetime]::UtcNow.ToString('o');FinishedUtc=$null;SelectedSites=$targets.Count;SiteReadErrors=0;SitesWithFieldGaps=0;TenantReadStatus='Pending';Scope='Tenant and site sharing configuration only';Warnings=@('Settings do not prove actual external sharing.','CapabilityCeilingOnly compares just the two SharingCapability values.','Domain restrictions, labels, Entra/Teams/B2B/conditional-access and other policies may restrict further.','Unavailable properties are not treated as disabled/default.','Same-root-host site collections only; OneDrive and cross-host/multi-geo sites excluded.','Not a transactionally consistent snapshot.')}
$sites=[Collections.Generic.List[object]]::new()
$tenantRow=$null
try {

 $settings=$null; $tenantError=''
 try { $settings=Get-PnPTenant -Connection $admin -ErrorAction Stop; if ($null -eq $settings) { throw 'Tenant settings response was empty.' } } catch { $tenantError=$_.Exception.Message }
 $tenantRow=New-ESCSettingsRow -Scope Tenant -Url ([string]$admin.Url) -Settings $settings -Fields $tenantFields -ErrorText $tenantError
 $manifest.TenantReadStatus=$tenantRow.ReadStatus

 foreach ($url in $targets) {
  $settings=$null; $errorText=''
  try {
   $normalized=ConvertTo-ESCUrl -Value $url -AllowedHost $rootHost
   $settings=Get-PnPTenantSite -Identity $normalized -Detailed -Connection $admin -ErrorAction Stop
   if ($null -eq $settings -or ([string]$settings.Url).TrimEnd('/') -ine $normalized -or [string]$settings.Template -like 'SPSPERS*') { throw 'Only exact non-OneDrive site collection settings are supported.' }
  } catch { $settings=$null; $errorText=$_.Exception.Message }
  $row=New-ESCSettingsRow -Scope Site -Url $url -Settings $settings -Fields $siteFields -ErrorText $errorText
  if ($row.ReadStatus -ne 'Error') { $row.CapabilityCeilingOnly=Get-ESCCapabilityCeiling -TenantValue $tenantRow.SharingCapability -SiteValue $row.SharingCapability }
  if ($row.ReadStatus -eq 'Error') { $manifest.SiteReadErrors++ } elseif ($row.ReadStatus -ne 'ReadSucceeded') { $manifest.SitesWithFieldGaps++ }
  $sites.Add($row)
  Write-Progress -Activity 'Read sharing configuration' -Status ($sites.Count.ToString()+' / '+$targets.Count) -PercentComplete (100*$sites.Count/$targets.Count)
 }
} catch {
 $manifest.Status='Interrupted'
 $manifest['ScanError']=$_.Exception.Message
 Write-Warning ('Sharing configuration retrieval interrupted; collected results remain available: '+$_.Exception.Message)
} finally { Write-Progress -Activity 'Read sharing configuration' -Completed }
if ($manifest.Status -ne 'Interrupted') {
 $partial=($manifest.SiteReadErrors -gt 0 -or $manifest.SitesWithFieldGaps -gt 0 -or $null -eq $tenantRow -or $tenantRow.ReadStatus -ne 'ReadSucceeded')
 $manifest.Status=if ($partial) {'PartialConfigurationCoverage'} else {'CompletedWithinDeclaredScope'}
}
$manifest.FinishedUtc=[datetime]::UtcNow.ToString('o')
$tenantRows=@(); if ($null -ne $tenantRow) { $tenantRows=@($tenantRow) }
$siteRows=$sites.ToArray()
Show-M365Results -InputObject $tenantRows -Title 'Tenant external-sharing configuration' -NoPaging:$NoInteractive
Show-M365Results -InputObject $siteRows -Title 'Site external-sharing configuration' -NoPaging:$NoInteractive
[pscustomobject]$manifest | Format-List | Out-Host
Write-Host ('Report status: '+$manifest.Status) -ForegroundColor Cyan
Write-Host 'Configuration is not evidence of actual external access. CapabilityCeilingOnly is not effective sharing permission. Review unavailable properties and run limitations above.' -ForegroundColor Yellow
$tenantColumns=@('Scope','Url','ReadStatus','Error','SharingCapabilityLabel','CapabilityCeilingOnly','UnavailableProperties','Interpretation')+$tenantFields
$siteColumns=@('Scope','Url','ReadStatus','Error','SharingCapabilityLabel','CapabilityCeilingOnly','UnavailableProperties','Interpretation')+$siteFields
. (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
$export=Export-ToolkitReportBundle -Tables @{'TenantSharing.csv'=$tenantRows;'SiteSharing.csv'=$siteRows} -Manifest $manifest -Columns @{'TenantSharing.csv'=$tenantColumns;'SiteSharing.csv'=$siteColumns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
Write-M365Log -Message ('Sharing configuration report: '+$targets.Count+' sites; '+$manifest.SiteReadErrors+' read errors; '+$manifest.SitesWithFieldGaps+' sites with field gaps; export='+$export.Status) -Level Info -Quiet
if ($PassThru) { [pscustomobject]@{ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Status=$manifest.Status;Tenant=$tenantRow;Sites=$siteRows;Manifest=[pscustomobject]$manifest} }
