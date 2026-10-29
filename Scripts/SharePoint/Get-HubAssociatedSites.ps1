#Requires -Version 7.4
<#
.SYNOPSIS
Discover sites linked from a hub navigation menu and the menus of linked registered hubs.
.DESCRIPTION
Read-only tenant-admin PnP queries. Display first; CSV export is optional.
Default Navigation mode follows top menus/submenus and linked registered hubs. Associations mode retains the older direct-association report. No permission changes,
homepage web-part crawl, automatic report files, or ordinary-site menu crawl.
.PARAMETER HubUrl
Hub site URL. Omit to choose from the tenant hub list or enter a URL interactively.
.PARAMETER ExportPath
Explicit full CSV path including filename.csv. Without it, export is offered after display.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$HubUrl,[ValidateSet('Navigation','Associations')][string]$ReportMode='Navigation',
 [ValidateRange(0,20)][int]$MaxHubDepth=4,[ValidateRange(1,1000)][int]$MaxHubs=100,
 [ValidateRange(1,100000)][int]$MaxNavigationNodes=20000,
 [switch]$NoInteractive,[string]$ExportPath,[switch]$OverwriteExport,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and -not $HubUrl) { throw 'HubUrl is required with NoInteractive.' }
if (-not $PSCmdlet.ShouldProcess('SharePoint hub discovery','Read hub/site metadata; display results and optionally export CSV')) { return }
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.HubAssociatedSites.Helpers.ps1')
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
$taskId='sharepoint.hub-associated-sites'
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId $taskId
$tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('Sites.Read.All') -TaskId $taskId -TaskName 'Hub navigation/site discovery report'
if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'A verified global-cloud tenant is required.' }
$rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
$rootUri=[uri]$rootSite['webUrl']; $hostName=$rootUri.Host
if ($rootUri.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported verified SharePoint root host.' }
$core=Get-Module M365Toolkit.Core
$admin=& $core { $script:M365Session.SharePoint.Connection }
if (-not $admin -or ([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit SharePoint admin connection is unavailable.' }
if (-not $HubUrl) {
 $hubs=@(Get-PnPHubSite -Connection $admin -ErrorAction Stop | Sort-Object Title,SiteUrl)
 if (-not $hubs.Count) { Write-Host 'No registered hubs were returned for this tenant. No files saved.'; return }
 $choices=@(for ($i=0;$i -lt $hubs.Count;$i++) { [pscustomobject]@{Number=$i+1;Title=[string](Get-HARValue $hubs[$i] 'Title');HubUrl=[string](Get-HARValue $hubs[$i] 'SiteUrl')} })
 Show-M365Results -InputObject $choices -Title 'Registered SharePoint hubs'
 $answer=([string](Read-Host 'Select a hub NUMBER or enter its full URL (Enter cancels)')).Trim()
 if (-not $answer -or $answer -imatch '^(q|quit|cancel)$') { return }
 $number=0
 if ([int]::TryParse($answer,[ref]$number)) {
  if ($number -lt 1 -or $number -gt $hubs.Count) { throw 'Hub selection is out of range.' }
  $HubUrl=[string](Get-HARValue $hubs[$number-1] 'SiteUrl')
 } else { $HubUrl=$answer }
}
$HubUrl=ConvertTo-HARUrl -Value $HubUrl -AllowedHost $hostName
$matched=@(Get-PnPHubSite -Identity $HubUrl -Connection $admin -ErrorAction Stop)
if ($matched.Count -ne 1 -or (ConvertTo-HARUrl -Value ([string](Get-HARValue $matched[0] 'SiteUrl')) -AllowedHost $hostName) -ine $HubUrl) { throw 'The requested URL did not resolve to one matching registered hub.' }
if ($ReportMode -eq 'Navigation') {
 . (Join-Path $root 'Tools/Toolkit.HubNavigationDiscovery.Helpers.ps1')
 Invoke-HNDNavigationDiscovery -SelectedHub $matched[0] -Admin $admin -RootHost $hostName -Tenant $tenant -MaxHubDepth $MaxHubDepth -MaxHubs $MaxHubs -MaxNavigationNodes $MaxNavigationNodes -NoInteractive:$NoInteractive -ExportPath $ExportPath -OverwriteExport:$OverwriteExport -PassThru:$PassThru
 return
}
$report=Get-HARAssociatedSites -Hub $matched[0] -Connection $admin -RootHost $hostName
$report.Metadata | Format-List | Out-Host
if ($report.Metadata.EnumerationStatus -ne 'Complete') { Write-Warning 'Associated-site enumeration was incomplete. The returned site count is not a complete inventory; see EnumerationError.' }
if ($report.Metadata.DetailGaps -or $report.Metadata.UnresolvedResults) { Write-Warning 'Some returned entries have unresolved metadata or association changes. URLs and diagnostic rows are retained.' }
Show-M365Results -InputObject @($report.Sites) -Title 'Sites reported as directly associated with the selected hub' -NoPaging:$NoInteractive
if ($report.Diagnostics.Count) { Show-M365Results -InputObject @($report.Diagnostics) -Title 'Unresolved hub lookup results' -NoPaging:$NoInteractive }
Write-Host 'Hub itself is shown separately above. Hub association is not navigation membership or proof of user access.' -ForegroundColor Yellow
$export=Export-M365Csv -InputObject $report.ExportRows -ReportName 'HubAssociatedSites' -Path $ExportPath -NoInteractive:$NoInteractive -Overwrite:$OverwriteExport -PassThru
Write-M365Log -Message ('Hub associated sites: '+$HubUrl+'; '+$report.Metadata.ReportedSiteCount+' distinct reported sites; '+$report.Metadata.Status+'; export='+$export.Status) -Level Info -Quiet
if ($PassThru) { [pscustomobject]@{Metadata=$report.Metadata;Sites=$report.Sites;Diagnostics=$report.Diagnostics;ExportRows=$report.ExportRows;ExportStatus=$export.Status;ExportPath=$export.Path;ExportError=$export.Error} }
