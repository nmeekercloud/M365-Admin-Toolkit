# Definitions only. Read-only storage reporting helpers.
function ConvertTo-SSRUrl {
 param([string]$Value,[string]$AllowedHost)
 $u=$null
 if (-not [uri]::TryCreate($Value.Trim(),[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -ine $AllowedHost -or $u.UserInfo -or $u.Query -or $u.Fragment -or -not $u.IsDefaultPort) { throw 'Use HTTPS site collection URLs on the verified root host without credentials, query, fragment or custom port.' }
 $u.AbsoluteUri.TrimEnd('/')
}
function Get-SSRField {
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
function ConvertTo-SSRNumber {
 param([object]$Value)
 $n=[decimal]0
 if ($null -eq $Value -or $Value -is [bool]) { return [pscustomobject]@{Valid=$false;Value=$null} }
 $text=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
 if ([string]::IsNullOrWhiteSpace($text) -or -not [decimal]::TryParse($text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or $n -lt 0) { return [pscustomobject]@{Valid=$false;Value=$null} }
 [pscustomobject]@{Valid=$true;Value=$n}
}
function ConvertTo-SSRRow {
 param([string]$Url,[object]$Settings,[decimal]$WarningPercent=80,[decimal]$CriticalPercent=90,[string]$ErrorText='')
 $missing=[Collections.Generic.List[string]]::new()
 $data=@{}
 foreach ($name in @('Title','Template','Owner','LockState','LastContentModifiedDate','StorageUsageCurrent','StorageQuota','StorageQuotaWarningLevel')) {
  $field=Get-SSRField $Settings $name
  if (-not $field.Available) { $missing.Add($name) }
  $data[$name]=$field.Value
 }
 $used=ConvertTo-SSRNumber $data.StorageUsageCurrent; $quota=ConvertTo-SSRNumber $data.StorageQuota
 $warning=ConvertTo-SSRNumber $data.StorageQuotaWarningLevel
 $row=[ordered]@{
  SiteUrl=$Url;Title=$data.Title;Template=$data.Template;Owner=$data.Owner;LockState=[string]$data.LockState
  LastContentModifiedDate=[string]$data.LastContentModifiedDate;ReadStatus='';Error=$ErrorText
  StorageUsageCurrentMB=$used.Value;StorageQuotaMB=$quota.Value;StorageQuotaWarningLevelMB=$warning.Value
  UsedGiB=$null;QuotaGiB=$null;HeadroomToSiteQuotaGiB=$null;OverSiteQuotaGiB=$null;UtilizationPercent=$null
  UtilizationStatus='Unknown';MetricIssues='';UnavailableProperties=($missing -join '; ')
  Interpretation='Service-reported rounded binary MB; quota is a site limit, not reserved tenant capacity; telemetry can lag'
 }
 $issues=[Collections.Generic.List[string]]::new()
 if ($used.Valid) { $row.UsedGiB=[Math]::Round($used.Value/1024,3) } else { $issues.Add('StorageUsageCurrent missing/invalid') }
 if ($quota.Valid) { $row.QuotaGiB=[Math]::Round($quota.Value/1024,3) } else { $issues.Add('StorageQuota missing/invalid') }
 if ($used.Valid -and $quota.Valid -and $quota.Value -gt 0) {
  $pct=100*$used.Value/$quota.Value
  $row.UtilizationPercent=[Math]::Round($pct,2)
  $row.HeadroomToSiteQuotaGiB=[Math]::Round([Math]::Max([decimal]0,$quota.Value-$used.Value)/1024,3)
  $row.OverSiteQuotaGiB=[Math]::Round([Math]::Max([decimal]0,$used.Value-$quota.Value)/1024,3)
  $row.UtilizationStatus=if ($used.Value -gt $quota.Value) {'OverSiteQuota'} elseif ($pct -ge $CriticalPercent) {'Critical'} elseif ($pct -ge $WarningPercent) {'Warning'} else {'BelowWarningThreshold'}
 } elseif ($quota.Valid -and $quota.Value -eq 0) { $issues.Add('No positive site quota; utilization/headroom not calculated') }
 if (-not $warning.Valid) { $issues.Add('StorageQuotaWarningLevel missing/invalid') }
 $row.MetricIssues=$issues -join '; '
 $row.ReadStatus=if ($ErrorText) {'Error'} elseif (-not $used.Valid -or -not $quota.Valid -or $quota.Value -eq 0) {'ReadWithMetricGaps'} elseif ($missing.Count -or -not $warning.Valid) {'ReadWithUnavailableFields'} else {'ReadSucceeded'}
 if ($ErrorText) {
  foreach ($name in @('StorageUsageCurrentMB','StorageQuotaMB','StorageQuotaWarningLevelMB','UsedGiB','QuotaGiB','HeadroomToSiteQuotaGiB','OverSiteQuotaGiB','UtilizationPercent')) { $row[$name]=$null }
  $row.UtilizationStatus='Unknown'
 }
 [pscustomobject]$row
}
function ConvertTo-SSRSafeCsv {
 param([object]$Row)
 $out=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $out[$p.Name]=$value
 }
 [pscustomobject]$out
}
