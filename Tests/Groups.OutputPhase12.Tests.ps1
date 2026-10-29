BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Groups/Get-GroupList.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked' }
 if (Test-Path variable:global:M365Phase12Answers) { throw 'Reserved test state exists; use a fresh window.' }
 $global:M365Phase12Answers=$null
}
AfterAll { Remove-Variable M365Phase12Answers -Scope Global -ErrorAction SilentlyContinue }
Describe 'Phase 12 group inventory shared output' {
 BeforeEach {
  $global:M365Phase12Answers=[Collections.Generic.Queue[string]]::new()
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='offline';TenantName='Offline'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest {
   @{value=@(
    @{id='11111111-1111-4111-8111-111111111111';displayName='=Finance';mail='finance@contoso.com';description='Literal [abc]';groupTypes=@();mailEnabled=$false;securityEnabled=$true;onPremisesSyncEnabled=$true},
    @{id='22222222-2222-4222-8222-222222222222';displayName='Team';mail='team@contoso.com';description='Team';groupTypes=@('Unified','DynamicMembership');mailEnabled=$true;securityEnabled=$false;resourceProvisioningOptions=@('Team')}
   )}
  }
  Mock Show-M365Results {}
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Read-Host {
   if (-not $global:M365Phase12Answers.Count) { throw 'Unexpected prompt' }
   $global:M365Phase12Answers.Dequeue()
  }
 }
 It 'uses the shared viewer without prompting or writing by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=@(& $entry -NoInteractive -PassThru)
  $r.Count | Should -Be 2
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only Groups.csv and Run.json with safe CSV and raw passthrough' {
  $r=@(& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'groups' -PassThru -Confirm:$false)
  $folder=Join-Path $TestDrive 'groups'
  @((Get-ChildItem $folder -File).Name | Sort-Object) | Should -Be @('Groups.csv','Run.json')
  @((Import-Csv (Join-Path $folder 'Groups.csv')) | Where-Object Mail -eq 'finance@contoso.com')[0].DisplayName | Should -Be "'=Finance"
  @($r | Where-Object Mail -eq 'finance@contoso.com')[0].DisplayName | Should -Be '=Finance'
  (Get-Content (Join-Path $folder 'Run.json') -Raw | ConvertFrom-Json).MatchingRows | Should -Be 2
  Should -Invoke Show-M365Results -Times 1
 }
 It 'retains literal search and group type membership and origin classifications' {
  $r=@(& $entry -Search '[abc]' -GroupType Security -Membership Assigned -NoInteractive -PassThru)
  $r.Count | Should -Be 1
  $r[0].Origin | Should -Be 'On-premises synced'
  $r[0].GroupType | Should -Be 'Security'
  $dynamic=@(& $entry -GroupType Microsoft365 -Membership Dynamic -NoInteractive -PassThru)
  $dynamic.Count | Should -Be 1
  $dynamic[0].TeamsEnabled | Should -BeTrue
 }
 It 'rejects unattended legacy export without a destination before authentication' {
  { & $entry -NoInteractive -ExportCsv } | Should -Throw '*both ExportDirectory and ReportName*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'retains numbered details and the interactive export menu' {
  foreach ($a in @('1','','E','n','0')) { $global:M365Phase12Answers.Enqueue($a) }
  $r=@(& $entry -Search '' -PassThru -Confirm:$false)
  $r.Count | Should -Be 2
  Should -Invoke Show-M365Results -Times 3
  Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -eq 'Press Enter to return to the list' }
 }
 It 'retains interactive filters and records the resulting filter in a saved manifest' {
  foreach ($a in @('F','1','D','E','y',$TestDrive,'filtered','0')) { $global:M365Phase12Answers.Enqueue($a) }
  $r=@(& $entry -Search '' -PassThru -Confirm:$false)
  $r.Count | Should -Be 1
  $r[0].MembershipMode | Should -Be 'Dynamic'
  $m=Get-Content (Join-Path $TestDrive 'filtered/Run.json') -Raw | ConvertFrom-Json
  $m.GroupTypeFilter | Should -Be 'Microsoft365'
  $m.MembershipFilter | Should -Be 'Dynamic'
  $m.InventoryRows | Should -Be 2
  $m.MatchingRows | Should -Be 1
 }
 It 'exports a successful empty filtered list with explicit headers and scope context' {
  & $entry -Search 'no-match' -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -Confirm:$false
  (Get-Content (Join-Path $TestDrive 'empty/Groups.csv') -First 1) | Should -Be '"Id","DisplayName","Mail","GroupType","MembershipMode","Origin","TeamsEnabled","RoleAssignable","Visibility","Description","CreatedDateTime","LastSyncDateTime","MembershipRule","RuleProcessingState"'
  (Get-Content (Join-Path $TestDrive 'empty/Run.json') -Raw | ConvertFrom-Json).MatchingRows | Should -Be 0
 }
 It 'does not export a failed inventory read' {
  Mock Invoke-MgGraphRequest { throw 'Synthetic inventory denial' }
  { & $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'blocked' -Confirm:$false } | Should -Throw '*Synthetic inventory denial*'
  Test-Path (Join-Path $TestDrive 'blocked') | Should -BeFalse
 }
 It 'preserves rows on export failure and suppresses writes under WhatIf' {
  $r=@(& $entry -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru -Confirm:$false -WarningAction SilentlyContinue)
  $r.Count | Should -Be 2
  Mock New-Item { throw 'Unexpected directory creation' }
  & $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'preview' -WhatIf
  Should -Invoke New-Item -Times 0
 }
 It 'retains search control and raw passthrough without automatic export paths' {
  foreach ($a in @('S','Team','0')) { $global:M365Phase12Answers.Enqueue($a) }
  $r=@(& $entry -Search '' -PassThru)
  $r.Count | Should -Be 1
  $r[0].DisplayName | Should -Be 'Team'
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Get-M365OutputPath|Export-Csv'
  $text | Should -Match 'if \(\$PassThru\) \{ \$filtered \}'
 }
}
