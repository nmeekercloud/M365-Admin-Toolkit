BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.CopyGroupMemberships.Output.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 $entry=Join-Path $root 'Scripts/Groups/Copy-GroupMemberships.ps1'
}
Describe 'Phase 13 copy directory group membership result output' {
 BeforeEach {
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  $rows=@([pscustomobject]@{Group='=Example';GroupId='11111111-1111-4111-8111-111111111111';Target='target@contoso.com';Result='Success';Detail='Offline fixture'})
 }
 It 'displays before offering export and declining creates nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=Show-ToolkitCopyGroupMembershipResult -Results $rows
  $r.Status | Should -Be 'Declined'
  $r.ReportFolder | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or export by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitCopyGroupMembershipResult -Results $rows -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
 }
 It 'exports only Results.csv and Run.json with explicit columns and unmodified raw rows' {
  $r=Show-ToolkitCopyGroupMembershipResult -Results $rows -TenantId 'offline' -NoInteractive -ExportDirectory $TestDrive -ReportName 'copy-results'
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Results.csv','Run.json')
  (Get-Content (Join-Path $r.ReportFolder 'Results.csv') -First 1) | Should -Be '"Group","GroupId","Target","Result","Detail"'
  (Import-Csv (Join-Path $r.ReportFolder 'Results.csv')).Group | Should -Be "'=Example"
  $rows[0].Group | Should -Be '=Example'
 }
 It 'does not export preview results even with a destination' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitCopyGroupMembershipResult -Results $rows -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'counts original failure uncertainty and Not run statuses without relabeling them' {
  $mixed=@('Failed','Unverified','Not run' | ForEach-Object { [pscustomobject]@{Group='Example';GroupId='offline';Target='target@contoso.com';Result=$_;Detail='fixture'} })
  $r=Show-ToolkitCopyGroupMembershipResult -Results $mixed -NoInteractive -ExportDirectory $TestDrive -ReportName 'mixed'
  $r.Status | Should -Be 'Saved'
  $m=Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json
  $m.TaskId | Should -Be 'groups.copy-groupmemberships'
  $m.Status | Should -Be 'ResultSummary'
  $m.Successful | Should -Be 0
  $m.Failed | Should -Be 1
  $m.Unverified | Should -Be 1
  $m.NotRun | Should -Be 1
  ($mixed.Result -join ',') | Should -Be 'Failed,Unverified,Not run'
 }
 It 'retains mutation result rows when export fails' {
  (Show-ToolkitCopyGroupMembershipResult -Results $rows -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $rows[0].Result | Should -Be 'Success'
 }
 It 'refuses existing bundles without changing their files' {
  $folder=Join-Path $TestDrive 'existing';$null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  (Show-ToolkitCopyGroupMembershipResult -Results $rows -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'does not offer export for no results' {
  (Show-ToolkitCopyGroupMembershipResult -Results @()).Status | Should -Be 'NoResults'
  Should -Invoke Read-Host -Times 0
 }
 It 'retains approval ShouldProcess and required backup before the Graph write and raw passthrough' {
  $text=Get-Content $entry -Raw
  $backup=$text.IndexOf('$null=Save-UMJson')
  $backup | Should -BeGreaterThan $text.IndexOf('Confirm-M365Action')
  $backup | Should -BeGreaterThan $text.IndexOf('$PSCmdlet.ShouldProcess')
  $backup | Should -BeLessThan $text.IndexOf('$null=Invoke-UMGraph -Method POST')
  $text | Should -Match 'if \(\$PassThru\) \{ \$results \}'
  $text | Should -Match 'PreviewOnly:\$WhatIfPreference'
  $text | Should -Not -Match 'Get-M365OutputPath -Type Reports|Export-Csv'
 }
 It 'contains no cloud operations in the output helper' {
  $text=Get-Content (Join-Path $root 'Tools/Toolkit.CopyGroupMemberships.Output.ps1') -Raw
  $text | Should -Not -Match 'Invoke-UMGraph|Invoke-MgGraphRequest|Save-UMJson|Assert-M365Connection|Confirm-M365Action'
 }
}
