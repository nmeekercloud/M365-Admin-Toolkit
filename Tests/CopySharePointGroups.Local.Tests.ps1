[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.CopySharePointGroups.Helpers.ps1')
function Assert-CSTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
Assert-CSTest ((ConvertTo-CSUrl 'https://contoso.sharepoint.com/sites/Test/' 'contoso.sharepoint.com') -eq 'https://contoso.sharepoint.com/sites/Test') 'URL normalization failed.'
foreach ($url in @('http://contoso.sharepoint.com/sites/Test','https://other.sharepoint.com/sites/Test','https://contoso.sharepoint.com/sites/Test?x=1')) {
 $failed=$false; try { $null=ConvertTo-CSUrl $url 'contoso.sharepoint.com' } catch { $failed=$true }; Assert-CSTest $failed 'Unsafe site URL accepted.'
}
$plan=@([pscustomobject]@{Number=1;Status='Eligible'},[pscustomobject]@{Number=2;Status='Excluded'},[pscustomobject]@{Number=3;Status='AlreadyMember'})
Assert-CSTest (@(Select-CSRows $plan ALL).Count -eq 1) 'ALL must select eligible rows only.'
Assert-CSTest (@(Select-CSRows $plan '1,1').Count -eq 1) 'Selection must deduplicate.'
foreach ($bad in @('2','3','0','abc','999999999999999999999')) {
 $failed=$false; try { $null=@(Select-CSRows $plan $bad) } catch { $failed=$true }; Assert-CSTest $failed 'Ineligible selection accepted.'
}
$r=ConvertTo-CSCsvSafe ([pscustomobject]@{GroupName='=BAD()';Id=4})
Assert-CSTest ($r.GroupName.StartsWith("'=") -and $r.Id -eq 4) 'CSV formula-prefix safety failed.'
$script:CSCalls=0
function Get-PnPUser { param($Identity,$Connection); $script:CSCalls++; [pscustomobject]@{Id=7;LoginName=$Identity} }
try {
 $u=Get-CSSiteUser 'test.user@contoso.com' ([pscustomobject]@{})
 Assert-CSTest ($u.Id -eq 7 -and $u.LoginName -eq 'i:0#.f|membership|test.user@contoso.com' -and $script:CSCalls -eq 1) 'Existing site-user lookup failed.'
} finally { Remove-Item Function:Get-PnPUser -ErrorAction SilentlyContinue }
$source=[IO.File]::ReadAllText((Join-Path $root 'Scripts/SharePoint/Copy-SitePermissions.ps1'))
Assert-CSTest (-not $source.Contains('Ensure-PnPUser') -and -not $source.Contains('Remove-PnP')) 'Unexpected provisioning/deletion operation.'
Assert-CSTest ($source.IndexOf('Confirm-M365Action') -lt $source.IndexOf('Add-PnPGroupMember')) 'Confirmation must precede add.'
Assert-CSTest ($source.IndexOf('$PSCmdlet.ShouldProcess') -lt $source.IndexOf('Get-M365OutputPath')) 'WhatIf guard must precede output creation.'
Write-Host 'SharePoint copy helper tests passed. Synthetic/mocked reads only; no tenant writes.' -ForegroundColor Green
