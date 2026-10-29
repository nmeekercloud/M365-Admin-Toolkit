# Definitions only. Optional result export is independent of required safety backups.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Show-ToolkitCopyGroupMembershipResult {
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
       [string]$TenantId,[string]$ExportDirectory,[string]$ReportName,
       [switch]$NoInteractive,[switch]$PreviewOnly)
 Show-M365Results -InputObject $Results -Title 'Copied direct group membership results' -NoPaging:$NoInteractive
 if ($PreviewOnly) {
  Write-Host 'WhatIf: no membership changes, backups or result export written.'
  return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null}
 }
 if (-not $Results.Count) { return [pscustomobject]@{Status='NoResults';ReportFolder=$null;Error=$null} }
 $manifest=[ordered]@{
  TaskId='groups.copy-groupmemberships';TenantId=$TenantId
  Status='ResultSummary';FinishedUtc=[datetime]::UtcNow.ToString('o');Rows=$Results.Count
  Successful=@($Results | Where-Object Result -eq 'Success').Count
  Failed=@($Results | Where-Object Result -eq 'Failed').Count
  Unverified=@($Results | Where-Object Result -eq 'Unverified').Count
  NotRun=@($Results | Where-Object Result -eq 'Not run').Count
  AlreadyMember=@($Results | Where-Object Result -eq 'AlreadyMember').Count
  Planned=@($Results | Where-Object Result -eq 'Planned').Count
  Notes=@('ResultSummary is not a claim that all additions succeeded. Inspect row Result values.','Only selected eligible direct group memberships are copied; not ownership, effective access, directory roles, PIM or mailbox/site permissions.','Required pre-change backups remain independent of optional result export.','Inspect Unverified additions before rerunning. Export never retries membership changes.')
 }
 $columns=@('Group','GroupId','Target','Result','Detail')
 Export-ToolkitReportBundle -Tables @{'Results.csv'=$Results} -Manifest $manifest -Columns @{'Results.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
}
