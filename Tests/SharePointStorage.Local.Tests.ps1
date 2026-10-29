#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.SharePointStorage.Helpers.ps1')
function Assert-SSRTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function New-SSRTestSite([object]$Used,[object]$Quota) { @{Title='Test';Template='STS#3';Owner='test.user@contoso.com';LockState='Unlock';LastContentModifiedDate='2026-01-01';StorageUsageCurrent=$Used;StorageQuota=$Quota;StorageQuotaWarningLevel=900} }
$row=ConvertTo-SSRRow Test (New-SSRTestSite 512 1024)
Assert-SSRTest ($row.UsedGiB -eq 0.5 -and $row.QuotaGiB -eq 1 -and $row.UtilizationPercent -eq 50 -and $row.ReadStatus -eq 'ReadSucceeded') 'Binary units/utilization failed.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 0 1024)
Assert-SSRTest ($row.StorageUsageCurrentMB -eq 0 -and $row.UtilizationPercent -eq 0) 'Real zero usage must remain zero.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite $null 1024)
Assert-SSRTest ($null -eq $row.StorageUsageCurrentMB -and $null -eq $row.UtilizationPercent -and $row.ReadStatus -eq 'ReadWithMetricGaps') 'Missing usage must not become zero.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 100 0)
Assert-SSRTest ($null -eq $row.UtilizationPercent -and $null -eq $row.HeadroomToSiteQuotaGiB) 'Zero quota must not divide by zero or imply unlimited headroom.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 1100 1000)
Assert-SSRTest ($row.UtilizationStatus -eq 'OverSiteQuota' -and $row.HeadroomToSiteQuotaGiB -eq 0 -and $row.OverSiteQuotaGiB -gt 0) 'Over-quota handling failed.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 800 1000)
Assert-SSRTest ($row.UtilizationStatus -eq 'Warning') 'Warning boundary failed.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 900 1000)
Assert-SSRTest ($row.UtilizationStatus -eq 'Critical') 'Critical boundary failed.'
$row=ConvertTo-SSRRow Test (New-SSRTestSite 799.999 1000)
Assert-SSRTest ($row.UtilizationStatus -eq 'BelowWarningThreshold') 'Threshold must use unrounded ratio.'
foreach ($invalid in @(-1,'bad','',$false)) { Assert-SSRTest (-not (ConvertTo-SSRNumber $invalid).Valid) 'Invalid metric accepted.' }
$row=ConvertTo-SSRRow -Url Test -Settings $null -ErrorText 'Simulated read failure'
Assert-SSRTest ($row.ReadStatus -eq 'Error' -and $null -eq $row.UsedGiB) 'API failure must not imply empty storage.'
Assert-SSRTest ((ConvertTo-SSRUrl 'https://contoso.sharepoint.com/sites/Test/' 'contoso.sharepoint.com') -eq 'https://contoso.sharepoint.com/sites/Test') 'URL normalization failed.'
$failed=$false; try { $null=ConvertTo-SSRUrl 'https://other.sharepoint.com/sites/Test' 'contoso.sharepoint.com' } catch { $failed=$true }
Assert-SSRTest $failed 'Cross-host target accepted.'
$safe=ConvertTo-SSRSafeCsv ([pscustomobject]@{Title='=BAD()';Used=0})
Assert-SSRTest ($safe.Title.StartsWith("'=") -and $safe.Used -eq 0) 'CSV formula-prefix safety failed.'
$scriptText=[IO.File]::ReadAllText((Join-Path $root 'Scripts/SharePoint/Get-SharePointStorageReport.ps1'))
Assert-SSRTest ($scriptText.IndexOf('$PSCmdlet.ShouldProcess') -lt $scriptText.IndexOf('Get-M365OutputPath')) 'Dry-run guard must precede output.'
Assert-SSRTest (-not $scriptText.Contains('Set-PnP') -and -not $scriptText.Contains('Add-PnP') -and -not $scriptText.Contains('Remove-PnP')) 'Storage report must not mutate tenant.'
Write-Host 'SharePoint storage helper tests passed. Synthetic data only; no tenant calls.' -ForegroundColor Green
