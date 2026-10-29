# Definitions only. Optional result export does not replace the pre-change backup.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Show-ToolkitBulkGroupMemberResult {
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
       [string]$TenantId,[string]$ExportDirectory,[string]$ReportName,
       [switch]$NoInteractive,[switch]$PreviewOnly)
 Show-M365Results -InputObject $Results -Title 'Bulk direct group membership results' -NoPaging:$NoInteractive
 if ($PreviewOnly) {
  Write-Host 'WhatIf: no membership changes, backup or result export written.'
  return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null}
 }
 if (-not $Results.Count) { return [pscustomobject]@{Status='NoResults';ReportFolder=$null;Error=$null} }
 $manifest=[ordered]@{
  TaskId='groups.add-bulkgroupmember';TenantId=$TenantId
  Status='ResultSummary';FinishedUtc=[datetime]::UtcNow.ToString('o');Rows=$Results.Count
  Successful=@($Results | Where-Object Result -eq 'Success').Count
  Failed=@($Results | Where-Object Result -eq 'Failed').Count
  Unverified=@($Results | Where-Object Result -eq 'Unverified').Count
  NotRun=@($Results | Where-Object Result -eq 'NotRun').Count
  Unsupported=@($Results | Where-Object Result -eq 'Unsupported').Count
  Duplicate=@($Results | Where-Object Result -eq 'Duplicate').Count
  AlreadyMember=@($Results | Where-Object Result -eq 'AlreadyMember').Count
  Planned=@($Results | Where-Object Result -eq 'Planned').Count
  Notes=@('ResultSummary is not a claim that all additions succeeded; inspect each Result.','Only eligible direct membership additions; no removals, ownership or role assignments.','Required pre-change backups are independent of optional result export.','Unverified additions require inspection before rerunning; export never retries writes.')
 }
 $columns=@('Record','Group','GroupId','UserPrincipalName','UserId','Result','Detail')
 Export-ToolkitReportBundle -Tables @{'Results.csv'=$Results} -Manifest $manifest -Columns @{'Results.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
}
