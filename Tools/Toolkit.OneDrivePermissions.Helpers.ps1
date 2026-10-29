# Definitions only. OneDrive permissions package; no calls on dot-source.
function Get-ODPValue {
 param([object]$Object,[string]$Name)
 try { if ($null -eq $Object) {return $null}; if ($Object -is [System.Collections.IDictionary]) {return $Object[$Name]}; $p=$Object.PSObject.Properties[$Name]; if ($p) {return $p.Value} } catch {return $null}
}
function ConvertTo-ODPClaimUpn {
 param([string]$Login)
 if ($Login -like 'i:0#.f|membership|*') { return $Login.Substring('i:0#.f|membership|'.Length) }
 if ($Login -match '^[^@\s|]+@[^@\s|]+$') {return $Login}
 ''
}
function Assert-ODPPersonalUrl {
 param([string]$Url,[string]$RootHost)
 $u=$null; $expected=$RootHost.Replace('.sharepoint.com','-my.sharepoint.com')
 if (-not [uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $expected -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort -or $u.AbsolutePath -notmatch '^/personal/[^/]+/?$') {throw 'Profile PersonalUrl must be an exact existing OneDrive site on the verified tenant -my host. Multi-geo/custom paths are not supported.'}
 $u.AbsoluteUri.TrimEnd('/')
}
function Assert-ODPToken {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.');if ($parts.Count -ne 3) {throw 'Not JWT'}
  $p=$parts[1].Replace('-','+').Replace('_','/');$p=$p.PadRight($p.Length+((4-$p.Length%4)%4),'=')
  $c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch {throw 'Cannot inspect existing SharePoint token identity; reconnect through toolkit.'}
 if ([string]$c['tid'] -ine $TenantId -or $Account -notin @($c['upn'],$c['preferred_username'],$c['unique_name'])) {throw 'SharePoint token account/tenant differs from verified toolkit session.'}
 if (-not $c['exp'] -or [long]$c['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) {throw 'SharePoint token expired/near expiry; reconnect and rebuild the plan.'}
}
function Initialize-ODPTask {
 param([string]$Root,[string]$TaskId,[ValidateSet('ReadOnly','Changes')][string]$AccessMode)
 if (-not (Get-Module M365Toolkit.Core)) {Import-Module (Join-Path $Root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop}
 $null=Assert-M365TaskAccess -AccessMode $AccessMode -TaskId $TaskId
 $tenant=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('User.Read.All','Sites.Read.All') -TaskId $TaskId -TaskName 'OneDrive permissions / site administrators'
 if (-not $tenant.TenantId -or [string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') {throw 'Verified global-cloud tenant required.'}
 $tenant
}
function Get-ODPUser {
 param([string]$Identity)
 if (-not $Identity) {throw 'A user UPN or immutable user ID is required.'}
 $u=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($Identity.Trim())+'?$select=id,displayName,userPrincipalName,userType') -OutputType Hashtable -ErrorAction Stop
 $id=[guid]::Empty
 if ($u -isnot [System.Collections.IDictionary] -or -not [guid]::TryParse([string]$u['id'],[ref]$id) -or $id -eq [guid]::Empty -or $u['userType'] -ne 'Member' -or -not $u['userPrincipalName']) {throw 'Only resolvable tenant Member accounts are supported; guests are excluded.'}
 $u
}
function Get-ODPContext {
 param([object]$Tenant,[System.Collections.IDictionary]$Owner)
 $admin=Get-M365SharePointConnection -ErrorAction Stop
 $root=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType Hashtable -ErrorAction Stop
 $rootUri=[uri]$root['webUrl'];$hostName=$rootUri.Host
 if ($rootUri.Scheme -ne 'https' -or $hostName -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $hostName -match '-(my|admin)\.sharepoint\.com$') {throw 'Unsupported verified SharePoint root host.'}
 if (([uri]$admin.Url).Scheme -ne 'https' -or ([uri]$admin.Url).Host -ine $hostName.Replace('.sharepoint.com','-admin.sharepoint.com')) {throw 'Toolkit admin connection URL mismatch.'}
 # Profile read, never GET /users/{id}/drive or personal-site provisioning.
 $profiles=@(Get-PnPUserProfileProperty -Account $Owner['userPrincipalName'] -Connection $admin -ErrorAction Stop)
 if ($profiles.Count -ne 1) {throw 'Expected exactly one owner profile.'}
 $profile=$profiles[0]
 $profileAccount=ConvertTo-ODPClaimUpn ([string](Get-ODPValue $profile 'AccountName'))
 if ($profileAccount -ine [string]$Owner['userPrincipalName']) {throw 'Profile owner account cannot be matched to resolved user.'}
 $personal=[string](Get-ODPValue $profile 'PersonalUrl')
 if (-not $personal) {$properties=Get-ODPValue $profile 'UserProfileProperties';$personal=[string](Get-ODPValue $properties 'PersonalUrl')}
 if (-not $personal) {throw 'No existing PersonalUrl returned. OneDrive may be unprovisioned/inaccessible. Nothing was provisioned.'}
 $url=Assert-ODPPersonalUrl -Url $personal -RootHost $hostName
 $siteInfo=Get-PnPTenantSite -Identity $url -Detailed -Connection $admin -ErrorAction Stop
 if (([string]$siteInfo.Url).TrimEnd('/') -ine $url -or [string]$siteInfo.Template -notlike 'SPSPERS*') {throw 'Resolved URL is not an existing personal site.'}
 $resource=([uri]$url).GetLeftPart([UriPartial]::Authority)
 $raw=Get-PnPAccessToken -ResourceUrl $resource -Connection $admin -ErrorAction Stop
 $token=if ($raw -is [Security.SecureString]) {([pscredential]::new('token',$raw)).GetNetworkCredential().Password} else {[string]$raw};$raw=$null
 Assert-ODPToken $token $Tenant.TenantId $Tenant.Account
 $connection=Connect-PnPOnline -Url $url -AccessToken $token -ReturnConnection -ErrorAction Stop
 $site=Get-PnPSite -Includes Id,Url,Owner -Connection $connection -ErrorAction Stop
 $web=Get-PnPWeb -Includes Id,Url -Connection $connection -ErrorAction Stop
 if (([string]$site.Url).TrimEnd('/') -ine $url -or ([string]$web.Url).TrimEnd('/') -ine $url) {throw 'Personal site/root-web URL mismatch.'}
 $null=Get-PnPProperty -ClientObject $site.Owner -Property Id,LoginName,Title -Connection $connection -ErrorAction Stop
 $primary=ConvertTo-ODPClaimUpn ([string]$site.Owner.LoginName)
 if ($primary -ine [string]$Owner['userPrincipalName']) {throw 'Actual primary site owner differs from resolved OneDrive user; no change permitted.'}
 $siteId=[guid]::Empty;$webId=[guid]::Empty
 if (-not [guid]::TryParse([string]$site.Id,[ref]$siteId) -or -not [guid]::TryParse([string]$web.Id,[ref]$webId) -or $siteId -eq [guid]::Empty -or $webId -eq [guid]::Empty) {throw 'Site/web immutable IDs missing.'}
 @{Url=$url;SiteId=$siteId.ToString('D');WebId=$webId.ToString('D');PrimaryLogin=[string]$site.Owner.LoginName;PrimarySiteUserId=[int]$site.Owner.Id;Connection=$connection;Web=$web;Token=$token}
}
function Get-ODPAdministrators {
 param([hashtable]$Context)
 $admins=@(Get-PnPSiteCollectionAdmin -Connection $Context.Connection -ErrorAction Stop)
 if (-not $admins.Count -or $Context.PrimarySiteUserId -notin @($admins | ForEach-Object {[int]$_.Id})) {throw 'Administrator list is empty or primary owner is absent. Refusing incomplete evidence.'}
 foreach ($a in $admins) {
  if ([int]$a.Id -lt 1 -or -not [string]$a.LoginName) {throw 'Administrator identity metadata incomplete.'}
  [pscustomobject]@{SiteUserId=[int]$a.Id;LoginName=[string]$a.LoginName;Title=[string]$a.Title;IsPrimaryOwner=([int]$a.Id -eq $Context.PrimarySiteUserId)}
 }
}
function Assert-ODPRemoval {
 param([string]$TargetUserId,[string]$OwnerUserId,[string]$TargetUpn,[string]$OperatorUpn,[int]$AdminCount,[bool]$TargetIsPrimary)
 if ($TargetUserId -ieq $OwnerUserId -or $TargetIsPrimary) {throw 'Removing the OneDrive owner / primary site administrator is blocked.'}
 if ($TargetUpn -ieq $OperatorUpn) {throw 'Removing the signed-in operator is blocked.'}
 if ($AdminCount -le 1) {throw 'Removing the final observed administrator is blocked.'}
}
function ConvertTo-ODPSafeCsv {
 param([object]$Row)
 $v=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value;if ($value -is [string] -and $value -match '^\s*[=+@-]') {$value="'"+$value};$v[$p.Name]=$value
 }
 [pscustomobject]$v
}
function New-ODPAccessRow {
 param([hashtable]$Context,[object]$Principal,[string]$Origin,[string]$ViaGroup,[string]$Roles)
 [pscustomobject]@{SiteUrl=$Context.Url;SiteId=$Context.SiteId;Scope='Site administrators and root-web grants only';Origin=$Origin;ViaSharePointGroup=$ViaGroup;PrincipalId=[string](Get-ODPValue $Principal 'Id');PrincipalType=[string](Get-ODPValue $Principal 'PrincipalType');Title=[string](Get-ODPValue $Principal 'Title');LoginName=[string](Get-ODPValue $Principal 'LoginName');Roles=$Roles;Limitations='No file/folder/link scan, no Entra-group expansion or effective-access calculation'}
}
