# OneDrive tasks 3/4 helpers. Definitions only; dependency contains definitions only.
. (Join-Path $PSScriptRoot 'Toolkit.OneDrivePermissions.Helpers.ps1')
function Initialize-OD34Task {
 param([string]$Root,[string]$TaskId,[ValidateSet('ReadOnly','Changes')][string]$AccessMode)
 if (-not (Get-Module M365Toolkit.Core)) {Import-Module (Join-Path $Root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop}
 $null=Assert-M365TaskAccess -AccessMode $AccessMode -TaskId $TaskId
 $scopes=@('User.Read.All','Sites.Read.All');if ($AccessMode -eq 'Changes') {$scopes+='Files.ReadWrite.All'}
 $tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes $scopes -TaskId $TaskId -TaskName 'OneDrive sharing link / storage'
 if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') {throw 'Verified global-cloud tenant required.'}
 $tenant
}
function Resolve-OD34PersonalSite {
 param([object]$Tenant,[System.Collections.IDictionary]$Owner)
 $admin=Get-M365SharePointConnection -ErrorAction Stop
 $root=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
 $uri=[uri]$root['webUrl'];$hostName=$uri.Host
 if ($uri.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(my|admin)\.sharepoint\.com$') {throw 'Unsupported verified SharePoint root.'}
 if (([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) {throw 'Admin connection does not match verified tenant.'}
 $profiles=@(Get-PnPUserProfileProperty -Account $Owner['userPrincipalName'] -Connection $admin -ErrorAction Stop)
 if ($profiles.Count -ne 1 -or (ConvertTo-ODPClaimUpn ([string](Get-ODPValue $profiles[0] 'AccountName'))) -ine [string]$Owner['userPrincipalName']) {throw 'Profile identity could not be matched to selected OneDrive owner.'}
 $url=[string](Get-ODPValue $profiles[0] 'PersonalUrl')
 if (-not $url) {$url=[string](Get-ODPValue (Get-ODPValue $profiles[0] 'UserProfileProperties') 'PersonalUrl')}
 if (-not $url) {throw 'No existing OneDrive PersonalUrl returned. No OneDrive was provisioned.'}
 $url=Assert-ODPPersonalUrl $url $hostName
 $site=Get-PnPTenantSite -Identity $url -Detailed -Connection $admin -ErrorAction Stop
 if (([string]$site.Url).TrimEnd('/') -ine $url -or [string]$site.Template -notlike 'SPSPERS*') {throw 'Expected an existing personal site, not a team site/subweb.'}
 @{Url=$url;Details=$site}
}
function Get-OD34Drive {
 param([hashtable]$PersonalSite)
 $u=[uri]$PersonalSite.Url
 $graphSite=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/sites/'+$u.Host+':'+$u.AbsolutePath+'?$select=id,webUrl') -OutputType Hashtable -ErrorAction Stop
 if (([string]$graphSite['webUrl']).TrimEnd('/') -ine $PersonalSite.Url -or -not $graphSite['id']) {throw 'Graph site identity does not match verified personal site.'}
 $siteId=[uri]::EscapeDataString([string]$graphSite['id'])
 # Read default drive of an ALREADY verified existing site; never /users/{id}/drive.
 $drive=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/sites/'+$siteId+'/drive?$select=id,webUrl,driveType') -OutputType Hashtable -ErrorAction Stop
 $driveUri=$null
 if (-not $drive['id'] -or -not [uri]::TryCreate([string]$drive['webUrl'],[UriKind]::Absolute,[ref]$driveUri) -or $driveUri.Scheme -ne 'https' -or $driveUri.Host -ine $u.Host -or -not ([string]$drive['webUrl']).StartsWith($PersonalSite.Url+'/',[StringComparison]::OrdinalIgnoreCase)) {throw 'Default drive root is not under selected existing OneDrive.'}
 $drive
}
function ConvertTo-OD34RelativePath {
 param([Parameter(Mandatory)][string]$Value)
 $path=$Value.Trim()
 if (-not $path -or $path.StartsWith('/') -or $path -match '^[a-zA-Z]+:' -or $path -match '[\\\x00-\x1f]' -or @($path -split '/' | Where-Object {$_ -in @('.','..') -or -not $_}).Count) {throw 'Use a plain path relative to the OneDrive Documents root, e.g. HR/Handbook.docx. Do not use a URL, leading slash or traversal.'}
 $path
}
function Assert-OD34Item {
 param([System.Collections.IDictionary]$Item,[string]$DriveId)
 if (-not $Item['id'] -or $Item.Contains('root') -and $null -ne $Item['root']) {throw 'Sharing the entire drive root is not supported.'}
 if ($Item.Contains('remoteItem') -and $null -ne $Item['remoteItem']) {throw 'Remote shortcuts are excluded; select an actual item in this OneDrive.'}
 if (-not (($Item.Contains('file') -and $null -ne $Item['file']) -or ($Item.Contains('folder') -and $null -ne $Item['folder']))) {throw 'Selected item is not a confirmed file/folder.'}
 if ([string]$Item['parentReference']['driveId'] -cne $DriveId) {throw 'Item belongs to a different or unverified drive.'}
}
function Get-OD34Item {
 param([string]$DriveId,[string]$ItemPath,[string]$ItemId)
 $base='https://graph.microsoft.com/v1.0/drives/'+[uri]::EscapeDataString($DriveId)
 $select='?$select=id,name,webUrl,parentReference,file,folder,root,remoteItem'
 if ($ItemId) {$uri=$base+'/items/'+[uri]::EscapeDataString($ItemId)+$select}
 else {
  $path=ConvertTo-OD34RelativePath $ItemPath
  $encoded=(@($path -split '/' | ForEach-Object {[uri]::EscapeDataString($_)}) -join '/')
  $uri=$base+'/root:/'+$encoded+$select
 }
 $item=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable -ErrorAction Stop
 Assert-OD34Item -Item $item -DriveId $DriveId
 $item
}
function New-OD34LinkBody {
 param([ValidateSet('Organization','Anonymous')][string]$Scope,[ValidateSet('View','Edit')][string]$LinkType,[datetimeoffset]$ExpiresUtc)
 if ($ExpiresUtc -le [datetimeoffset]::UtcNow.AddMinutes(1)) {throw 'Link expiration must be more than one minute in the future.'}
 @{type=$LinkType.ToLowerInvariant();scope=$Scope.ToLowerInvariant();expirationDateTime=$ExpiresUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');retainInheritedPermissions=$true}
}
function Get-OD34Permissions {
 param([string]$DriveId,[string]$ItemId)
 $path='/v1.0/drives/'+[uri]::EscapeDataString($DriveId)+'/items/'+[uri]::EscapeDataString($ItemId)+'/permissions'
 $next='https://graph.microsoft.com'+$path+'?$select=id,roles,link,expirationDateTime,inheritedFrom'
 $seen=[Collections.Generic.HashSet[string]]::new();$rows=[Collections.Generic.List[object]]::new()
 while ($next) {
  $u=[uri]$next
  if ($u.Scheme -ne 'https' -or $u.Host -ne 'graph.microsoft.com' -or $u.AbsolutePath -cne $path -or $u.UserInfo -or $u.Fragment -or -not $u.IsDefaultPort -or -not $seen.Add($next)) {throw 'Unexpected/repeated permission pagination URL.'}
  $page=Invoke-MgGraphRequest -Method GET -Uri $next -OutputType Hashtable -ErrorAction Stop
  if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value')) {throw 'Invalid permission collection response.'}
  foreach ($p in @($page['value'])) {
   $link=Get-ODPValue $p 'link'
   # Do not serialize bearer URLs/shareIds from raw permission responses.
   $rows.Add([pscustomobject]@{Id=[string](Get-ODPValue $p 'id');Roles=@(Get-ODPValue $p 'roles');LinkScope=[string](Get-ODPValue $link 'scope');LinkType=[string](Get-ODPValue $link 'type');Expiration=[string](Get-ODPValue $p 'expirationDateTime');Inherited=($null -ne (Get-ODPValue $p 'inheritedFrom'))})
  }
  $next=[string]$page['@odata.nextLink']
 }
 $rows.ToArray()
}
function ConvertTo-OD34Number {
 param([object]$Value)
 $n=[decimal]0
 if ($null -eq $Value -or $Value -is [bool]) {return $null}
 $text=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
 if ([string]::IsNullOrWhiteSpace($text) -or -not [decimal]::TryParse($text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or $n -lt 0) {return $null}
 $n
}
function New-OD34StorageRow {
 param([System.Collections.IDictionary]$Owner,[hashtable]$PersonalSite)
 $used=ConvertTo-OD34Number (Get-ODPValue $PersonalSite.Details 'StorageUsageCurrent')
 $quota=ConvertTo-OD34Number (Get-ODPValue $PersonalSite.Details 'StorageQuota')
 $status=if ($null -eq $used -or $null -eq $quota -or $quota -eq 0) {'PartialMetricCoverage'} else {'ReadSucceeded'}
 $row=[ordered]@{OwnerUPN=[string]$Owner['userPrincipalName'];OwnerId=[string]$Owner['id'];OneDriveUrl=$PersonalSite.Url;ReadUtc=[datetime]::UtcNow.ToString('o');Status=$status;StorageUsedMB=$used;QuotaMB=$quota;UsedGiB=$null;QuotaGiB=$null;RemainingToSiteQuotaGiB=$null;OverQuotaGiB=$null;UtilizationPercent=$null;LockState=[string](Get-ODPValue $PersonalSite.Details 'LockState');Notes='Service-reported rounded binary MB; GiB=MB/1024; telemetry may lag; site quota is not tenant free capacity'}
 if ($null -ne $used) {$row.UsedGiB=[Math]::Round($used/1024,3)}
 if ($null -ne $quota) {$row.QuotaGiB=[Math]::Round($quota/1024,3)}
 if ($null -ne $used -and $null -ne $quota -and $quota -gt 0) {
  $row.RemainingToSiteQuotaGiB=[Math]::Round([Math]::Max([decimal]0,$quota-$used)/1024,3)
  $row.OverQuotaGiB=[Math]::Round([Math]::Max([decimal]0,$used-$quota)/1024,3)
  $row.UtilizationPercent=[Math]::Round(100*$used/$quota,2)
 }
 [pscustomobject]$row
}
