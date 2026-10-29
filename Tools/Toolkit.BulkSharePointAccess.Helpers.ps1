# Definitions only. Independent of earlier SharePoint ZIPs.
function ConvertTo-BSAUrl {
 param([Parameter(Mandatory)][string]$Value,[string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort -or $u.Host -notmatch '^[a-z0-9-]+\.sharepoint\.com$' -or $u.Host -match '-(admin|my)\.sharepoint\.com$') { throw 'Use an HTTPS SharePoint site collection URL, without credentials, query, fragment or custom port.' }
 if ($AllowedHost -and $u.Host -ine $AllowedHost) { throw 'Site URL is outside verified tenant root host; multi-geo/cross-host sites not supported.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function Import-BSACsv {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$LiteralPath,[ValidateRange(1,10000)][int]$MaxRows=1000)
 $file=Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
 if ($file.PSIsContainer -or $file.Extension -ine '.csv') { throw 'Select a CSV file.' }
 if ($file.Length -gt 10MB) { throw 'CSV exceeds 10 MB safety limit.' }
 Add-Type -AssemblyName Microsoft.VisualBasic.Core -ErrorAction Stop
 $parser=[Microsoft.VisualBasic.FileIO.TextFieldParser]::new($file.FullName,[Text.UTF8Encoding]::new($false,$true),$true)
 $rows=[Collections.Generic.List[object]]::new()
 try {
  $parser.TextFieldType=[Microsoft.VisualBasic.FileIO.FieldType]::Delimited
  $parser.SetDelimiters([string[]]@(',')); $parser.HasFieldsEnclosedInQuotes=$true; $parser.TrimWhiteSpace=$false
  if ($parser.EndOfData) { throw 'CSV is empty.' }
  $headers=@($parser.ReadFields() | ForEach-Object { $_.Trim() })
  $required=@('SiteUrl','SharePointGroupId','UserPrincipalName')
  if ($headers.Count -ne 3) { throw 'CSV requires exactly SiteUrl,SharePointGroupId,UserPrincipalName headers.' }
  foreach ($name in $required) { if (@($headers | Where-Object { $_ -ieq $name }).Count -ne 1) { throw ('Missing or duplicate CSV header: '+$name) } }
  $indexes=@{}; for ($i=0;$i -lt $headers.Count;$i++) { $indexes[$headers[$i]]=$i }
  $record=1
  while (-not $parser.EndOfData) {
   $record++; $fields=$parser.ReadFields()
   if ($fields.Count -ne 3) { throw ('CSV record '+$record+' must have exactly three fields.') }
   $url=ConvertTo-BSAUrl -Value $fields[$indexes.SiteUrl]
   $groupId=0
   if (-not [int]::TryParse($fields[$indexes.SharePointGroupId].Trim(),[ref]$groupId) -or $groupId -lt 1) { throw ('Invalid SharePointGroupId at record '+$record+'; use a positive site-local integer, not an Entra group GUID.') }
   $upn=$fields[$indexes.UserPrincipalName].Trim()
   if ($upn -notmatch '^[^@\s]+@[^@\s]+$' -or $upn.Length -gt 254) { throw ('Invalid UserPrincipalName at record '+$record) }
   if ($rows.Count -ge $MaxRows) { throw ('CSV exceeds '+$MaxRows+' row limit; split batch. No rows submitted.') }
   $rows.Add([pscustomobject]@{Record=$record;SiteUrl=$url;SharePointGroupId=$groupId;UserPrincipalName=$upn})
  }
  if (-not $rows.Count) { throw 'CSV has headers only. Add real rows to a private working copy.' }
 } finally { $parser.Close(); $parser.Dispose() }
 $rows.ToArray()
}
function Assert-BSAToken {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.'); if ($parts.Count -ne 3) { throw 'Not JWT' }
  $p=$parts[1].Replace('-','+').Replace('_','/'); $p=$p.PadRight($p.Length+((4-$p.Length%4)%4),'=')
  $c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch { throw 'Existing SharePoint token identity cannot be inspected; reconnect through toolkit.' }
 if ([string]$c['tid'] -ine $TenantId -or $Account -notin @($c['upn'],$c['preferred_username'],$c['unique_name'])) { throw 'SharePoint token tenant/account does not match verified toolkit session.' }
 if (-not $c['exp'] -or [long]$c['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) { throw 'SharePoint token expired or near expiry; reconnect and rebuild plan.' }
}
function Get-BSAUser {
 param([string]$Identity)
 $uri='https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($Identity.Trim())+'?$select=id,displayName,userPrincipalName,userType'
 $u=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable -ErrorAction Stop
 $id=[guid]::Empty
 if ($u -isnot [System.Collections.IDictionary] -or -not [guid]::TryParse([string]$u['id'],[ref]$id) -or $id -eq [guid]::Empty -or $u['userType'] -ne 'Member' -or -not $u['userPrincipalName']) { throw 'Only resolvable tenant Member users are supported.' }
 $u
}
function Get-BSASiteUser {
 param([string]$Upn,[object]$Connection)
 $claim='i:0#.f|membership|'+$Upn
 $users=@(Get-PnPUser -Identity $claim -Connection $Connection -ErrorAction Stop)
 if ($users.Count -ne 1 -or [string]$users[0].LoginName -ine $claim -or [int]$users[0].Id -lt 1) { throw 'Existing canonical site user could not be verified; this version does not provision site users.' }
 $users[0]
}
function Get-BSARowState {
 param([int]$GroupId,[int]$OwnerGroupId,[bool]$Duplicate,[bool]$AlreadyMember)
 if ($GroupId -eq $OwnerGroupId) { return 'OwnersExcluded' }
 if ($Duplicate) { return 'Duplicate' }
 if ($AlreadyMember) { return 'AlreadyMember' }
 'Eligible'
}
function ConvertTo-BSASafeCsv {
 param([object]$Row)
 $values=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $values[$p.Name]=$value
 }
 [pscustomobject]$values
}
