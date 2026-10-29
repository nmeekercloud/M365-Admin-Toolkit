# Navigation discovery only. Uses read-only PnP calls; no tenant or file mutations.
function New-HNDRow {
 param([hashtable]$Values=@{})
 $row=[ordered]@{RecordType='';StartingHub='';SourceHub='';NavigationPath='';LinkTitle='';NavigationUrl='';SiteTitle='';SiteUrl='';IsHub=$false;HubDepth=0;Status='';Detail='';ReportStatus='';RetrievedUtc=''}
 foreach ($key in $Values.Keys) { $row[$key]=$Values[$key] }
 [pscustomobject]$row
}
function Add-HNDCoverage {
 param([hashtable]$Context,[string]$Hub,[string]$Status,[string]$Detail)
 if ($Status -in @('Error','Unresolved','Truncated')) { $Context.Gaps++ }
 $Context.Coverage.Add((New-HNDRow @{RecordType='Coverage';SourceHub=$Hub;Status=$Status;Detail=$Detail}))
}
function Assert-HNDToken {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.'); if ($parts.Count -ne 3) { throw 'Not JWT' }
  $payload=$parts[1].Replace('-','+').Replace('_','/')
  $payload=$payload.PadRight($payload.Length+((4-$payload.Length%4)%4),'=')
  $claims=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch { throw 'Cannot inspect the existing SharePoint token identity. Reconnect through the toolkit.' }
 if ([string]$claims['tid'] -ine $TenantId -or $Account -notin @($claims['upn'],$claims['preferred_username'],$claims['unique_name'])) { throw 'SharePoint token tenant/account mismatch.' }
 if (-not $claims['exp'] -or [long]$claims['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) { throw 'SharePoint token expired or near expiry. Reconnect through the toolkit.' }
}
function Resolve-HNDLink {
 param([string]$Href,[string]$HubUrl,[string]$RootHost,[object[]]$Inventory)
 $result=[ordered]@{Status='Unresolved';NavigationUrl='';SiteUrl='';SiteTitle='';Detail=''}
 if ([string]::IsNullOrWhiteSpace($Href) -or $Href.Trim().StartsWith('#')) { $result.Status='HeadingOrAnchor'; return [pscustomobject]$result }
 try { $u=[uri]::new([uri]($HubUrl.TrimEnd('/')+'/'),$Href.Trim()) }
 catch { $result.Detail='Invalid navigation URL.'; return [pscustomobject]$result }
 if ($u.Scheme -notin @('https','http')) { $result.Status='NonWebLink'; $result.Detail='Non-web target omitted.'; return [pscustomobject]$result }
 if ($u.UserInfo -or -not $u.IsDefaultPort) { $result.Detail='Credentials or a custom port in a navigation URL are not followed.'; return [pscustomobject]$result }
 $path=$u.AbsolutePath
 # Opaque sharing/redirect links may contain redeemable secrets and cannot be mapped safely.
 if ($path -match '^/:[a-z]:/[sgt]/' -or $path -imatch '/_layouts/15/(Doc|DocIdRedir|guestaccess|redirect)\.aspx$') {
  $result.Status='OpaqueSharingOrRedirect'; $result.NavigationUrl='[sharing/redirect URL omitted]'; $result.Detail='Target site not inferred from an opaque sharing or redirect URL.'
  return [pscustomobject]$result
 }
 if ($path -match '^/:[a-z]:/r(/.*)$') { $path=$Matches[1] }
 $result.NavigationUrl=$u.GetLeftPart([UriPartial]::Authority)+$path
 if ($u.Scheme -ne 'https') { $result.Status='UnsupportedScheme'; return [pscustomobject]$result }
 if ($u.Host -ine $RootHost) { $result.Status='OtherHostNotScanned'; $result.Detail='Other-host links are recorded but not followed or assumed to belong to this tenant.'; return [pscustomobject]$result }
 # RootFolder/id are understood only as same-host server-relative paths, never arbitrary redirects.
 foreach ($part in $u.Query.TrimStart('?').Split('&')) {
  $pair=$part.Split('=',2)
  if ($pair.Count -eq 2 -and [uri]::UnescapeDataString($pair[0]) -in @('id','RootFolder')) {
   $target=[uri]::UnescapeDataString($pair[1].Replace('+',' '))
   if ($target.StartsWith('/') -and -not $target.StartsWith('//')) { $path=$target.Split('?')[0].Split('#')[0] }
  }
 }
 $decoded=[uri]::UnescapeDataString($path).TrimEnd('/')
 foreach ($site in @($Inventory | Sort-Object @{Expression={([uri]$_.Url).AbsolutePath.Length};Descending=$true})) {
  $sitePath=[uri]::UnescapeDataString(([uri]$site.Url).AbsolutePath).TrimEnd('/')
  if ($decoded.Equals($sitePath,[StringComparison]::OrdinalIgnoreCase) -or $decoded.StartsWith($sitePath+'/',[StringComparison]::OrdinalIgnoreCase)) {
   if (-not $sitePath -and $decoded -imatch '^/(sites|teams)/') {
    $result.Detail='No matching site collection was present in the verified inventory; refusing to label an unknown managed-path site as the root site.'
    return [pscustomobject]$result
   }
   $result.Status='ResolvedSite'; $result.SiteUrl=$site.Url; $result.SiteTitle=$site.Title
   return [pscustomobject]$result
  }
 }
 $result.Detail='No containing site collection could be matched in the verified site inventory.'
 [pscustomobject]$result
}
function Read-HNDNavigationNode {
 param([object]$Node,[object]$Connection,[hashtable]$Context,[object]$Frame,[string]$ParentPath,[int]$MenuDepth=0)
 if ($Context.Stopped) { return }
 if ($MenuDepth -gt 20) { Add-HNDCoverage $Context $Frame.Url 'Truncated' 'Navigation submenu depth exceeded 20.'; return }
 if ($Context.NodeCount -ge $Context.MaxNodes) {
  $Context.Stopped=$true
  Add-HNDCoverage $Context $Frame.Url 'Truncated' 'Global navigation-node limit reached. Narrow the scan or raise MaxNavigationNodes explicitly.'
  return
 }
 $Context.NodeCount++
 try {
  $nodeId=[string](Get-HARValue $Node 'Id')
  if (-not $nodeId) { $nodeId='object:'+([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Node)) }
  if (-not $Context.NodeSeen.Add($nodeId)) { return }
  $title=[string](Get-HARValue $Node 'Title'); if (-not $title) { $title='[untitled]' }
  $trail=$ParentPath+' > '+$title
  $resolved=Resolve-HNDLink -Href ([string](Get-HARValue $Node 'Url')) -HubUrl $Frame.Url -RootHost $Context.RootHost -Inventory $Context.Inventory
  $link=New-HNDRow @{RecordType='NavigationLink';SourceHub=$Frame.Url;NavigationPath=$trail;LinkTitle=$title;NavigationUrl=$resolved.NavigationUrl;SiteTitle=$resolved.SiteTitle;SiteUrl=$resolved.SiteUrl;HubDepth=$Frame.Depth;Status=$resolved.Status;Detail=$resolved.Detail}
  if ($resolved.SiteUrl) {
   $isHub=$Context.HubMap.ContainsKey($resolved.SiteUrl)
   $link.IsHub=$isHub
   if (-not $Context.SiteMap.ContainsKey($resolved.SiteUrl)) {
    $Context.SiteMap[$resolved.SiteUrl]=New-HNDRow @{RecordType='Site';SourceHub=$Frame.Url;NavigationPath=$trail;SiteTitle=$resolved.SiteTitle;SiteUrl=$resolved.SiteUrl;IsHub=$isHub;HubDepth=$Frame.Depth;Status='DiscoveredFromNavigation'}
   }
   if ($isHub -and -not $Context.Queued.Contains($resolved.SiteUrl)) {
    if ($Frame.Depth -ge $Context.MaxDepth) { Add-HNDCoverage $Context $resolved.SiteUrl 'Truncated' 'Linked hub was discovered but its menus exceed MaxHubDepth.' }
    elseif ($Context.Queued.Count -ge $Context.MaxHubs) { Add-HNDCoverage $Context $resolved.SiteUrl 'Truncated' 'Linked hub was discovered but the MaxHubs limit prevents scanning its menus.' }
    else {
     $null=$Context.Queued.Add($resolved.SiteUrl)
     $Context.Queue.Enqueue([pscustomobject]@{Url=$resolved.SiteUrl;Depth=$Frame.Depth+1;Trail=$trail})
    }
   }
  } elseif ($resolved.Status -in @('Unresolved','OpaqueSharingOrRedirect','UnsupportedScheme')) {
   Add-HNDCoverage $Context $Frame.Url 'Unresolved' ($trail+': '+$resolved.Detail+' ['+$resolved.Status+']')
  }
  $Context.Links.Add($link)
  try {
   # Do not use -Tree: it is a display feature. Explicitly load the child collection.
   $null=Get-PnPProperty -ClientObject $Node -Property Children -Connection $Connection -ErrorAction Stop
   foreach ($child in @(Get-HARValue $Node 'Children')) {
    if ($null -ne $child) { Read-HNDNavigationNode -Node $child -Connection $Connection -Context $Context -Frame $Frame -ParentPath $trail -MenuDepth ($MenuDepth+1) }
   }
  } catch { Add-HNDCoverage $Context $Frame.Url 'Error' ('Could not read submenu children at '+$trail+': '+$_.Exception.Message) }
 } catch { Add-HNDCoverage $Context $Frame.Url 'Error' ('Could not read a navigation node: '+$_.Exception.Message) }
}
function Get-HNDNavigationReport {
 [CmdletBinding()]
 param([Parameter(Mandatory)]$SelectedHub,[Parameter(Mandatory)]$Admin,[string]$RootHost,
       [string]$Token,[string]$TenantId,[string]$Account,
       [ValidateRange(0,20)][int]$MaxHubDepth=4,[ValidateRange(1,1000)][int]$MaxHubs=100,[ValidateRange(1,100000)][int]$MaxNavigationNodes=20000)
 $start=ConvertTo-HARUrl ([string](Get-HARValue $SelectedHub 'SiteUrl')) $RootHost
 $ctx=@{RootHost=$RootHost;Inventory=@();HubMap=@{};SiteMap=@{};Queue=[Collections.Generic.Queue[object]]::new();Queued=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);NodeSeen=$null;Links=[Collections.Generic.List[object]]::new();Coverage=[Collections.Generic.List[object]]::new();Gaps=0;NodeCount=0;HubsRead=0;Stopped=$false;MaxDepth=$MaxHubDepth;MaxHubs=$MaxHubs;MaxNodes=$MaxNavigationNodes}
 $inventory=@{}; $inventoryComplete=$true; $hubCatalogComplete=$true
 try {
  Get-PnPTenantSite -Connection $Admin -Detailed -ErrorAction Stop | ForEach-Object {
   try { $url=ConvertTo-HARUrl ([string](Get-HARValue $_ 'Url')) $RootHost; $inventory[$url]=[pscustomobject]@{Url=$url;Title=[string](Get-HARValue $_ 'Title')} }
   catch { Add-HNDCoverage $ctx $start 'Unresolved' 'An inventory entry was outside the verified host or had an invalid URL; it was not queried.' }
  }
 } catch { $inventoryComplete=$false; Add-HNDCoverage $ctx $start 'Error' ('Site inventory read was incomplete: '+$_.Exception.Message) }
 try {
  Get-PnPHubSite -Connection $Admin -ErrorAction Stop | ForEach-Object {
   try {
    $url=ConvertTo-HARUrl ([string](Get-HARValue $_ 'SiteUrl')) $RootHost
    $ctx.HubMap[$url]=$_
    if (-not $inventory.ContainsKey($url)) { $inventory[$url]=[pscustomobject]@{Url=$url;Title=[string](Get-HARValue $_ 'Title')} }
   } catch { Add-HNDCoverage $ctx $start 'Unresolved' 'A registered hub was outside the verified root host; cross-host menus are not scanned.' }
  }
 } catch { $hubCatalogComplete=$false; Add-HNDCoverage $ctx $start 'Error' ('Registered hub catalog was incomplete; linked-hub recognition may be incomplete: '+$_.Exception.Message) }
 $ctx.HubMap[$start]=$SelectedHub
 if (-not $inventory.ContainsKey($start)) { $inventory[$start]=[pscustomobject]@{Url=$start;Title=[string](Get-HARValue $SelectedHub 'Title')} }
 $ctx.Inventory=@($inventory.Values)
 $title=[string](Get-HARValue $SelectedHub 'Title'); if (-not $title) { $title=$start }
 $ctx.SiteMap[$start]=New-HNDRow @{RecordType='Site';SourceHub=$start;SiteTitle=$title;SiteUrl=$start;IsHub=$true;NavigationPath=$title;Status='StartingHub'}
 $null=$ctx.Queued.Add($start); $ctx.Queue.Enqueue([pscustomobject]@{Url=$start;Depth=0;Trail=$title})
 while ($ctx.Queue.Count -gt 0 -and -not $ctx.Stopped) {
  $frame=$ctx.Queue.Dequeue(); $con=$null
  $ctx.NodeSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  try {
   Assert-HNDToken -Token $Token -TenantId $TenantId -Account $Account
   $con=Connect-PnPOnline -Url $frame.Url -AccessToken $Token -ReturnConnection -ErrorAction Stop
   $web=Get-PnPWeb -Includes Url -Connection $con -ErrorAction Stop
   if ((ConvertTo-HARUrl ([string](Get-HARValue $web 'Url')) $RootHost) -ine $frame.Url) { throw 'Connected web does not match the selected hub.' }
   # Stream roots through the visitor, preserving earlier results if a later read fails.
   Get-PnPNavigationNode -Location TopNavigationBar -Connection $con -ErrorAction Stop | ForEach-Object {
    Read-HNDNavigationNode -Node $_ -Connection $con -Context $ctx -Frame $frame -ParentPath $frame.Trail
   }
   if (-not $ctx.Stopped) {
    $ctx.HubsRead++
    Add-HNDCoverage $ctx $frame.Url 'ReadSucceeded' 'Top navigation and readable submenu children processed. No homepage web-part or global-app-bar crawl.'
   } else { Add-HNDCoverage $ctx $frame.Url 'ReadStopped' 'Navigation enumeration stopped at the declared global node limit; see truncation coverage.' }
  } catch { Add-HNDCoverage $ctx $frame.Url 'Error' ('Hub navigation was not fully readable: '+$_.Exception.Message) }
  finally { $con=$null }
 }
 if ($ctx.Stopped -and $ctx.Queue.Count) { Add-HNDCoverage $ctx $start 'Truncated' 'Some queued hub menus were not scanned because the global node limit stopped discovery.' }
 $status=if ($ctx.Gaps) {'PartialCoverage'} else {'CompletedWithinDeclaredScope'}
 $stamp=[datetime]::UtcNow.ToString('o')
 $sites=@($ctx.SiteMap.Values | Sort-Object SiteUrl)
 $links=$ctx.Links.ToArray(); $coverage=$ctx.Coverage.ToArray()
 $summary=New-HNDRow @{RecordType='RunSummary';StartingHub=$start;Status=$status;Detail=('Distinct sites including starting hub: '+$sites.Count+'; hub menus read: '+$ctx.HubsRead+'; coverage gaps: '+$ctx.Gaps)}
 $exportRows=@($summary)+$sites+@($links)+@($coverage)
 foreach ($row in $exportRows) { $row.StartingHub=$start; $row.ReportStatus=$status; $row.RetrievedUtc=$stamp }
 $metadata=[pscustomobject]@{StartingHub=$start;Status=$status;DistinctSitesIncludingStart=$sites.Count;HubMenusRead=$ctx.HubsRead;NavigationNodesProcessed=$ctx.NodeCount;CoverageGaps=$ctx.Gaps;SiteInventoryComplete=$inventoryComplete;HubCatalogComplete=$hubCatalogComplete;MaxHubDepth=$MaxHubDepth;MaxHubs=$MaxHubs;MaxNavigationNodes=$MaxNavigationNodes;RetrievedUtc=$stamp;Scope='Top menus/submenus of starting hub and linked registered same-host hubs only. Ordinary-site menus, homepage Quick Links/webparts, global app-bar navigation, cross-host crawling and effective-permission analysis are excluded. Visibility is the current admin view, not a per-user audience simulation. No access is granted.'}
 [pscustomobject]@{Metadata=$metadata;Sites=$sites;Links=$links;Coverage=$coverage;ExportRows=$exportRows}
}
function Invoke-HNDNavigationDiscovery {
 [CmdletBinding()]
 param($SelectedHub,$Admin,[string]$RootHost,$Tenant,[int]$MaxHubDepth=4,[int]$MaxHubs=100,[int]$MaxNavigationNodes=20000,
       [switch]$NoInteractive,[string]$ExportPath,[switch]$OverwriteExport,[switch]$PassThru)
 $raw=$null; $token=$null
 try {
  $raw=Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $Admin -ErrorAction Stop
  $token=if ($raw -is [Security.SecureString]) { ([pscredential]::new('token',$raw)).GetNetworkCredential().Password } else { [string]$raw }
  $raw=$null
  Assert-HNDToken -Token $token -TenantId $Tenant.TenantId -Account $Tenant.Account
  $report=Get-HNDNavigationReport -SelectedHub $SelectedHub -Admin $Admin -RootHost $RootHost -Token $token -TenantId $Tenant.TenantId -Account $Tenant.Account -MaxHubDepth $MaxHubDepth -MaxHubs $MaxHubs -MaxNavigationNodes $MaxNavigationNodes
 } finally { $token=$null; $raw=$null }
 $report.Metadata | Format-List | Out-Host
 Show-M365Results -InputObject @($report.Sites | Select-Object SiteTitle,SiteUrl,IsHub,NavigationPath) -Title 'Distinct sites discovered from hub navigation (includes starting hub)' -NoPaging:$NoInteractive
 Show-M365Results -InputObject @($report.Links | Select-Object SourceHub,NavigationPath,SiteUrl,Status,Detail) -Title 'Navigation link evidence' -NoPaging:$NoInteractive
 Show-M365Results -InputObject @($report.Coverage | Select-Object SourceHub,Status,Detail) -Title 'Navigation coverage and unresolved destinations' -NoPaging:$NoInteractive
 if ($report.Metadata.CoverageGaps) { Write-Warning 'Discovery has coverage gaps. Do not treat this as a complete inventory; review coverage before using the site list.' }
 $export=Export-M365Csv -InputObject $report.ExportRows -ReportName 'HubNavigationDiscovery' -Path $ExportPath -NoInteractive:$NoInteractive -Overwrite:$OverwriteExport -PassThru
 Write-M365Log -Message ('Hub navigation discovery: '+$report.Metadata.DistinctSitesIncludingStart+' distinct sites; '+$report.Metadata.Status+'; export='+$export.Status) -Level Info -Quiet
 if ($PassThru) { [pscustomobject]@{Metadata=$report.Metadata;Sites=$report.Sites;NavigationLinks=$report.Links;Coverage=$report.Coverage;ExportRows=$report.ExportRows;ExportStatus=$export.Status;ExportPath=$export.Path;ExportError=$export.Error} }
}
