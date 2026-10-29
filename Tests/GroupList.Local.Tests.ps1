[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.GroupList.Helpers.ps1')
function Assert-GLTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$testGroups=@(
 @{id='11111111-1111-4111-8111-111111111111';displayName='Unified';groupTypes=@('Unified');mailEnabled=$true;securityEnabled=$false},
 @{id='22222222-2222-4222-8222-222222222222';displayName='Dynamic Security';groupTypes=@('DynamicMembership');mailEnabled=$false;securityEnabled=$true;onPremisesSyncEnabled=$true},
 @{id='33333333-3333-4333-8333-333333333333';displayName='Mail Security';groupTypes=@();mailEnabled=$true;securityEnabled=$true},
 @{id='44444444-4444-4444-8444-444444444444';displayName='Distribution';groupTypes=@();mailEnabled=$true;securityEnabled=$false},
 @{id='55555555-5555-4555-8555-555555555555';displayName='Unknown';groupTypes=@();mailEnabled=$null;securityEnabled=$null}
)
$rows=@($testGroups | ForEach-Object { ConvertTo-GLGroupRow $_ })
Assert-GLTest ($rows[0].GroupType -eq 'Microsoft 365') 'Unified classification failed.'
Assert-GLTest ($rows[1].MembershipMode -eq 'Dynamic' -and $rows[1].Origin -eq 'On-premises synced') 'Dynamic/synced classification failed.'
Assert-GLTest ($rows[2].GroupType -eq 'Mail-enabled security') 'Mail security classification failed.'
Assert-GLTest ($rows[3].GroupType -eq 'Distribution') 'Distribution classification failed.'
Assert-GLTest ($rows[4].GroupType -eq 'Unknown') 'Unknown flags must not become a known type.'
Assert-GLTest (@(Select-GLRows -Rows $rows -Search '*').Count -eq 0) 'Search must be literal, not wildcard.'
Assert-GLTest (@(Select-GLRows -Rows $rows -Search 'security' -Membership Dynamic).Count -eq 1) 'Search/membership filter failed.'
Assert-GLTest (@(Select-GLRows -Rows @()).Count -eq 0) 'Empty filter failed.'
$safe=ConvertTo-GLCsvSafeRow ([pscustomobject]@{DisplayName='=HYPERLINK("bad")';Normal='ordinary';Flag=$true})
Assert-GLTest ($safe.DisplayName.StartsWith("'=") -and $safe.Normal -eq 'ordinary' -and $safe.Flag -eq $true) 'CSV neutralization failed.'
$script:GLCalls=0; $script:GLTestMode='Pages'
function Invoke-MgGraphRequest {
 param($Method,$Uri,$OutputType)
 if ($Method -ne 'GET') { throw 'Unexpected mutation in read-only task.' }
 $script:GLCalls++
 if ($script:GLTestMode -eq 'Pages') {
  if ($script:GLCalls -eq 1) { return @{value=@($testGroups[0]);'@odata.nextLink'='https://graph.microsoft.com/v1.0/groups?$skiptoken=test'} }
  return @{value=@($testGroups[1])}
 }
 if ($script:GLTestMode -eq 'Cycle') { return @{value=@($testGroups[0]);'@odata.nextLink'='https://graph.microsoft.com/v1.0/groups?$skiptoken=cycle'} }
 if ($script:GLTestMode -eq 'External') { return @{value=@();'@odata.nextLink'='https://example.invalid/steal'} }
 if ($script:GLTestMode -eq 'Error') { if ($script:GLCalls -eq 1) { return @{value=@($testGroups[0]);'@odata.nextLink'='https://graph.microsoft.com/v1.0/groups?$skiptoken=error'} }; throw 'Simulated read failure' }
 return @{value=@()}
}
try {
 $all=@(Get-GLInventory)
 Assert-GLTest ($all.Count -eq 2 -and $script:GLCalls -eq 2) 'Pagination failed.'
 foreach ($mode in @('Cycle','External','Error')) {
  $script:GLTestMode=$mode; $script:GLCalls=0; $failed=$false
  try { $null=@(Get-GLInventory) } catch { $failed=$true }
  Assert-GLTest $failed ('Expected guarded failure: '+$mode)
 }
 $script:GLTestMode='Empty'
 Assert-GLTest (@(Get-GLInventory).Count -eq 0) 'Empty Graph response failed.'
} finally { Remove-Item Function:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
Write-Host 'Local group-list tests passed. Mocked reads only; no tenant calls.' -ForegroundColor Green
