# Shared read-only scanner for SharePoint tasks 5/6. Definitions only.
function Get-SARValue {
 param([object]$Object,[string]$Name)
 try {
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
  $p=$Object.PSObject.Properties[$Name]; if ($null -ne $p) { return $p.Value }
 } catch { return $null }
}
function ConvertTo-SARUrl {
 param([string]$Value,[string]$HostName)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $HostName -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) { throw 'Site URL must be HTTPS on verified root host without credentials/query/fragment/custom port.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function Assert-SARToken {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.'); if ($parts.Count -ne 3) { throw 'Not JWT' }
  $payload=$parts[1].Replace('-','+').Replace('_','/'); $payload=$payload.PadRight($payload.Length+((4-$payload.Length%4)%4),'=')
  $c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch { throw 'Existing SharePoint token identity cannot be inspected. Reconnect through toolkit.' }
 if ([string]$c['tid'] -ine $TenantId -or $Account -notin @($c['upn'],$c['preferred_username'],$c['unique_name'])) { throw 'SharePoint token tenant/account mismatch.' }
 if (-not $c['exp'] -or [long]$c['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) { throw 'SharePoint token expired/near expiry. Reconnect and rebuild scan.' }
}
function ConvertTo-SARSafeCsv {
 param([object]$Row)
 $v=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $v[$p.Name]=$value
 }
 [pscustomobject]$v
}
function Initialize-SARCsv {
 param([string]$Path,[string[]]$Columns)
 throw 'Scan-time CSV initialization is disabled. Export the in-memory bundle after displaying results.'
}
function New-SARMemoryContext {
 param([string]$Mode,[ValidateRange(1,1000000)][int]$MaxRows=100000)
 $rows=@{}
 foreach ($name in @('Grants.csv','Links.csv','Coverage.csv')) { $rows[$name]=[Collections.Generic.List[object]]::new() }
 return @{Mode=$Mode;Rows=$rows;MaxRows=$MaxRows;BufferedRows=0;IdentityCache=@{};GroupCache=@{};OutputFailed=$false;Gaps=0;GrantRows=0;LinkRows=0;FilteredMemberRows=0;UnresolvedGrantRows=0}
}
function Write-SARRow {
 param([hashtable]$Context,[string]$File,[object]$Row)
 if (-not $Context.Rows.ContainsKey($File)) { throw 'Unknown report table.' }
 if ($Context.BufferedRows -ge $Context.MaxRows) {
  $Context.OutputFailed=$true
  throw 'In-memory report row limit reached. Scan stopped; collected results remain available. Narrow the scope or increase MaxBufferedRows explicitly.'
 }
 $Context.Rows[$File].Add($Row)
 $Context.BufferedRows++
}
function Write-SARCoverage {
 param([hashtable]$Context,[string]$Site,[string]$Object,[string]$Stage,[string]$Status,[string]$Detail)
 if ($Context.OutputFailed) { throw 'In-memory report row limit reached; scan stopped. Collected results remain available.' }
 if ($Status -in @('Error','Truncated','Unresolved')) { $Context.Gaps++ }
 Write-SARRow $Context 'Coverage.csv' ([pscustomobject]@{SiteUrl=$Site;Object=$Object;Stage=$Stage;Status=$Status;Detail=$Detail})
}
function Get-SARExposure {
 param([hashtable]$Context,[object]$Principal)
 $type=[string](Get-SARValue $Principal 'PrincipalType')
 $login=[string](Get-SARValue $Principal 'LoginName')
 if ((Get-SARValue $Principal 'IsShareByEmailGuestUser') -eq $true -or (Get-SARValue $Principal 'IsEmailAuthenticationGuestUser') -eq $true) { return 'SharePointGuestIndicator' }
 if ($type -match 'SharePointGroup') { return 'SharePointGroupContainer' }
 if ($type -match 'SecurityGroup|DistributionList') { return 'UnexpandedDirectoryGroup' }
 if ($login -match '^c:') { return 'BroadOrUnresolvedClaim' }
 if ($type -match 'User' -and $login -like 'i:0#.f|membership|*') {
  $upn=$login.Substring('i:0#.f|membership|'.Length)
  if (-not $Context.IdentityCache.ContainsKey($upn)) {
   try {
    $user=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($upn)+'?$select=id,userType') -OutputType Hashtable -ErrorAction Stop
    $userType=[string](Get-SARValue $user 'userType')
    $Context.IdentityCache[$upn]=switch ($userType) { 'Guest' {'DirectoryGuest'} 'Member' {'DirectoryMember'} default {'UnresolvedUser'} }
   } catch { $Context.IdentityCache[$upn]='UnresolvedUser' }
  }
  return $Context.IdentityCache[$upn]
 }
 'UnresolvedPrincipal'
}
function Write-SARGrant {
 param([hashtable]$Context,[string]$Site,[string]$Object,[string]$ObjectType,[object]$Principal,[string]$Origin,[string]$ViaGroup,[string]$Roles)
 $exposure=Get-SARExposure $Context $Principal
 if ($exposure -in @('UnresolvedUser','UnresolvedPrincipal','UnexpandedDirectoryGroup','BroadOrUnresolvedClaim')) { $Context.UnresolvedGrantRows++ }
 if ($Context.Mode -eq 'ExternalCandidates' -and $exposure -eq 'DirectoryMember') { $Context.FilteredMemberRows++; return }
 Write-SARRow $Context 'Grants.csv' ([pscustomobject]@{
  SiteUrl=$Site;Object=$Object;ObjectType=$ObjectType;Origin=$Origin;ViaSharePointGroup=$ViaGroup
  PrincipalId=[string](Get-SARValue $Principal 'Id');PrincipalType=[string](Get-SARValue $Principal 'PrincipalType')
  PrincipalTitle=[string](Get-SARValue $Principal 'Title');LoginName=[string](Get-SARValue $Principal 'LoginName')
  RoleNames=$Roles;Exposure=$exposure;Interpretation='Observed grant path; not effective access; directory groups not expanded'
 })
 $Context.GrantRows++
}
function Read-SARRoles {
 param([hashtable]$Context,[object]$Connection,[object]$Securable,[string]$Site,[string]$Object,[string]$ObjectType)
 $null=Get-PnPProperty -ClientObject $Securable -Property HasUniqueRoleAssignments -Connection $Connection -ErrorAction Stop
 if (-not $Securable.HasUniqueRoleAssignments) {
  Write-SARCoverage $Context $Site $Object 'Permissions' 'InheritedNotExpanded' 'No unique ACL read; inherited grants are not recalculated or flattened.'
  return
 }
 $null=Get-PnPProperty -ClientObject $Securable -Property RoleAssignments -Connection $Connection -ErrorAction Stop
 foreach ($assignment in $Securable.RoleAssignments) {
  $null=Get-PnPProperty -ClientObject $assignment -Property Member,RoleDefinitionBindings -Connection $Connection -ErrorAction Stop
  $principal=$assignment.Member
  $null=Get-PnPProperty -ClientObject $principal -Property Id,Title,LoginName,PrincipalType -Connection $Connection -ErrorAction Stop
  $roles=@($assignment.RoleDefinitionBindings | ForEach-Object Name) -join '; '
  Write-SARGrant -Context $Context -Site $Site -Object $Object -ObjectType $ObjectType -Principal $principal -Origin 'UniqueRoleAssignment' -Roles $roles
  if ([string]$principal.PrincipalType -eq 'SharePointGroup') {
   $key=$Site+'|'+$principal.Id
   $members=$null; $readError=''
   if ($Context.GroupCache.ContainsKey($key)) { $members=$Context.GroupCache[$key] }
   else {
    try { $members=@(Get-PnPGroupMember -Group $principal.Id -Connection $Connection -ErrorAction Stop); $Context.GroupCache[$key]=$members }
    catch { $readError=$_.Exception.Message }
   }
   if ($readError) { Write-SARCoverage $Context $Site $Object 'SharePointGroupExpansion' 'Error' $readError }
   else {
    foreach ($member in @($members)) { Write-SARGrant -Context $Context -Site $Site -Object $Object -ObjectType $ObjectType -Principal $member -Origin 'DirectSharePointGroupMember' -ViaGroup $principal.Title -Roles $roles }
   }
  }
 }
 Write-SARCoverage $Context $Site $Object 'Permissions' 'ReadSucceeded' 'Unique assignments read; direct SharePoint groups expanded where accessible; Entra groups not expanded.'
}
function ConvertTo-SARLinkRow {
 param([object]$Permission,[string]$Site,[string]$Object,[string]$ObjectType)
 $link=Get-SARValue $Permission 'Link'
 $scope=[string](Get-SARValue $link 'Scope'); $type=[string](Get-SARValue $link 'Type')
 if (-not $scope) { $scope='Unknown' }; if (-not $type) { $type='Unknown' }
 [pscustomobject]@{
  SiteUrl=$Site;Object=$Object;ObjectType=$ObjectType;PermissionId=[string](Get-SARValue $Permission 'Id')
  LinkScope=$scope;LinkType=$type;Expiration=[string](Get-SARValue $Permission 'ExpirationDateTime')
  Interpretation='Discovered link metadata only; recipients/redeemability not resolved; redeemable URL deliberately omitted'
 }
}
function Read-SARLinks {
 param([hashtable]$Context,[object]$Connection,[string]$Site,[string]$Path,[bool]$Folder)
 if ($Folder) { $permissions=@(Get-PnPFolderSharingLink -Folder $Path -Connection $Connection -ErrorAction Stop) }
 else { $permissions=@(Get-PnPFileSharingLink -Identity $Path -Connection $Connection -ErrorAction Stop) }
 foreach ($permission in $permissions) {
  $row=ConvertTo-SARLinkRow -Permission $permission -Site $Site -Object $Path -ObjectType $(if ($Folder) {'Folder'} else {'File'})
  Write-SARRow $Context 'Links.csv' $row; $Context.LinkRows++
  if ($row.LinkScope -eq 'Unknown') { Write-SARCoverage $Context $Site $Path 'LinkMetadata' 'Unresolved' 'PnP returned permission metadata without a recognized Link.Scope.' }
 }
 Write-SARCoverage $Context $Site $Path 'Links' 'ReadSucceeded' ('Returned link records: '+$permissions.Count+'; no claim that all links/recipients are visible.')
}
function Invoke-SARReport {
 [CmdletBinding(SupportsShouldProcess)]
 param([Parameter(Mandatory)][string]$TaskId,[ValidateSet('ExternalCandidates','All')][string]$Mode,
 [string[]]$SiteUrls,[switch]$AllSites,[ValidateSet('RootWeb','Lists','DocumentLibraryItems')][string]$ScanScope,
 [ValidateRange(1,100000)][int]$MaxItemsPerLibrary=1000,[ValidateRange(1,1000)][int]$MaxLibrariesPerSite=100,
 [ValidateRange(100,1000000)][int]$MaxBufferedRows=100000,
 [string]$ExportDirectory,[string]$ReportName,
 [switch]$NoInteractive,[switch]$PassThru)
 $ErrorActionPreference='Stop'
 if ($AllSites -and $SiteUrls) { throw 'Choose SiteUrls or AllSites.' }
 if (-not $SiteUrls -and -not $AllSites) {
  if ($NoInteractive) { throw 'SiteUrls or AllSites is required.' }
  $answer=([string](Read-Host 'Site collection URLs separated by semicolons; ALL for all; Enter cancels')).Trim()
  if (-not $answer) { return }
  if ($answer -ieq 'ALL') { $AllSites=$true } else { $SiteUrls=@($answer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
 }
 if (-not $ScanScope) {
  if ($NoInteractive) { throw 'Explicit ScanScope is required with NoInteractive.' }
  Write-Host '[1] Root web/site admins  [2] + non-hidden list/library ACLs  [3] + document files/folders and links'
  $choice=([string](Read-Host 'Scan scope (Enter cancels)')).Trim()
  if (-not $choice) { return }
  $scopes=@{'1'='RootWeb';'2'='Lists';'3'='DocumentLibraryItems'}
  if (-not $scopes.ContainsKey($choice)) { throw 'Invalid scan scope.' }; $ScanScope=$scopes[$choice]
 }
 $root=Split-Path -Parent $PSScriptRoot
 if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
 $null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId $TaskId
 $tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('Sites.Read.All','User.Read.All') -TaskId $TaskId -TaskName ('SharePoint access/sharing report: '+$Mode)
 if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Verified global-cloud tenant required.' }
 $rootSite=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
 $u=[uri]$rootSite['webUrl']; $hostName=$u.Host
 if ($u.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(admin|my)\.sharepoint\.com$') { throw 'Unsupported verified SharePoint root.' }
 $core=Get-Module M365Toolkit.Core; $admin=& $core { $script:M365Session.SharePoint.Connection }
 if (-not $admin -or ([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) { throw 'Verified toolkit admin connection unavailable.' }
 if ($AllSites) { $targets=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop | Where-Object { [string]$_.Template -notlike 'SPSPERS*' } | ForEach-Object { [string]$_.Url } | Sort-Object -Unique) }
 else { $targets=@($SiteUrls | ForEach-Object { ConvertTo-SARUrl $_ $hostName } | Sort-Object -Unique) }
 if (-not $targets.Count) { Write-Host 'No selected sites; no files created.'; return }
 Write-Host ('Report: '+$Mode+' | Sites: '+$targets.Count+' | Scope: '+$ScanScope) -ForegroundColor Cyan
 Write-Host ('Limits: '+$MaxItemsPerLibrary+' items per document library; '+$MaxLibrariesPerSite+' document libraries per site.') -ForegroundColor Yellow
 Write-Host 'Not an effective-access audit. No subweb scan or Entra-group expansion. External view retains uncertain candidates.' -ForegroundColor Yellow
 if (-not $PSCmdlet.ShouldProcess(($targets.Count.ToString()+' sites; '+$ScanScope),'Read access/link metadata into memory; export is optional afterward')) { return }
 $raw=Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $admin -ErrorAction Stop
 $token=if ($raw -is [Security.SecureString]) { ([pscredential]::new('token',$raw)).GetNetworkCredential().Password } else { [string]$raw }; $raw=$null
 Assert-SARToken $token $tenant.TenantId $tenant.Account
 $ctx=New-SARMemoryContext -Mode $Mode -MaxRows $MaxBufferedRows
 $manifest=[ordered]@{Status='InProgress';TaskId=$TaskId;Mode=$Mode;TenantId=$tenant.TenantId;StartedUtc=[datetime]::UtcNow.ToString('o');FinishedUtc=$null;SelectedSites=$targets.Count;Scope=$ScanScope;MaxItemsPerLibrary=$MaxItemsPerLibrary;MaxLibrariesPerSite=$MaxLibrariesPerSite;GrantRows=0;LinkRows=0;CoverageGaps=0;FilteredDirectoryMemberRows=0;UnresolvedGrantRows=0;Exclusions=@('Subwebs','Hidden/system lists','Non-document-list item permissions/links','Entra-group expansion','Effective inheritance/user-access calculations','Link recipients/redeemability','OneDrive/cross-host/multi-geo','Transactional snapshot guarantees');Notes=@('ExternalCandidates excludes only resolved directory Member grant rows; this is not employment/internal-domain classification.','All link scopes retained in both reports; specific-people recipients are not resolved.','Sharing links are metadata; redeemable URLs deliberately not exported.','Evidence can remain from partially failed objects; Coverage.csv is mandatory context.','Zero rows do not prove zero external access.','Read caps/truncation are explicitly logged.')}
 $manifest['MaxBufferedRows']=$MaxBufferedRows
 $manifest['Storage']='Memory only until export is approved'
 $scanError=$null
 try {
  foreach ($siteUrl in $targets) {
   $con=$null
   try {
    $siteUrl=ConvertTo-SARUrl $siteUrl $hostName
    Assert-SARToken $token $tenant.TenantId $tenant.Account
    $site=Get-PnPTenantSite -Identity $siteUrl -Connection $admin -ErrorAction Stop
    if (([string]$site.Url).TrimEnd('/') -ine $siteUrl -or [string]$site.Template -like 'SPSPERS*') { throw 'Only exact non-OneDrive site collections supported.' }
    $con=Connect-PnPOnline -Url $siteUrl -AccessToken $token -ReturnConnection -ErrorAction Stop
    $web=Get-PnPWeb -Includes Url,Title -Connection $con -ErrorAction Stop
    if (([string]$web.Url).TrimEnd('/') -ine $siteUrl) { throw 'Root-web URL mismatch.' }
    try {
     foreach ($principal in @(Get-PnPSiteCollectionAdmin -Connection $con -ErrorAction Stop)) { Write-SARGrant -Context $ctx -Site $siteUrl -Object $siteUrl -ObjectType RootWeb -Principal $principal -Origin SiteCollectionAdministrator -Roles 'Site Collection Administrator' }
     Write-SARCoverage $ctx $siteUrl $siteUrl 'SiteAdministrators' 'ReadSucceeded' 'Returned site collection administrator grants; no role copying.'
    } catch { Write-SARCoverage $ctx $siteUrl $siteUrl 'SiteAdministrators' 'Error' $_.Exception.Message }
    try { Read-SARRoles $ctx $con $web $siteUrl $siteUrl 'RootWeb' } catch { Write-SARCoverage $ctx $siteUrl $siteUrl 'RootPermissions' 'Error' $_.Exception.Message }
    if ($ScanScope -eq 'RootWeb') { Write-SARCoverage $ctx $siteUrl $siteUrl 'ListsItemsLinks' 'NotRequested' 'RootWeb scope: list/item/link scanning not requested.'; continue }
    $lists=@(Get-PnPList -Includes Id,Title,Hidden,BaseType,RootFolder -Connection $con -ErrorAction Stop)
    $libraryCount=0
    foreach ($list in $lists) {
     $object=[string]$list.RootFolder.ServerRelativeUrl
     if ($list.Hidden) { Write-SARCoverage $ctx $siteUrl $object 'List' 'Excluded' 'Hidden/system list outside declared scope.'; continue }
     try { Read-SARRoles $ctx $con $list $siteUrl $object 'ListOrLibrary' } catch { Write-SARCoverage $ctx $siteUrl $object 'ListPermissions' 'Error' $_.Exception.Message }
     if ($ScanScope -ne 'DocumentLibraryItems') { Write-SARCoverage $ctx $siteUrl $object 'ItemsLinks' 'NotRequested' 'Lists scope does not crawl items or links.'; continue }
     if ([string]$list.BaseType -ne 'DocumentLibrary') { Write-SARCoverage $ctx $siteUrl $object 'ItemsLinks' 'Excluded' 'Non-document-list items outside declared scope.'; continue }
     $libraryCount++
     if ($libraryCount -gt $MaxLibrariesPerSite) { Write-SARCoverage $ctx $siteUrl $object 'LibraryItems' 'Truncated' 'Document-library cap reached; ACL read above but items/links not scanned.'; continue }
     try { Read-SARLinks $ctx $con $siteUrl $object $true } catch { Write-SARCoverage $ctx $siteUrl $object 'LibraryRootLinks' 'Error' $_.Exception.Message }
     try {
      $query="<View Scope='RecursiveAll'><ViewFields><FieldRef Name='ID'/><FieldRef Name='FileRef'/><FieldRef Name='FSObjType'/></ViewFields><RowLimit Paged='TRUE'>200</RowLimit></View>"
      $items=@(Get-PnPListItem -List $list.Id -Query $query -PageSize 200 -Connection $con -ErrorAction Stop | Select-Object -First ($MaxItemsPerLibrary+1))
      if ($items.Count -gt $MaxItemsPerLibrary) { Write-SARCoverage $ctx $siteUrl $object 'LibraryItems' 'Truncated' 'Item cap reached; remaining objects not scanned.' }
      $scanned=0
      foreach ($item in @($items | Select-Object -First $MaxItemsPerLibrary)) {
       $scanned++
       $path=[string]$item.FieldValues['FileRef']; $kind=[string]$item.FieldValues['FSObjType']
       if (-not $path.StartsWith('/') -or $path.StartsWith('//') -or $kind -notin @('0','1')) { Write-SARCoverage $ctx $siteUrl ($object+' item '+$item.Id) 'Item' 'Error' 'Missing/invalid item path or file/folder type.'; continue }
       $itemType=if ($kind -eq '1') {'Folder'} else {'File'}
       try { Read-SARRoles $ctx $con $item $siteUrl $path $itemType } catch { Write-SARCoverage $ctx $siteUrl $path 'ItemPermissions' 'Error' $_.Exception.Message }
       try { Read-SARLinks $ctx $con $siteUrl $path ($kind -eq '1') } catch { Write-SARCoverage $ctx $siteUrl $path 'ItemLinks' 'Error' $_.Exception.Message }
      }
      Write-SARCoverage $ctx $siteUrl $object 'LibraryEnumeration' 'ReadSucceeded' ('Processed returned objects within cap: '+$scanned+'; see separate ACL/link errors and truncation entries.')
     } catch { Write-SARCoverage $ctx $siteUrl $object 'LibraryEnumeration' 'Error' $_.Exception.Message }
    }
   } catch { Write-SARCoverage $ctx $siteUrl $siteUrl 'SiteScan' 'Error' $_.Exception.Message }
   finally { $con=$null; $ctx.GroupCache.Clear() }
  }
 } catch {
  $scanError=$_.Exception.Message
  $manifest.Status='Interrupted'
  $manifest['ScanError']=$scanError
  $ctx.Gaps++
  # One extra diagnostic row is retained even when the buffer limit stopped the scan.
  $ctx.Rows['Coverage.csv'].Add([pscustomobject]@{SiteUrl='';Object='Scan';Stage='ScanInterrupted';Status='Error';Detail=$scanError})
  Write-Warning ('Scan interrupted; collected results are retained in memory: '+$scanError)
 } finally { $token=$null; $ctx.IdentityCache.Clear(); $ctx.GroupCache.Clear() }
 $manifest.GrantRows=$ctx.GrantRows; $manifest.LinkRows=$ctx.LinkRows; $manifest.CoverageGaps=$ctx.Gaps
 $manifest.FilteredDirectoryMemberRows=$ctx.FilteredMemberRows; $manifest.UnresolvedGrantRows=$ctx.UnresolvedGrantRows
 if (-not $scanError) { $manifest.Status=if ($ctx.Gaps -gt 0 -or $ctx.UnresolvedGrantRows -gt 0) {'PartialCoverage'} else {'CompletedWithinDeclaredScope'} }
 $manifest.FinishedUtc=[datetime]::UtcNow.ToString('o')
 Write-Host ('Status: '+$manifest.Status+' | Grant rows: '+$ctx.GrantRows+' | Link rows: '+$ctx.LinkRows) -ForegroundColor Cyan
 Write-Host 'Observed grants/links are not effective access. Zero rows do not prove no access. Review coverage and run limitations below.' -ForegroundColor Yellow
 Show-M365Results -InputObject $ctx.Rows['Grants.csv'].ToArray() -Title 'SharePoint permission grants' -NoPaging:$NoInteractive
 Show-M365Results -InputObject $ctx.Rows['Links.csv'].ToArray() -Title 'Discovered sharing links' -NoPaging:$NoInteractive
 Show-M365Results -InputObject $ctx.Rows['Coverage.csv'].ToArray() -Title 'Scan coverage, exclusions and errors' -NoPaging:$NoInteractive
 [pscustomobject]$manifest | Format-List | Out-Host
 $columns=@{
  'Grants.csv'=@('SiteUrl','Object','ObjectType','Origin','ViaSharePointGroup','PrincipalId','PrincipalType','PrincipalTitle','LoginName','RoleNames','Exposure','Interpretation')
  'Links.csv'=@('SiteUrl','Object','ObjectType','PermissionId','LinkScope','LinkType','Expiration','Interpretation')
  'Coverage.csv'=@('SiteUrl','Object','Stage','Status','Detail')
 }
 . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
 $export=Export-ToolkitReportBundle -Tables $ctx.Rows -Manifest $manifest -Columns $columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
 Write-M365Log -Message ('SharePoint '+$Mode+' scan: '+$manifest.Status+'; '+$ctx.GrantRows+' grants; '+$ctx.LinkRows+' links; export='+$export.Status) -Level Info -Quiet
 if ($PassThru) {
  [pscustomobject]@{ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Status=$manifest.Status;ScanScope=$ScanScope;
   GrantRows=$ctx.GrantRows;LinkRows=$ctx.LinkRows;CoverageGaps=$ctx.Gaps;UnresolvedGrantRows=$ctx.UnresolvedGrantRows;
   Grants=$ctx.Rows['Grants.csv'].ToArray();Links=$ctx.Rows['Links.csv'].ToArray();Coverage=$ctx.Rows['Coverage.csv'].ToArray();Manifest=[pscustomobject]$manifest}
 }
}
