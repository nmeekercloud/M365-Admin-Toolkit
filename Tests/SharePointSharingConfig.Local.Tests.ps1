#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.SharePointSharingConfig.Helpers.ps1')
function Assert-ESCTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
Assert-ESCTest ((Get-ESCCapabilityCeiling ExternalUserAndGuestSharing Disabled) -eq 'Disabled') 'Site restriction must win.'
Assert-ESCTest ((Get-ESCCapabilityCeiling ExistingExternalUserSharingOnly ExternalUserAndGuestSharing) -eq 'ExistingExternalUserSharingOnly') 'Tenant restriction must win.'
Assert-ESCTest ((Get-ESCCapabilityCeiling Bad ExternalUserSharingOnly) -eq 'Unknown / unavailable') 'Unknown tenant must remain unknown.'
Assert-ESCTest ((Get-ESCCapabilityLabel Disabled) -eq 'Only people in your organization') 'Capability mapping failed.'
$field=Get-ESCField ([pscustomobject]@{Enabled=$false;Count=0}) Enabled
Assert-ESCTest ($field.Available -and $field.Value -eq $false) 'False must not mean unavailable.'
$field=Get-ESCField ([pscustomobject]@{Count=0}) Count
Assert-ESCTest ($field.Available -and $field.Value -eq 0) 'Zero must not mean unavailable.'
$field=Get-ESCField ([pscustomobject]@{}) Absent
Assert-ESCTest (-not $field.Available -and $null -eq $field.Value) 'Absent property should be unavailable.'
$row=New-ESCSettingsRow -Scope Site -Url 'https://contoso.sharepoint.com/sites/Test' -Settings ([pscustomobject]@{SharingCapability='Disabled'}) -Fields @('SharingCapability','Missing')
Assert-ESCTest ($row.ReadStatus -eq 'ReadWithUnavailableFields' -and $row.UnavailableProperties -eq 'Missing') 'Missing optional fields not recorded.'
$row=New-ESCSettingsRow -Scope Site -Url Test -Settings $null -Fields @('SharingCapability') -ErrorText 'Simulated read error'
Assert-ESCTest ($row.ReadStatus -eq 'Error' -and $row.SharingCapabilityLabel -eq 'Unknown / unavailable') 'Read error must not imply disabled sharing.'
Assert-ESCTest ((ConvertTo-ESCUrl 'https://contoso.sharepoint.com/sites/Test/' 'contoso.sharepoint.com') -eq 'https://contoso.sharepoint.com/sites/Test') 'URL normalization failed.'
$failed=$false; try { $null=ConvertTo-ESCUrl 'https://other.sharepoint.com/sites/Test' 'contoso.sharepoint.com' } catch { $failed=$true }
Assert-ESCTest $failed 'Cross-host target accepted.'
$safe=ConvertTo-ESCSafeCsv ([pscustomobject]@{Name='=BAD()';Enabled=$false})
Assert-ESCTest ($safe.Name.StartsWith("'=") -and $safe.Enabled -eq $false) 'CSV text safety failed.'
$scriptText=[IO.File]::ReadAllText((Join-Path $root 'Scripts/SharePoint/Get-SharePointExternalSharingConfig.ps1'))
Assert-ESCTest ($scriptText.IndexOf('$PSCmdlet.ShouldProcess') -lt $scriptText.IndexOf('Get-M365OutputPath')) 'Dry-run guard must precede report creation.'
Assert-ESCTest (-not $scriptText.Contains('Set-PnP') -and -not $scriptText.Contains('Add-PnP') -and -not $scriptText.Contains('Remove-PnP')) 'Report must not modify settings.'
Write-Host 'Sharing configuration helper tests passed. Synthetic data only; no tenant calls.' -ForegroundColor Green
