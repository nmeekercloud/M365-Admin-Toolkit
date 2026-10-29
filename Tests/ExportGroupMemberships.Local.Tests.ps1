[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.ExportGroupMemberships.Helpers.ps1')
function Assert-EGTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$group=@{id='11111111-1111-4111-8111-111111111111';displayName='Test Group';mail='test.group@contoso.com';groupTypes=@('Unified');mailEnabled=$true;securityEnabled=$false}
$member=@{id='22222222-2222-4222-8222-222222222222';'@odata.type'='#microsoft.graph.user';displayName='Test User';userPrincipalName='test.user@contoso.com'}
$limited=@{id='33333333-3333-4333-8333-333333333333';'@odata.type'='#microsoft.graph.device'}
Assert-EGTest ((Get-EGType $group) -eq 'Microsoft 365') 'Group classification failed.'
$row=ConvertTo-EGMember -Group $group -Member $member
Assert-EGTest ($row.GroupId -eq $group.id -and $row.MembershipScope -eq 'Direct') 'Member context missing.'
$row=ConvertTo-EGMember -Group $group -Member $limited
Assert-EGTest ($row.ObjectId -eq $limited.id -and $row.Information -eq 'Limited information returned') 'Limited object lost.'
$safe=ConvertTo-EGSafeCsv ([pscustomobject]@{GroupName='=BAD()';Count=0})
Assert-EGTest ($safe.GroupName.StartsWith("'=") -and $safe.Count -eq 0) 'CSV formula-prefix safety failed.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('EGTest-'+[guid]::NewGuid().ToString('N')+'.csv')
try {
 Initialize-EGCsv -LiteralPath $temp -Columns @('Id','Name')
 Assert-EGTest ([IO.File]::ReadAllText($temp).Trim() -eq '"Id","Name"') 'Header-only CSV invalid.'
 [pscustomobject]@{Id='test';Name='value'} | Export-Csv -LiteralPath $temp -Append -NoTypeInformation -Encoding utf8
 Assert-EGTest (@(Import-Csv -LiteralPath $temp).Count -eq 1) 'Appending to header-only CSV failed.'
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
$script:EGMode='Pages'; $script:EGCalls=0
$path='/v1.0/groups/'+$group.id+'/members'; $uri='https://graph.microsoft.com'+$path
$script:EGBaseUri=$uri
function Invoke-MgGraphRequest {
 param($Method,$Uri,$OutputType)
 if ($Method -ne 'GET') { throw 'Unexpected Graph write.' }
 $script:EGCalls++
 if ($script:EGCalls -gt 4) { throw 'Mock call safety limit exceeded; pagination did not terminate.' }
 switch ($script:EGMode) {
  'Pages' { if ($script:EGCalls -eq 1) { return @{value=@($member);'@odata.nextLink'=($script:EGBaseUri+'?$skiptoken=next')} }; return @{value=@($limited,$member)} }
  'Empty' { return @{value=@()} }
  'Cycle' { return @{value=@($member);'@odata.nextLink'=($script:EGBaseUri+'?$skiptoken=cycle')} }
  'External' { return @{value=@();'@odata.nextLink'='https://example.invalid/steal'} }
  'Failure' { if ($script:EGCalls -eq 1) { return @{value=@($member);'@odata.nextLink'=($script:EGBaseUri+'?$skiptoken=fail')} }; throw 'Simulated read failure' }
 }
}
try {
 $rows=@(Get-EGCollection -Uri $uri -ExpectedPath $path)
 Assert-EGTest ($rows.Count -eq 2 -and $script:EGCalls -eq 2) 'Pagination/deduplication failed.'
 foreach ($mode in @('Cycle','External','Failure')) {
  $script:EGMode=$mode; $script:EGCalls=0; $failed=$false
  try { $null=@(Get-EGCollection -Uri $uri -ExpectedPath $path) } catch { $failed=$true }
  Assert-EGTest $failed ('Expected guarded failure: '+$mode)
  if ($mode -eq 'Cycle') { Assert-EGTest ($script:EGCalls -eq 2) 'Cycle guard must reject a repeated URL after exactly two mocked requests.' }
 }
 $script:EGMode='Empty'
 Assert-EGTest (@(Get-EGCollection -Uri $uri -ExpectedPath $path).Count -eq 0) 'Empty response failed.'
} finally { Remove-Item Function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
Write-Host 'Export group-membership helper tests passed. Mocked reads only; no tenant calls.' -ForegroundColor Green
