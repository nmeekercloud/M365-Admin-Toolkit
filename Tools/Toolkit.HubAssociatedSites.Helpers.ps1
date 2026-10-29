# Read-only hub-association report helpers. No disk writes or SDK/module installation.
function Get-HARValue {
 param([object]$Object,[string]$Name)
 if ($null -eq $Object) { return $null }
 if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
 $p=$Object.PSObject.Properties[$Name]
 if ($p) { return $p.Value }
 return $null
}
function ConvertTo-HARUrl {
 param([Parameter(Mandatory)][string]$Value,[string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) {
  throw 'Use an absolute HTTPS site URL without credentials, query, fragment or custom port.'
 }
 if ($AllowedHost -and $u.Host -ine $AllowedHost) { throw 'Hub URL must use the verified tenant SharePoint root host; cross-host hub selection is not supported.' }
 return $u.AbsoluteUri.TrimEnd('/')
}
function New-HARReportRow {
 param([hashtable]$Values=@{})
 $row=[ordered]@{RecordType='AssociatedSite';HubTitle='';HubUrl='';HubId='';SiteTitle='';SiteUrl='';SiteId='';SiteHubId='';AssociationState='';DetailStatus='';DetailError='';EnumerationStatus='';ReportedSiteCount=$null;ReportStatus='';RetrievedUtc=''}
 foreach ($key in $Values.Keys) {
  if (-not $row.Contains($key)) { throw "Unknown report column: $key" }
  $row[$key]=$Values[$key]
 }
 [pscustomobject]$row
}
function Get-HARAssociatedSites {
 [CmdletBinding()]
 param([Parameter(Mandatory)]$Hub,[Parameter(Mandatory)]$Connection,[Parameter(Mandatory)][string]$RootHost)
 $hubUrl=ConvertTo-HARUrl -Value ([string](Get-HARValue $Hub 'SiteUrl')) -AllowedHost $RootHost
 $hubId=[guid]::Empty
 if (-not [guid]::TryParse([string](Get-HARValue $Hub 'ID'),[ref]$hubId) -or $hubId -eq [guid]::Empty) { throw 'Hub metadata did not include a valid hub ID.' }
 $hubTitle=[string](Get-HARValue $Hub 'Title')
 $raw=[Collections.Generic.List[object]]::new(); $rows=[Collections.Generic.List[object]]::new()
 $enumeration='Complete'; $enumerationError=''; $invalid=0; $duplicates=0; $selfEntries=0
 try {
  # Keep streamed records if enumeration subsequently throws. Never turn a failed read into zero sites.
  Get-PnPHubSiteChild -Identity $hubUrl -Connection $Connection -ErrorAction Stop | ForEach-Object { $raw.Add($_) }
 } catch { $enumeration='Incomplete'; $enumerationError=$_.Exception.Message }
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach ($entry in $raw) {
  $candidate=if ($entry -is [string] -or $entry -is [uri]) { [string]$entry } else {
   $value=Get-HARValue $entry 'Url'
   if (-not $value) { $value=Get-HARValue $entry 'SiteUrl' }
   [string]$value
  }
  try { $siteUrl=ConvertTo-HARUrl -Value $candidate }
  catch {
   $invalid++
   $rows.Add((New-HARReportRow @{RecordType='UnresolvedAssociation';SiteUrl=$candidate;AssociationState='UnrecognizedHubResult';DetailStatus='NotQueried';DetailError=$_.Exception.Message}))
   continue
  }
  if ($siteUrl -ieq $hubUrl) { $selfEntries++; continue }
  if (-not $seen.Add($siteUrl)) { $duplicates++; continue }
  $row=New-HARReportRow @{SiteUrl=$siteUrl;AssociationState='ReportedByHubLookup';DetailStatus='NotQueried'}
  $siteUri=[uri]$siteUrl
  if ($siteUri.Host -ine $RootHost) {
   # Preserve the reported URL but do not query an unverified host.
   $row.DetailStatus='CrossHostNotQueried'
   $row.DetailError='Association URL was returned by the hub query; metadata lookup is limited to the verified root host.'
  } else {
   try {
    $site=Get-PnPTenantSite -Identity $siteUrl -Detailed -Connection $Connection -ErrorAction Stop
    if ($null -eq $site -or (ConvertTo-HARUrl -Value ([string](Get-HARValue $site 'Url')) -AllowedHost $RootHost) -ine $siteUrl) { throw 'Site metadata was empty or returned a different URL.' }
    $row.SiteTitle=[string](Get-HARValue $site 'Title')
    $row.SiteId=[string](Get-HARValue $site 'SiteId')
    $siteHub=[guid]::Empty
    $rawHub=Get-HARValue $site 'HubSiteId'
    if ($null -ne $rawHub -and [guid]::TryParse([string]$rawHub,[ref]$siteHub)) {
     $row.SiteHubId=$siteHub.ToString('D')
     if ($siteHub -eq $hubId) { $row.AssociationState='ConfirmedBySiteMetadata' }
     else { $row.AssociationState='ChangedOrMismatched'; $row.DetailError='Site metadata no longer matches the selected hub; association may have changed during this non-transactional report.' }
    }
    $row.DetailStatus=if ($row.SiteTitle) {'ReadSucceeded'} else {'ReadWithMissingTitle'}
   } catch { $row.DetailStatus='LookupFailed'; $row.DetailError=$_.Exception.Message }
  }
  $rows.Add($row)
 }
 $siteRows=@($rows.ToArray() | Where-Object RecordType -eq 'AssociatedSite')
 $gaps=@($siteRows | Where-Object { $_.DetailStatus -ne 'ReadSucceeded' -or $_.AssociationState -eq 'ChangedOrMismatched' }).Count
 $status=if ($enumeration -ne 'Complete' -or $invalid) {'PartialCoverage'} elseif ($gaps) {'CompleteWithDetailGaps'} else {'CompletedWithinDeclaredScope'}
 $stamp=[datetime]::UtcNow.ToString('o')
 $summary=New-HARReportRow @{RecordType='HubSummary';HubTitle=$hubTitle;HubUrl=$hubUrl;HubId=$hubId.ToString('D');DetailStatus='Summary';DetailError=$enumerationError;EnumerationStatus=$enumeration;ReportedSiteCount=$siteRows.Count;ReportStatus=$status;RetrievedUtc=$stamp}
 foreach ($row in $rows) {
  $row.HubTitle=$hubTitle; $row.HubUrl=$hubUrl; $row.HubId=$hubId.ToString('D')
  $row.EnumerationStatus=$enumeration; $row.ReportedSiteCount=$siteRows.Count; $row.ReportStatus=$status; $row.RetrievedUtc=$stamp
 }
 $metadata=[pscustomobject]@{HubTitle=$hubTitle;HubUrl=$hubUrl;HubId=$hubId.ToString('D');Status=$status;EnumerationStatus=$enumeration;EnumerationError=$enumerationError;ReportedSiteCount=$siteRows.Count;ConfirmedBySiteMetadata=@($siteRows | Where-Object AssociationState -eq 'ConfirmedBySiteMetadata').Count;DetailGaps=$gaps;UnresolvedResults=$invalid;DuplicateUrlsRemoved=$duplicates;HubSelfEntriesRemoved=$selfEntries;RetrievedUtc=$stamp;Scope='Sites directly returned for this hub; not navigation links, recursive child-hub inventory, permissions or an effective-access audit; not a transactional snapshot'}
 $exportRows=@($summary)+@($rows.ToArray() | Sort-Object SiteUrl,RecordType)
 [pscustomobject]@{Metadata=$metadata;Sites=$siteRows;Diagnostics=@($rows.ToArray() | Where-Object RecordType -ne 'AssociatedSite');ExportRows=$exportRows}
}
