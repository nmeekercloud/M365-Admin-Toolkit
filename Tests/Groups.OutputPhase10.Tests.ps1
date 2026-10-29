BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Groups/Export-GroupMemberships.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked' }
 function New-Phase10Group {
  @{id='11111111-1111-4111-8111-111111111111';displayName='=Members';mail='group@contoso.com';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$null}
 }
 function Get-Phase10Fixture {
  param([string]$Uri)
  if ($Uri -match '/members') { return @{value=@(@{id='22222222-2222-4222-8222-222222222222';displayName='=User';userPrincipalName='user@contoso.com';mail='';'@odata.type'='#microsoft.graph.user'})} }
  if ($Uri -match '/groups\?') { return @{value=@(New-Phase10Group)} }
  if ($Uri -match '/groups/') { return (New-Phase10Group) }
  throw ('Unexpected URI: '+$Uri)
 }
}
Describe 'Phase 10 direct group membership output' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='offline'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest { Get-Phase10Fixture -Uri $Uri }
  Mock Show-M365Results {}
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Write-Progress {}
  Mock Read-Host { 'n' }
 }
 It 'displays members and coverage before asking and declining creates nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 2 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -AllGroups -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Declined'
  $r.ReturnedMemberRows | Should -Be 1
  $r.ReportFolder | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save in noninteractive mode by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -AllGroups -NoInteractive -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 2 -ParameterFilter { $NoPaging }
 }
 It 'exports only three declared files and preserves raw values and scope warnings' {
  $r=& $entry -AllGroups -NoInteractive -ExportDirectory $TestDrive -ReportName 'members' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Groups.csv','Members.csv','Run.json')
  (Import-Csv (Join-Path $r.ReportFolder 'Members.csv')).DisplayName | Should -Be "'=User"
  $r.Members[0].DisplayName | Should -Be '=User'
  $r.Members[0].MembershipScope | Should -Be 'Direct'
  $r.RunStatus | Should -Be 'CompletedWithKnownLimitations'
  (Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json).Warnings | Should -Contain 'Nested groups are not expanded.'
 }
 It 'skips hidden-membership reads with explicit partial coverage and unknown counts' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { throw 'Hidden membership must not be read' }
   $g=New-Phase10Group;$g.visibility='HiddenMembership'
   @{value=@($g)}
  }
  $r=& $entry -AllGroups -NoInteractive -PassThru -Confirm:$false
  $r.RunStatus | Should -Be 'PartialCoverage'
  $r.Groups[0].ReadStatus | Should -Be 'HiddenSkipped'
  $r.Groups[0].ReturnedMemberCount | Should -BeNullOrEmpty
  $r.Manifest.HiddenGroupsSkipped | Should -Be 1
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Uri -match '/members' }
 }
 It 'keeps API failure counts unknown rather than claiming zero members' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { throw 'Synthetic membership denial' }
   Get-Phase10Fixture -Uri $Uri
  }
  $r=& $entry -AllGroups -NoInteractive -PassThru -Confirm:$false
  $r.RunStatus | Should -Be 'PartialCoverage'
  $r.Groups[0].ReadStatus | Should -Be 'Error'
  $r.Groups[0].ReturnedMemberCount | Should -BeNullOrEmpty
  $r.Manifest.FailedGroupReads | Should -Be 1
 }
 It 'keeps incomplete paginated group reads from emitting apparently complete members' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match 'skiptoken') { throw 'Synthetic second-page denial' }
   $page=Get-Phase10Fixture -Uri $Uri
   if ($Uri -match '/members') { $page['@odata.nextLink']='https://graph.microsoft.com/v1.0/groups/11111111-1111-4111-8111-111111111111/members?$skiptoken=offline' }
   $page
  }
  $r=& $entry -AllGroups -NoInteractive -PassThru -Confirm:$false
  $r.RunStatus | Should -Be 'PartialCoverage'
  $r.Members.Count | Should -Be 0
  $r.Groups[0].ReturnedMemberCount | Should -BeNullOrEmpty
 }
 It 'retains limited information counts' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { return @{value=@(@{id='22222222-2222-4222-8222-222222222222';'@odata.type'='#microsoft.graph.user'})} }
   Get-Phase10Fixture -Uri $Uri
  }
  $r=& $entry -AllGroups -NoInteractive -PassThru -Confirm:$false
  $r.Groups[0].LimitedInformationCount | Should -Be 1
  $r.Members[0].Information | Should -Be 'Limited information returned'
 }
 It 'supports explicit group IDs without changing lookup validation' {
  $r=& $entry -GroupIds '11111111-1111-4111-8111-111111111111' -NoInteractive -PassThru -Confirm:$false
  $r.ReturnedMemberRows | Should -Be 1
  $r.Groups[0].GroupId | Should -Be '11111111-1111-4111-8111-111111111111'
 }
 It 'preserves explicit member headers for successful empty reads' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { return @{value=@()} }
   Get-Phase10Fixture -Uri $Uri
  }
  $r=& $entry -AllGroups -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  $r.Groups[0].ReadStatus | Should -Be 'ReadSucceeded'
  $r.Groups[0].ReturnedMemberCount | Should -Be 0
  (Get-Content (Join-Path $r.ReportFolder 'Members.csv') -First 1) | Should -Be '"GroupId","GroupName","GroupMail","MembershipScope","ObjectType","ObjectId","DisplayName","UserPrincipalName","Mail","Information","Coverage"'
 }
 It 'keeps scan status and rows independent of export failure' {
  $r=& $entry -AllGroups -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru -Confirm:$false -WarningAction SilentlyContinue
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.RunStatus | Should -Be 'CompletedWithKnownLimitations'
  $r.ReturnedMemberRows | Should -Be 1
 }
 It 'honors WhatIf before membership reads display or output creation' {
  Mock New-Item { throw 'Unexpected directory creation' }
  & $entry -AllGroups -NoInteractive -WhatIf
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Uri -match '/members' }
  Should -Invoke Show-M365Results -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'contains no automatic report staging or export commands' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Get-M365OutputPath|Export-Csv|Set-Content|New-Item|Move-Item|Initialize-EGCsv|\.partial'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
