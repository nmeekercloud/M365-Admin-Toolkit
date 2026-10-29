# Definitions only. Standalone output is separate from backups and workflow approval.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Show-EX17Output {
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
       [Parameter(Mandatory)][string[]]$Columns,[string]$Label='ExchangeResult',
       [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,
       [switch]$PreviewOnly,[switch]$PassThru,[Collections.IDictionary]$Metadata=@{})
 Show-M365Results -InputObject @($Rows | Select-Object -Property $Columns) -Title $Label -NoPaging:$NoInteractive
 if ($PreviewOnly) { Write-Host 'Preview/cancelled output: no result files saved.' }
 else {
  $manifest=[ordered]@{Task=$Label;Status='OutcomeSummary';FinishedUtc=[datetime]::UtcNow.ToString('o');Rows=$Rows.Count;Notes=@('OutcomeSummary is not a claim of successful changes; inspect individual Result/Status and Error/Detail values.','Required pre-change snapshots are independent of optional result export.','Export never retries mutations or converts uncertain outcomes into success.')}
  foreach ($key in $Metadata.Keys) { if ($manifest.Contains($key)) { throw ('Reserved metadata key: '+$key) };$manifest[$key]=$Metadata[$key] }
  $export=Export-ToolkitReportBundle -Tables @{'Results.csv'=$Rows} -Manifest $manifest -Columns @{'Results.csv'=$Columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
  Write-Host ('Result export: '+$export.Status)
 }
 if ($PassThru) { $Rows }
}
function Write-EX17Results {
 param([object[]]$Results,[string]$Label,[switch]$PassThru)
 Show-EX17Output -Rows @($Results) -Columns @('Mailbox','Delegate','Right','Result','Error') -Label $Label -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference -PassThru:$PassThru
}
function Complete-EX17Step {
 param([string]$Action,[string]$Target,[string]$Status='Success',[switch]$PassThru,[string]$Detail='')
 $row=Complete-WFStep -Action $Action -Target $Target -Status $Status -Detail $Detail -PassThru
 # Approved offboarding/plan execution must retain the original return contract and never prompt for exports.
 if ($WorkflowApproval -or $PlanOnly) { if ($PassThru) { $row };return }
 Show-EX17Output -Rows @($row) -Columns @('Action','Target','Status','Detail') -Label $Action -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:($WhatIfPreference -or $Status -in @('Planned','Cancelled')) -PassThru:$PassThru
}
