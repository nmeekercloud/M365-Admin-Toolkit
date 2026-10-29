#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.OneDriveSharingStorage.Helpers.ps1')
function Assert-OD34Test([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
$body=New-OD34LinkBody -Scope Organization -LinkType View -ExpiresUtc ([datetimeoffset]::UtcNow.AddDays(7))
Assert-OD34Test ($body.scope -eq 'organization' -and $body.type -eq 'view' -and $body.retainInheritedPermissions -eq $true) 'Safe sharing-body defaults failed.'
$body=New-OD34LinkBody -Scope Anonymous -LinkType Edit -ExpiresUtc ([datetimeoffset]::UtcNow.AddDays(1))
Assert-OD34Test ($body.scope -eq 'anonymous' -and $body.type -eq 'edit') 'Explicit anonymous/edit body failed.'
$failed=$false;try {$null=New-OD34LinkBody Organization View ([datetimeoffset]::UtcNow.AddDays(-1))} catch {$failed=$true};Assert-OD34Test $failed 'Expired link request accepted.'
Assert-OD34Test ((ConvertTo-OD34RelativePath 'HR/Handbook.docx') -eq 'HR/Handbook.docx') 'Relative path failed.'
foreach ($path in @('../Other.docx','/Documents/File.docx','https://contoso.sharepoint.com/file','HR//File.docx')) {$failed=$false;try {$null=ConvertTo-OD34RelativePath $path} catch {$failed=$true};Assert-OD34Test $failed 'Unsafe path accepted.'}
$item=@{id='synthetic-item';folder=@{};parentReference=@{driveId='synthetic-drive'}}
Assert-OD34Item -Item $item -DriveId 'synthetic-drive'
$item.root=@{};$failed=$false;try {Assert-OD34Item $item 'synthetic-drive'} catch {$failed=$true};Assert-OD34Test $failed 'Drive-root sharing accepted.';$item.Remove('root')
$item.remoteItem=@{};$failed=$false;try {Assert-OD34Item $item 'synthetic-drive'} catch {$failed=$true};Assert-OD34Test $failed 'Shortcut sharing accepted.'
$owner=@{id='11111111-1111-4111-8111-111111111111';userPrincipalName='test.user@contoso.com'}
$site=@{Url='https://contoso-my.sharepoint.com/personal/test';Details=@{StorageUsageCurrent=512;StorageQuota=1024;LockState='Unlock'}}
$row=New-OD34StorageRow $owner $site
Assert-OD34Test ($row.UsedGiB -eq 0.5 -and $row.QuotaGiB -eq 1 -and $row.UtilizationPercent -eq 50 -and $row.RemainingToSiteQuotaGiB -eq 0.5) 'Storage math failed.'
$site.Details.StorageUsageCurrent=0;$row=New-OD34StorageRow $owner $site;Assert-OD34Test ($row.UsedGiB -eq 0 -and $row.UtilizationPercent -eq 0) 'Real zero lost.'
$site.Details.StorageUsageCurrent=$null;$row=New-OD34StorageRow $owner $site;Assert-OD34Test ($null -eq $row.UsedGiB -and $row.Status -eq 'PartialMetricCoverage') 'Missing metric became zero.'
$site.Details.StorageUsageCurrent=2048;$row=New-OD34StorageRow $owner $site;Assert-OD34Test ($row.OverQuotaGiB -eq 1 -and $row.RemainingToSiteQuotaGiB -eq 0) 'Over-quota math failed.'
$site.Details.StorageQuota=0;$row=New-OD34StorageRow $owner $site;Assert-OD34Test ($null -eq $row.UtilizationPercent) 'Zero quota divides by zero.'
$link=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/New-OneDriveSharingLink.ps1'))
$storage=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Get-OneDriveStorage.ps1'))
Assert-OD34Test ($link.IndexOf('Confirm-M365Action') -lt $link.IndexOf('-Method POST')) 'Approval must precede createLink.'
Assert-OD34Test ($link.IndexOf('$PSCmdlet.ShouldProcess') -lt $link.IndexOf('Get-M365OutputPath')) 'WhatIf must precede backup/output.'
Assert-OD34Test (-not $storage.Contains('-Method POST') -and -not $storage.Contains('Set-PnP') -and -not $storage.Contains('Add-PnP')) 'Storage must be read-only.'
Assert-OD34Test ($link.IndexOf('$result | ConvertTo-Json') -lt $link.IndexOf("-NotePropertyName SharingUrl")) 'Sensitive URL must not enter result file.'
Write-Host 'OneDrive sharing/storage helper tests passed. Synthetic data; no tenant calls.' -ForegroundColor Green
