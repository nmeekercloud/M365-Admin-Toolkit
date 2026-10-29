# Definitions only. Optional result export never replaces the pre-change backup.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Show-ToolkitCopySitePermissionsResult {
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
       [string]$TenantId,[string]$ExportDirectory,[string]$ReportName,
       [switch]$NoInteractive,[switch]$PreviewOnly)
 Show-M365Results -InputObject $Results -Title 'Copied SharePoint group membership results' -NoPaging:$NoInteractive
 if ($PreviewOnly) {
  Write-Host 'WhatIf: no membership additions, backups or result export written.'
  return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null}
 }
 if (-not $Results.Count) { return [pscustomobject]@{Status='NoResults';ReportFolder=$null;Error=$null} }
 $manifest=[ordered]@{
  TaskId='sharepoint.copy-sitepermissions';TenantId=$TenantId
  Status='ResultSummary';FinishedUtc=[datetime]::UtcNow.ToString('o');Rows=$Results.Count
  Successful=@($Results | Where-Object Result -eq 'Success').Count
  Failed=@($Results | Where-Object Result -eq 'Failed').Count
  Unverified=@($Results | Where-Object Result -eq 'Unverified').Count
  NotRun=@($Results | Where-Object Result -eq 'NotRun').Count
  AlreadyMember=@($Results | Where-Object Result -eq 'AlreadyMember').Count
  Planned=@($Results | Where-Object Result -eq 'Planned').Count
  Notes=@('ResultSummary is not a claim that all additions succeeded. Inspect row Result values.','Only selected direct SharePoint group memberships are copied, not full permissions or effective access.','Required pre-change backups remain independent of optional result export.','Inspect Unverified additions before rerunning. Export does not retry membership changes.')
 }
 $columns=@('SiteUrl','GroupId','GroupName','Target','Result','Detail')
 Export-ToolkitReportBundle -Tables @{'Results.csv'=$Results} -Manifest $manifest -Columns @{'Results.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
}
