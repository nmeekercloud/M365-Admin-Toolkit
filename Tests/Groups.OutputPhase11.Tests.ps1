BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Groups/Get-GroupMembers.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked' }
 function New-Phase11Group { @{id='11111111-1111-4111-8111-111111111111';displayName='Members';mail='members@contoso.com';visibility='Private'} }
 if (Test-Path variable:global:M365Phase11Answers) { throw 'Reserved test state exists; use a fresh window.' }
 $global:M365Phase11Answers=$null
}
AfterAll { Remove-Variable M365Phase11Answers -Scope Global -ErrorAction SilentlyContinue }
Describe 'Phase 11 group member paging and optional export' {
 BeforeEach {
  $global:M365Phase11Answers=[Collections.Generic.Queue[string]]::new()
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='offline'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { return @{value=@(@{id='22222222-2222-4222-8222-222222222222';displayName='=User';userPrincipalName='user@contoso.com';'@odata.type'='#microsoft.graph.user'})} }
   if ($Uri -match '/groups\?') { return @{value=@(New-Phase11Group)} }
   New-Phase11Group
  }
  Mock Show-M365Results {}
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Read-Host {
   if (-not $global:M365Phase11Answers.Count) { throw 'Unexpected prompt' }
   $global:M365Phase11Answers.Dequeue()
  }
 }
 It 'uses the shared viewer without prompts or directory creation by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=@(& $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -PassThru)
  $r.Count | Should -Be 1
  $r[0].MembershipScope | Should -Be 'Direct'
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only Members.csv and Run.json after display and keeps raw row passthrough' {
  $r=@(& $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -ExportDirectory $TestDrive -ReportName 'members' -PassThru -Confirm:$false)
  Should -Invoke Show-M365Results -Times 1 -Exactly
  $folder=Join-Path $TestDrive 'members'
  @((Get-ChildItem $folder -File).Name | Sort-Object) | Should -Be @('Members.csv','Run.json')
  (Import-Csv (Join-Path $folder 'Members.csv')).DisplayName | Should -Be "'=User"
  $r[0].DisplayName | Should -Be '=User'
  (Get-Content (Join-Path $folder 'Run.json') -Raw | ConvertFrom-Json).Scope | Should -Be 'Direct'
 }
 It 'rejects legacy unattended export without a destination before authentication' {
  { & $entry -GroupIdentity 'Members' -NoInteractive -ExportCsv } | Should -Throw '*both ExportDirectory and ReportName*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'retains interactive detail selection and the export menu' {
  foreach ($answer in @('1','','E','n','0')) { $global:M365Phase11Answers.Enqueue($answer) }
  $r=@(& $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -PassThru -Confirm:$false)
  $r.Count | Should -Be 1
  Should -Invoke Show-M365Results -Times 3
  Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -eq 'Press Enter to return to members' }
 }
 It 'blocks hidden-membership groups before member reads or export' {
  Mock Invoke-MgGraphRequest { $g=New-Phase11Group;$g.visibility='HiddenMembership';$g }
  { & $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive } | Should -Throw '*Hidden-membership groups*'
  Should -Invoke Show-M365Results -Times 0
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Uri -match '/members' }
 }
 It 'does not export incomplete pagination reads' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { throw 'Synthetic membership denial' }
   New-Phase11Group
  }
  { & $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -ExportDirectory $TestDrive -ReportName 'blocked' -Confirm:$false } | Should -Throw '*Synthetic membership denial*'
  Test-Path (Join-Path $TestDrive 'blocked') | Should -BeFalse
 }
 It 'can explicitly export a successful empty list with headers and scope warnings' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/members') { return @{value=@()} }
   New-Phase11Group
  }
  & $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -Confirm:$false
  (Get-Content (Join-Path $TestDrive 'empty/Members.csv') -First 1) | Should -Be '"GroupName","GroupId","MembershipScope","ObjectType","DisplayName","UserPrincipalName","Mail","ObjectId","Information","Coverage"'
  (Get-Content (Join-Path $TestDrive 'empty/Run.json') -Raw | ConvertFrom-Json).ReturnedMemberRows | Should -Be 0
 }
 It 'keeps returned rows when export fails' {
  $r=@(& $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru -Confirm:$false -WarningAction SilentlyContinue)
  $r.Count | Should -Be 1
  $r[0].ObjectId | Should -Be '22222222-2222-4222-8222-222222222222'
 }
 It 'does not create export output under WhatIf' {
  Mock New-Item { throw 'Unexpected directory creation' }
  & $entry -GroupIdentity '11111111-1111-4111-8111-111111111111' -NoInteractive -ExportDirectory $TestDrive -ReportName 'preview' -WhatIf
  Should -Invoke New-Item -Times 0
 }
 It 'preserves exact-name resolution and removes automatic CSV output' {
  $r=@(& $entry -GroupIdentity 'Members' -NoInteractive -PassThru)
  $r.Count | Should -Be 1
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Get-M365OutputPath|Export-Csv'
  $text | Should -Match 'No unique exact group name/email match'
  $text | Should -Match 'if \(\$PassThru\) \{ \$rows \}'
 }
}
