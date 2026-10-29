# Definitions only; no calls on dot-source.
function Get-EGCollection {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$ExpectedPath)
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $rows=[Collections.Generic.List[object]]::new()
 while ($Uri) {
  $u=$null
  if (-not [uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ne 'graph.microsoft.com' -or $u.AbsolutePath -cne $ExpectedPath -or $u.UserInfo -or $u.Fragment) { throw 'Unexpected Graph pagination URL.' }
  if (-not $seen.Add($Uri)) { throw 'Repeated Graph pagination URL.' }
  $page=Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType Hashtable -ErrorAction Stop
  if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value') -or $null -eq $page['value']) { throw 'Invalid Graph collection response.' }
  foreach ($item in @($page['value'])) {
   if ($item -isnot [System.Collections.IDictionary]) { throw 'Invalid collection object.' }
   $id=[guid]::Empty
   if (-not [guid]::TryParse([string]$item['id'],[ref]$id)) { throw 'Directory object missing valid immutable ID.' }
   if ($ids.Add($id.ToString('D'))) { $rows.Add($item) }
  }
  $Uri=[string]$page['@odata.nextLink']
 }
 $rows.ToArray()
}
function Get-EGType {
 param([System.Collections.IDictionary]$Group)
 if ('Unified' -in @($Group['groupTypes'])) { return 'Microsoft 365' }
 if ($Group['mailEnabled'] -eq $false -and $Group['securityEnabled'] -eq $true) { return 'Security' }
 if ($Group['mailEnabled'] -eq $true -and $Group['securityEnabled'] -eq $true) { return 'Mail-enabled security' }
 if ($Group['mailEnabled'] -eq $true -and $Group['securityEnabled'] -eq $false) { return 'Distribution' }
 'Unknown'
}
function ConvertTo-EGMember {
 param([System.Collections.IDictionary]$Group,[System.Collections.IDictionary]$Member)
 $limited=-not ([string]$Member['displayName'] -or [string]$Member['mail'] -or [string]$Member['userPrincipalName'])
 [pscustomobject]@{
  GroupId=[string]$Group['id'];GroupName=[string]$Group['displayName'];GroupMail=[string]$Group['mail']
  MembershipScope='Direct';ObjectType=[string]$Member['@odata.type'];ObjectId=[string]$Member['id']
  DisplayName=[string]$Member['displayName'];UserPrincipalName=[string]$Member['userPrincipalName'];Mail=[string]$Member['mail']
  Information=$(if ($limited) {'Limited information returned'} else {'Available properties shown'})
  Coverage='Graph v1.0; service principals may be omitted; not effective-access inventory'
 }
}
function ConvertTo-EGSafeCsv {
 param([object]$Row)
 $values=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $values[$p.Name]=$value
 }
 [pscustomobject]$values
}
function Initialize-EGCsv {
 param([string]$LiteralPath,[string[]]$Columns)
 $blank=[ordered]@{}
 foreach ($name in $Columns) { $blank[$name]='' }
 $header=@([pscustomobject]$blank | ConvertTo-Csv -NoTypeInformation)[0]
 Set-Content -LiteralPath $LiteralPath -Value $header -Encoding utf8 -ErrorAction Stop
}
