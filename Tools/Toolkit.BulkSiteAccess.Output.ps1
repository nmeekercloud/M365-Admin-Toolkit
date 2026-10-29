# Definitions only. Result export is separate from required pre-change backups.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Show-ToolkitBulkSiteAccessResult {
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
       [string]$TenantId,[string]$ExportDirectory,[string]$ReportName,
       [switch]$NoInteractive,[switch]$PreviewOnly)
 Show-M365Results -InputObject $Results -Title 'Bulk SharePoint membership results' -NoPaging:$NoInteractive
 if ($PreviewOnly) {
  Write-Host 'WhatIf: no membership additions, backup or result export written.'
  return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null}
 }
 if (-not $Results.Count) { return [pscustomobject]@{Status='NoResults';ReportFolder=$null;Error=$null} }
 $manifest=[ordered]@{
  TaskId='sharepoint.grant-bulksiteaccess';TenantId=$TenantId
  Status='ResultSummary';FinishedUtc=[datetime]::UtcNow.ToString('o')
  Rows=$Results.Count
  Successful=@($Results | Where-Object Result -eq 'Success').Count
  Failed=@($Results | Where-Object Result -eq 'Failed').Count
  Unverified=@($Results | Where-Object Result -eq 'Unverified').Count
  NotRun=@($Results | Where-Object Result -eq 'NotRun').Count
  Notes=@('ResultSummary is not a claim that all membership additions succeeded. Inspect each row.','Pre-change safety backups are independent of optional result export.','Unverified additions require inspection before rerunning; export does not retry changes.')
 }
 $columns=@('Record','SiteUrl','WebId','SharePointGroupId','GroupName','UserPrincipalName','UserId','Result','Detail')
 Export-ToolkitReportBundle -Tables @{'Results.csv'=$Results} -Manifest $manifest -Columns @{'Results.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
}
