[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.GroupMembers.Helpers.ps1')
function Assert-GMTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$group=@{id='11111111-1111-4111-8111-111111111111';displayName='Test group';mail='test-group@contoso.com'}
$user=@{id='22222222-2222-4222-8222-222222222222';'@odata.type'='#microsoft.graph.user';displayName='Test User';userPrincipalName='test.user@contoso.com';mail='test.user@contoso.com'}
$nested=@{id='33333333-3333-4333-8333-333333333333';'@odata.type'='#microsoft.graph.group';displayName='Nested group'}
$device=@{id='44444444-4444-4444-8444-444444444444';'@odata.type'='#microsoft.graph.device'}
$r=ConvertTo-GMMemberRow -Member $user -Group $group
Assert-GMTest ($r.ObjectType -eq 'User' -and $r.MembershipScope -eq 'Direct' -and $r.GroupId -eq $group.id) 'User conversion failed.'
$r=ConvertTo-GMMemberRow -Member $nested -Group $group
Assert-GMTest ($r.ObjectType -eq 'Group' -and $r.MembershipScope -eq 'Direct') 'Nested group must remain a direct group row.'
$r=ConvertTo-GMMemberRow -Member $device -Group $group
Assert-GMTest ($r.ObjectType -eq 'Device' -and $r.Information -eq 'Limited information returned' -and $r.ObjectId -eq $device.id) 'Limited object details lost.'
Assert-GMTest (@(Select-GMGroupMatches -Groups @($group) -Search '*').Count -eq 0) 'Wildcard interpreted in literal search.'
Assert-GMTest (@(Select-GMGroupMatches -Groups @($group) -Search 'TEST-GROUP@').Count -eq 1) 'Case-insensitive email search failed.'
$safe=ConvertTo-GMCsvSafeRow ([pscustomobject]@{DisplayName=' +SUM(1,2)';Name='ordinary'})
Assert-GMTest ($safe.DisplayName.StartsWith("'") -and $safe.Name -eq 'ordinary') 'CSV text safety failed.'
$script:GMCalls=0; $script:GMMode='Pages'
$memberPath='/v1.0/groups/'+$group.id+'/members'
$start='https://graph.microsoft.com'+$memberPath
function Invoke-MgGraphRequest {
 param($Method,$Uri,$OutputType)
 if ($Method -ne 'GET') { throw 'Mutation in read-only test.' }
 $script:GMCalls++
 switch ($script:GMMode) {
  'Pages' { if ($script:GMCalls -eq 1) { return @{value=@($user);'@odata.nextLink'=($start+'?$skiptoken=next')} }; return @{value=@($nested,$user)} }
  'Empty' { return @{value=@()} }
  'Cycle' { return @{value=@($user);'@odata.nextLink'=($start+'?$skiptoken=cycle')} }
  'External' { return @{value=@();'@odata.nextLink'='https://example.invalid/x'} }
  'WrongGroup' { return @{value=@();'@odata.nextLink'='https://graph.microsoft.com/v1.0/groups/55555555-5555-4555-8555-555555555555/members'} }
  'Failure' { if ($script:GMCalls -eq 1) { return @{value=@($user);'@odata.nextLink'=($start+'?$skiptoken=fail')} }; throw 'Simulated permission/transport failure' }
 }
}
try {
 $all=@(Get-GMCollection -Uri $start -ExpectedPath $memberPath)
 Assert-GMTest ($all.Count -eq 2 -and $script:GMCalls -eq 2) 'Pagination/deduplication failed.'
 foreach ($mode in @('Cycle','External','WrongGroup','Failure')) {
  $script:GMCalls=0; $script:GMMode=$mode; $failed=$false
  try { $null=@(Get-GMCollection -Uri $start -ExpectedPath $memberPath) } catch { $failed=$true }
  Assert-GMTest $failed ('Expected guarded failure: '+$mode)
 }
 $script:GMMode='Empty'
 Assert-GMTest (@(Get-GMCollection -Uri $start -ExpectedPath $memberPath).Count -eq 0) 'Empty collection failed.'
} finally { Remove-Item Function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
Write-Host 'Group-member local tests passed. Mocked Graph reads only; no tenant calls.' -ForegroundColor Green
