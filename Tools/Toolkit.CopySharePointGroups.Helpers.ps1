# Definitions only. Independent of other ZIP helper files.
function ConvertTo-CSUrl {
 param([string]$Value,[string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $AllowedHost -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) { throw 'Use an HTTPS site collection URL on the verified root host, without credentials, query or fragment.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function Assert-CSToken {
 param([string]$Token,[string]$TenantId,[string]$Account)
 try {
  $parts=$Token.Split('.'); if ($parts.Count -ne 3) { throw 'Not JWT' }
  $p=$parts[1].Replace('-','+').Replace('_','/'); $p=$p.PadRight($p.Length+((4-$p.Length%4)%4),'=')
  $c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
 } catch { throw 'Existing SharePoint token identity cannot be inspected; reconnect through toolkit.' }
 if ([string]$c['tid'] -ine $TenantId -or $Account -notin @($c['upn'],$c['preferred_username'],$c['unique_name'])) { throw 'SharePoint token tenant/account does not match verified toolkit session.' }
 if (-not $c['exp'] -or [long]$c['exp'] -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60) { throw 'SharePoint token expired or near expiry. Reconnect and rebuild plan.' }
}
function Get-CSUser {
 param([string]$Identity)
 if (-not $Identity) { throw 'User identity required.' }
 $uri='https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($Identity.Trim())+'?$select=id,displayName,userPrincipalName,userType'
 $u=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable -ErrorAction Stop
 $id=[guid]::Empty
 if (-not [guid]::TryParse([string]$u['id'],[ref]$id) -or $u['userType'] -ne 'Member' -or -not $u['userPrincipalName']) { throw 'Only resolvable tenant Member users are supported.' }
 $u
}
function Get-CSSiteUser {
 param([string]$Upn,[object]$Connection)
 $claim='i:0#.f|membership|'+$Upn
 $users=@(Get-PnPUser -Identity $claim -Connection $Connection -ErrorAction Stop)
 if ($users.Count -ne 1 -or [string]$users[0].LoginName -ine $claim -or [int]$users[0].Id -lt 1) { throw 'Canonical site user cannot be verified.' }
 $users[0]
}
function Select-CSRows {
 param([object[]]$Plan,[string]$Selection)
 $eligible=@($Plan | Where-Object Status -eq 'Eligible')
 if (-not $Selection) { return }
 if ($Selection.Trim() -ieq 'ALL') { $eligible; return }
 $numbers=[Collections.Generic.HashSet[int]]::new()
 foreach ($token in ($Selection -split '[,;]')) {
  $n=0
  if (-not [int]::TryParse($token.Trim(),[ref]$n) -or $n -lt 1 -or @($eligible | Where-Object Number -eq $n).Count -ne 1) { throw ('Invalid/ineligible plan number: '+$token) }
  $null=$numbers.Add($n)
 }
 foreach ($row in $eligible) { if ($numbers.Contains([int]$row.Number)) { $row } }
}
function ConvertTo-CSCsvSafe {
 param([object]$Row)
 $v=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $v[$p.Name]=$value
 }
 [pscustomobject]$v
}
