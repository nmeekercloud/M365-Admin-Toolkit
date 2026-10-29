#Requires -Version 7.4
# READ-ONLY TASK TEMPLATE
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param()
$ErrorActionPreference='Stop'
$definition=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '__TASK_META__')
if ($definition.Status -ne 'Ready') { throw 'Task is not Ready. Implement and test before enabling.' }
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Get-Module M365Toolkit.Core)) {
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
}
$access=if ($definition.ContainsKey('AccessMode')) { $definition.AccessMode } else { 'Changes' }
Assert-M365TaskAccess -AccessMode $access -TaskId $definition.Id
$tenant=Assert-M365Connection -Service $definition.Services -GraphScopes $definition.GraphScopes
Write-M365Log -Message ('Starting task: '+$definition.Id) -Level Info
# Implement read-only queries here. Keep raw objects separate from formatted display.
# Change tasks must build a plan, Confirm-M365Action, back up, then use ShouldProcess.
throw 'Scaffold only: replace this throw with tested task logic before enabling.'
# $results | Format-Table -AutoSize
# Export-M365Csv -InputObject @($results) -ReportName $definition.Id
