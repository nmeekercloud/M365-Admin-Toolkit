BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Groups/Export-GroupMemberships.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked' }
}
Describe 'Phase 10 omitted and explicit group ID regression' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='offline'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { return @{value=@()} }
   @{value=@(@{id='11111111-1111-4111-8111-111111111111';displayName='Finance';mail='finance@contoso.com';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private'})}
  }
  Mock Show-M365Results {}
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Write-Progress {}
  Mock Read-Host { throw 'Unexpected prompt' }
 }
 It 'allows omitted GroupIds when literal Search selects groups' {
  $r=& $entry -Search 'Finance' -NoInteractive -PassThru -Confirm:$false
  $r.RunStatus | Should -Be 'CompletedWithKnownLimitations'
  $r.ExportStatus | Should -Be 'NotRequested'
  $r.Groups.Count | Should -Be 1
 }
 It 'reaches the missing-selector validation without prompting or authentication' {
  { & $entry -NoInteractive } | Should -Throw '*Specify GroupIds, Search or AllGroups*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'rejects explicitly empty and null ID arrays before authentication' {
  { & $entry -GroupIds @() -NoInteractive } | Should -Throw '*contains no IDs*'
  { & $entry -GroupIds $null -NoInteractive } | Should -Throw '*contains no IDs*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'still rejects malformed whitespace and empty GUID values' {
  foreach ($bad in @('bad-id',' ','00000000-0000-0000-0000-000000000000')) {
   { & $entry -GroupIds $bad -NoInteractive } | Should -Throw '*Invalid GroupId*'
  }
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'does not silently discard invalid IDs mixed with valid IDs' {
  { & $entry -GroupIds @('11111111-1111-4111-8111-111111111111','') -NoInteractive } | Should -Throw '*Invalid GroupId*'
  Should -Invoke Assert-M365Connection -Times 0
 }
}
