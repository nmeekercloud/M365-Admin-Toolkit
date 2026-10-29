# Definitions only; no authentication or tenant calls on dot-source.
function ConvertTo-SAUrl {
 param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $AllowedHost -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) { throw 'Site URL must be HTTPS on the verified SharePoint root host, without credentials, query or fragment.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function ConvertTo-SASafeCsv {
 param([object]$Row)
 $values=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $v=$p.Value
  if ($v -is [string] -and $v -match '^\s*[=+@-]') { $v="'"+$v }
  $values[$p.Name]=$v
 }
 [pscustomobject]$values
}
function Initialize-SACsv {
 param([string]$Path,[string[]]$Columns)
 $row=[ordered]@{}; foreach ($c in $Columns) { $row[$c]='' }
 $header=@([pscustomobject]$row | ConvertTo-Csv -NoTypeInformation)[0]
 Set-Content -LiteralPath $Path -Value $header -Encoding utf8 -ErrorAction Stop
}
function ConvertTo-SAPrincipalRow {
 param([string]$SiteUrl,[string]$SiteTitle,[object]$Principal,[string]$Origin,[string]$ViaGroup,[string]$Roles)
 [pscustomobject]@{
  SiteUrl=$SiteUrl;SiteTitle=$SiteTitle;ScanScope='Site collection administrators and root web only'
  Origin=$Origin;ViaSharePointGroup=$ViaGroup;PrincipalId=[string]$Principal.Id
  PrincipalType=[string]$Principal.PrincipalType;Title=[string]$Principal.Title;LoginName=[string]$Principal.LoginName
  RoleNames=$Roles;Expansion='Direct SharePoint group members only; Entra groups not expanded'
 }
}
function Assert-SATokenClaims {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.')
  if ($parts.Count -ne 3) { throw 'Not JWT' }
  $payload=$parts[1].Replace('-','+').Replace('_','/')
  $payload=$payload.PadRight($payload.Length+((4-$payload.Length%4)%4),'=')
  $claims=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch { throw 'Cannot inspect existing SharePoint token identity; reconnect through the toolkit.' }
 if ([string]$claims['tid'] -ine $TenantId) { throw 'SharePoint token tenant differs from verified tenant.' }
 $identities=@($claims['upn'],$claims['preferred_username'],$claims['unique_name']) | Where-Object { $_ }
 if ($Account -notin $identities) { throw 'SharePoint token account differs from verified toolkit account, or cannot be verified.' }
 if (-not $claims['exp'] -or [long]$claims['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) { throw 'SharePoint token expired or near expiry. Reconnect before scanning.' }
 # Claim inspection is an additional consistency check, not signature validation.
}
