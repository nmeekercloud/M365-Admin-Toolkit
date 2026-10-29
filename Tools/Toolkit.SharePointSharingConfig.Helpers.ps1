# Definitions only. Configuration report; no permission/member operations.
function ConvertTo-ESCUrl {
 param([string]$Value,[string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $AllowedHost -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) { throw 'Use HTTPS site collection URLs on the verified root host without query, fragment, credentials or custom port.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function Get-ESCField {
 param([object]$Object,[string]$Name)
 try {
  if ($null -eq $Object) { return [pscustomobject]@{Available=$false;Value=$null} }
  if ($Object -is [System.Collections.IDictionary]) {
   if (-not $Object.Contains($Name)) { return [pscustomobject]@{Available=$false;Value=$null} }
   return [pscustomobject]@{Available=$true;Value=$Object[$Name]}
  }
  if ($Object.PSObject.Methods['IsPropertyAvailable'] -and -not $Object.IsPropertyAvailable($Name)) { return [pscustomobject]@{Available=$false;Value=$null} }
  $p=$Object.PSObject.Properties[$Name]
  if ($null -eq $p) { return [pscustomobject]@{Available=$false;Value=$null} }
  [pscustomobject]@{Available=$true;Value=$p.Value}
 } catch { [pscustomobject]@{Available=$false;Value=$null} }
}
function Get-ESCCapabilityLabel {
 param([object]$Value)
 switch ([string]$Value) {
  'Disabled' {'Only people in your organization'}
  'ExistingExternalUserSharingOnly' {'Existing guests only'}
  'ExternalUserSharingOnly' {'New and existing guests'}
  'ExternalUserAndGuestSharing' {'Anyone links and authenticated guests'}
  default {'Unknown / unavailable'}
 }
}
function Get-ESCCapabilityCeiling {
 param([object]$TenantValue,[object]$SiteValue)
 $levels=@('Disabled','ExistingExternalUserSharingOnly','ExternalUserSharingOnly','ExternalUserAndGuestSharing')
 $t=[array]::IndexOf($levels,[string]$TenantValue); $s=[array]::IndexOf($levels,[string]$SiteValue)
 if ($t -lt 0 -or $s -lt 0) { return 'Unknown / unavailable' }
 $levels[[Math]::Min($t,$s)]
}
function New-ESCSettingsRow {
 param([string]$Scope,[string]$Url,[object]$Settings,[string[]]$Fields,[string]$ErrorText='')
 $row=[ordered]@{Scope=$Scope;Url=$Url;ReadStatus='';Error=$ErrorText;SharingCapabilityLabel='';CapabilityCeilingOnly='Not calculated';UnavailableProperties='';Interpretation='Configuration only; not evidence of actual external access or links'}
 $missing=[Collections.Generic.List[string]]::new()
 foreach ($name in $Fields) {
  $field=Get-ESCField -Object $Settings -Name $name
  $value=$field.Value
  if (-not $field.Available) { $missing.Add($name); $value=$null }
  elseif ($value -is [array]) { $value=$value -join '; ' }
  $row[$name]=$value
 }
 $row.UnavailableProperties=$missing -join '; '
 $row.SharingCapabilityLabel=Get-ESCCapabilityLabel $row['SharingCapability']
 $row.ReadStatus=if ($ErrorText) {'Error'} elseif ($missing.Count) {'ReadWithUnavailableFields'} else {'ReadSucceeded'}
 if (-not $ErrorText -and $row.SharingCapabilityLabel -eq 'Unknown / unavailable') { $row.ReadStatus='MissingOrUnknownCoreSetting' }
 [pscustomobject]$row
}
function ConvertTo-ESCSafeCsv {
 param([object]$Row)
 $v=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $v[$p.Name]=$value
 }
 [pscustomobject]$v
}
