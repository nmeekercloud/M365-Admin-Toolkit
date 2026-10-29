#Requires -Version 7.4
<# .SYNOPSIS
View/export existing OneDrive personal-site storage; no provisioning or quota changes.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$ExportCsv,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Noninteractive export requires both ExportDirectory and ReportName.'}
if ($NoInteractive -and $ExportCsv -and -not ($ExportDirectory -and $ReportName)) {throw 'Noninteractive ExportCsv requires ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveOutput.ps1')
if (-not $UserPrincipalName) {
 if ($NoInteractive) {throw 'UserPrincipalName required.'}
 $UserPrincipalName=([string](Read-Host 'OneDrive owner UPN (Enter cancels)')).Trim();if (-not $UserPrincipalName) {return}
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.OneDriveSharingStorage.Helpers.ps1')
$tenant=Initialize-OD34Task $root 'onedrive.get-onedrivestorage' ReadOnly
$owner=Get-ODPUser $UserPrincipalName
$personal=Resolve-OD34PersonalSite $tenant $owner
$row=New-OD34StorageRow -Owner $owner -PersonalSite $personal
Write-Host 'Used/quota are service-reported binary MB; remaining is to this site quota, not tenant free storage. Telemetry can lag.' -ForegroundColor Yellow
if ($row.Status -ne 'ReadSucceeded') {Write-Warning 'One or more usage/quota metrics unavailable or quota not positive; missing values are not zero.'}
$export=Invoke-OD18Output -Tables @{'Storage.csv'=@($row)} -Columns @{'Storage.csv'=@('OwnerUPN','OwnerId','OneDriveUrl','ReadUtc','Status','StorageUsedMB','QuotaMB','UsedGiB','QuotaGiB','RemainingToSiteQuotaGiB','OverQuotaGiB','UtilizationPercent','LockState','Notes')} -Manifest @{Task='onedrive.get-onedrivestorage';TenantId=$tenant.TenantId;Status=$row.Status;Scope='Existing personal-site storage; site quota is not tenant free capacity';Notes=$row.Notes} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
Write-Host ('Result export: '+$export.Status)
if ($WhatIfPreference) {Write-Host 'WhatIf: reads performed; no export files written.'}
Write-M365Log -Message ('OneDrive storage read status: '+$row.Status) -Level Info -Quiet
if ($PassThru) {$row}
