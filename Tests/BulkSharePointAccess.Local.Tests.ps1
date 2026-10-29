#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.BulkSharePointAccess.Helpers.ps1')
function Assert-BSATest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BSA-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
 $csv=Join-Path $temp 'test.csv'
 $url='https://contoso.sharepoint.com/sites/Test'
 [IO.File]::WriteAllText($csv,"SiteUrl,SharePointGroupId,UserPrincipalName`n$url,7,test.user@contoso.com`n")
 $rows=@(Import-BSACsv -LiteralPath $csv)
 Assert-BSATest ($rows.Count -eq 1 -and $rows[0].Record -eq 2 -and $rows[0].SharePointGroupId -eq 7) 'Valid CSV failed.'
 [IO.File]::WriteAllText($csv,"UserPrincipalName,SiteUrl,SharePointGroupId`n`"test.user@contoso.com`",`"$url/`",7")
 Assert-BSATest (@(Import-BSACsv -LiteralPath $csv)[0].SiteUrl -eq $url) 'Quoted/reordered columns failed.'
 $badCases=@('', 'SiteUrl,SharePointGroupId,UserPrincipalName',
  "SiteUrl,SharePointGroupId,UserPrincipalName`n$url,0,test.user@contoso.com",
  "SiteUrl,SharePointGroupId,UserPrincipalName`n$url,11111111-1111-4111-8111-111111111111,test.user@contoso.com",
  "SiteUrl,SharePointGroupId,UserPrincipalName`n$url,7,bad-upn",
  "SiteUrl,SharePointGroupId,UserPrincipalName`n$url,7,test.user@contoso.com,extra",
  "SiteUrl,SiteUrl,UserPrincipalName`n$url,$url,test.user@contoso.com",
  "SiteUrl,SharePointGroupId,UserPrincipalName`nhttp://contoso.sharepoint.com/sites/Test,7,test.user@contoso.com")
 foreach ($text in $badCases) {
  [IO.File]::WriteAllText($csv,$text)
  $failed=$false; try { $null=@(Import-BSACsv -LiteralPath $csv) } catch { $failed=$true }
  Assert-BSATest $failed 'Malformed CSV must fail.'
 }
 [IO.File]::WriteAllText($csv,"SiteUrl,SharePointGroupId,UserPrincipalName`n$url,7,test.user@contoso.com`n$url,7,test.other@contoso.com")
 $failed=$false; try { $null=@(Import-BSACsv -LiteralPath $csv -MaxRows 1) } catch { $failed=$true }
 Assert-BSATest $failed 'Row limit must reject entire CSV.'
 $failed=$false; try { $null=ConvertTo-BSAUrl 'https://other.sharepoint.com/sites/Test' 'contoso.sharepoint.com' } catch { $failed=$true }
 Assert-BSATest $failed 'Cross-host URL accepted.'
 Assert-BSATest ((Get-BSARowState 7 7 $false $false) -eq 'OwnersExcluded') 'Owners exclusion failed.'
 Assert-BSATest ((Get-BSARowState 7 8 $true $false) -eq 'Duplicate') 'Duplicate state failed.'
 Assert-BSATest ((Get-BSARowState 7 8 $false $true) -eq 'AlreadyMember') 'Existing membership state failed.'
 Assert-BSATest ((Get-BSARowState 7 8 $false $false) -eq 'Eligible') 'Eligible state failed.'
 $safe=ConvertTo-BSASafeCsv ([pscustomobject]@{Name='=BAD()';Id=7})
 Assert-BSATest ($safe.Name.StartsWith("'=") -and $safe.Id -eq 7) 'CSV text safety failed.'
 $script:BSATestCalls=0
 function Get-PnPUser { param($Identity,$Connection); $script:BSATestCalls++; [pscustomobject]@{Id=9;LoginName=$Identity} }
 try { $u=Get-BSASiteUser 'test.user@contoso.com' ([pscustomobject]@{}); Assert-BSATest ($u.Id -eq 9 -and $script:BSATestCalls -eq 1) 'Read-only existing site-user lookup failed.' }
 finally { Remove-Item Function:Get-PnPUser -ErrorAction SilentlyContinue }
 $source=[IO.File]::ReadAllText((Join-Path $root 'Scripts/SharePoint/Grant-BulkSiteAccess.ps1'))
 Assert-BSATest (-not $source.Contains('Ensure-PnPUser') -and -not $source.Contains('Remove-PnP')) 'Unexpected provisioning/deletion.'
 Assert-BSATest ($source.IndexOf('Import-BSACsv') -lt $source.IndexOf('Assert-M365Connection')) 'CSV must parse before auth.'
 Assert-BSATest ($source.IndexOf('Confirm-M365Action') -lt $source.IndexOf('Add-PnPGroupMember')) 'Approval must precede add.'
 Assert-BSATest ($source.IndexOf('$PSCmdlet.ShouldProcess') -lt $source.IndexOf('Get-M365OutputPath')) 'WhatIf guard must precede output creation.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Bulk SharePoint access helper tests passed. No tenant calls/writes.' -ForegroundColor Green
