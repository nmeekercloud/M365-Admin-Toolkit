# Definitions only. Export fixed metadata columns, never raw sharing/token responses.
. (Join-Path $PSScriptRoot 'Toolkit.ReportBundle.ps1')
function Invoke-OD18Output {
 [CmdletBinding()]
 param([Parameter(Mandatory)][hashtable]$Tables,[Parameter(Mandatory)][hashtable]$Columns,
       [Parameter(Mandatory)][Collections.IDictionary]$Manifest,
       [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PreviewOnly)
 foreach ($name in $Tables.Keys) {
  if (-not $Columns.ContainsKey($name) -or -not @($Columns[$name]).Count) { throw 'Explicit safe columns required for every OneDrive table.' }
  foreach ($column in $Columns[$name]) {
   if ($column -imatch '^(SharingUrl|LinkUrl|WebUrl|AccessToken|Token|ShareId)$') { throw 'Sensitive sharing/token columns cannot be exported.' }
  }
 }
 $serialized=$Manifest | ConvertTo-Json -Depth 12
 if ($serialized -imatch '"(SharingUrl|LinkUrl|WebUrl|AccessToken|Token|ShareId)"\s*:') { throw 'Sensitive sharing/token metadata cannot be exported.' }
 foreach ($name in @($Tables.Keys | Sort-Object)) {
  $raw=$Tables[$name]
  $rows=@(if ($raw -is [Collections.Generic.List[object]]) { $raw.ToArray() } else { @($raw) })
  Show-M365Results -InputObject @($rows | Select-Object -Property $Columns[$name]) -Title ('OneDrive '+$name) -NoPaging:$NoInteractive
 }
 [pscustomobject]$Manifest | Format-List | Out-Host
 if ($PreviewOnly) { Write-Host 'Preview: no result export written.';return [pscustomobject]@{Status='PreviewOnly';ReportFolder=$null;Error=$null} }
 Export-ToolkitReportBundle -Tables $Tables -Manifest $Manifest -Columns $Columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
}
function Complete-OD18ArchiveStep {
 param([string]$Action,[string]$Target,[string]$Status='Success',[switch]$PassThru,[string]$Detail='')
 $row=Complete-WFStep -Action $Action -Target $Target -Status $Status -Detail $Detail -PassThru
 if ($WorkflowApproval -or $PlanOnly) { if ($PassThru) {$row};return }
 $export=Invoke-OD18Output -Tables @{'Outcome.csv'=@($row)} -Columns @{'Outcome.csv'=@('Action','Target','Status','Detail')} -Manifest @{Task='onedrive.backup-onedrive';Status=$Status;Scope='Move completion summary only; operational recovery journals remain separate';Notes=@('A Success outcome is not a full-fidelity backup/compliance certification.','Optional export does not replace archive journals, pre-change snapshots or cleanup evidence.')} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:($WhatIfPreference -or $Status -eq 'Planned')
 Write-Host ('Result export: '+$export.Status)
 if ($PassThru) {$row}
}
