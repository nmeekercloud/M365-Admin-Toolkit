[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.BulkGroupMembers.Helpers.ps1')
function Assert-BGMTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BGM-Tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
 $csv=Join-Path $temp 'test.csv'
 $id='11111111-1111-4111-8111-111111111111'
 [IO.File]::WriteAllText($csv,"GroupId,UserPrincipalName`n$id,test.user@contoso.com`n")
 $rows=@(Import-BGMCsv -LiteralPath $csv)
 Assert-BGMTest ($rows.Count -eq 1 -and $rows[0].Record -eq 2 -and $rows[0].GroupId -eq $id) 'Valid CSV parse failed.'
 [IO.File]::WriteAllText($csv,"UserPrincipalName,GroupId`n`"test.user@contoso.com`",`"$id`"`n")
 Assert-BGMTest (@(Import-BGMCsv -LiteralPath $csv).Count -eq 1) 'Reordered/quoted columns failed.'
 $cases=@(
  '',
  'GroupId,UserPrincipalName',
  "GroupId,UserPrincipalName`nBAD,test.user@contoso.com",
  "GroupId,UserPrincipalName`n$id,bad-user",
  "GroupId,UserPrincipalName`n$id,test.user@contoso.com,extra",
  "GroupId,GroupId`n$id,$id",
  "GroupId;UserPrincipalName`n$id;test.user@contoso.com"
 )
 foreach ($text in $cases) {
  [IO.File]::WriteAllText($csv,$text)
  $failed=$false; try { $null=@(Import-BGMCsv -LiteralPath $csv) } catch { $failed=$true }
  Assert-BGMTest $failed 'Malformed CSV should fail before tenant operations.'
 }
 [IO.File]::WriteAllText($csv,"GroupId,UserPrincipalName`n$id,test.user@contoso.com`n$id,test.other@contoso.com")
 $failed=$false; try { $null=@(Import-BGMCsv -LiteralPath $csv -MaxRows 1) } catch { $failed=$true }
 Assert-BGMTest $failed 'Row limit must reject entire file, not truncate.'
 $safe=ConvertTo-BGMCsvSafeRow ([pscustomobject]@{Group='=BAD()';Detail='plain'})
 Assert-BGMTest ($safe.Group.StartsWith("'=") -and $safe.Detail -eq 'plain') 'CSV formula-prefix safety failed.'
 $script:BGMCalls=0
 function Invoke-UMGraph {
  param($Path)
  $script:BGMCalls++
  if ($script:BGMCalls -eq 1) { return @{value=@(@{id=$id});'@odata.nextLink'='https://graph.microsoft.com/v1.0/users/22222222-2222-4222-8222-222222222222/memberOf/microsoft.graph.group?$skiptoken=next'} }
  return @{value=@(@{id=$id})}
 }
 try {
  $ids=@(Get-BGMDirectGroups -UserId '22222222-2222-4222-8222-222222222222')
  Assert-BGMTest ($ids.Count -eq 1 -and $script:BGMCalls -eq 2) 'Membership pagination/deduplication failed.'
 } finally { Remove-Item Function:Invoke-UMGraph -ErrorAction SilentlyContinue }
 $source=[IO.File]::ReadAllText((Join-Path $root 'Scripts/Groups/Add-BulkGroupMember.ps1'))
 Assert-BGMTest (-not $source.Contains('-Method DELETE')) 'Bulk add must not remove objects.'
 Assert-BGMTest ($source.IndexOf('Confirm-M365Action') -lt $source.IndexOf('-Method POST')) 'Approval must precede addition.'
 Assert-BGMTest ($source.IndexOf('$PSCmdlet.ShouldProcess') -lt $source.IndexOf('Save-UMJson')) 'Dry-run guard must precede backup creation.'
 Assert-BGMTest ($source.Contains("'Unverified'") -and $source.Contains("'NotRun'")) 'Fail-stop states missing.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Bulk group member local tests passed. No tenant calls or membership writes.' -ForegroundColor Green
