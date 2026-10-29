# Definitions only. Output controls never authorize or replay account changes.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Invoke-UT19Output {
 [CmdletBinding()]
 param([Parameter(Mandatory)][hashtable]$Tables,[Parameter(Mandatory)][hashtable]$Columns,
       [Parameter(Mandatory)][Collections.IDictionary]$Manifest,
       [string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt,[switch]$PreviewOnly)
 foreach ($name in $Tables.Keys) {
  if (-not $Columns.ContainsKey($name) -or -not @($Columns[$name]).Count) {throw 'Explicit output columns required.'}
  foreach ($column in $Columns[$name]) {if ($column -imatch 'password|secret|token|credential') {throw 'Sensitive credential columns are not allowed in result exports.'}}
 }
 $json=$Manifest | ConvertTo-Json -Depth 12
 if ($json -imatch '"[^"\r\n]*(password|secret|token|credential)[^"\r\n]*"\s*:') {throw 'Sensitive credential metadata is not allowed in result exports.'}
 foreach ($name in @($Tables.Keys | Sort-Object)) {
  $raw=$Tables[$name]
  $rows=@(if ($raw -is [Collections.Generic.List[object]]) {$raw.ToArray()} else {@($raw)})
  Show-M365Results -InputObject @($rows | Select-Object -Property $Columns[$name]) -Title ([string]$Manifest.Task+' / '+$name) -NoPaging:$NoOutputPrompt
 }
 if ($PreviewOnly) {Write-Host 'Preview: no optional result files saved.';return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null}}
 Export-ToolkitReportBundle -Tables $Tables -Manifest $Manifest -Columns $Columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoOutputPrompt
}
function Write-UT19Results {
 param([object[]]$Results,[string]$Label)
 if ($UT19State) {$UT19State.ResultsShown=$true}
 $allowed=@('Target','Action','Result','Error','Detail','Step','StepId','Product','SkuId','Group')
 $columns=@($allowed | Where-Object {$name=$_;@($Results | Where-Object {$_.PSObject.Properties[$name]}).Count -gt 0})
 if (-not $columns.Count) {$columns=@('Target','Action','Result','Error')}
 if ($WorkflowApproval -or $PlanOnly) {
  Show-M365Results -InputObject @($Results | Select-Object -Property $columns) -Title $Label -NoPaging
  return
 }
 $export=Invoke-UT19Output -Tables @{'Results.csv'=@($Results)} -Columns @{'Results.csv'=$columns} -Manifest @{Task=$Label;Status='OutcomeSummary';Rows=@($Results).Count;Notes=@('Inspect individual Result/Detail/Error; export success does not verify account changes.','Required backups and checkpoints remain separate.','No credentials or request bodies are included by this output schema.')} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoOutputPrompt:$NoOutputPrompt -PreviewOnly:$WhatIfPreference
 Write-Host ('Result export: '+$export.Status)
}
function Complete-UT19Step {
 param([string]$Action,[string]$Target,[string]$Status='Success',[switch]$PassThru,[string]$Detail='')
 $row=Complete-WFStep -Action $Action -Target $Target -Status $Status -Detail $Detail -PassThru
 if ($WorkflowApproval -or $PlanOnly -or ($UT19State -and $UT19State.ResultsShown)) {if ($PassThru) {$row};return}
 $export=Invoke-UT19Output -Tables @{'Outcome.csv'=@($row)} -Columns @{'Outcome.csv'=@('Action','Target','Status','Detail')} -Manifest @{Task=$Action;Status='OutcomeSummary';Outcome=$Status;Notes='Original completion status retained; optional report does not replace required backups or verification.'} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoOutputPrompt:$NoOutputPrompt -PreviewOnly:($WhatIfPreference -or $Status -in @('Planned','Cancelled'))
 Write-Host ('Result export: '+$export.Status)
 if ($PassThru) {$row}
}
