BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.BulkGroupMembers.Output.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 $entry=Join-Path $root 'Scripts/Groups/Add-BulkGroupMember.ps1'
}
Describe 'Phase 14 bulk directory group membership output' {
 BeforeEach {
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  $rows=@([pscustomobject]@{Record=2;Group='=Example';GroupId='11111111-1111-4111-8111-111111111111';UserPrincipalName='user@contoso.com';UserId='22222222-2222-4222-8222-222222222222';Result='Success';Detail='Offline fixture'})
 }
 It 'displays before export choice and declining creates nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=Show-ToolkitBulkGroupMemberResult -Results $rows
  $r.Status | Should -Be 'Declined'
  $r.ReportFolder | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitBulkGroupMemberResult -Results $rows -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
 }
 It 'exports declared files and columns with safe CSV and unmodified rows' {
  $r=Show-ToolkitBulkGroupMemberResult -Results $rows -TenantId 'offline' -NoInteractive -ExportDirectory $TestDrive -ReportName 'bulk'
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Results.csv','Run.json')
  (Get-Content (Join-Path $r.ReportFolder 'Results.csv') -First 1) | Should -Be '"Record","Group","GroupId","UserPrincipalName","UserId","Result","Detail"'
  (Import-Csv (Join-Path $r.ReportFolder 'Results.csv')).Group | Should -Be "'=Example"
  $rows[0].Group | Should -Be '=Example'
 }
 It 'suppresses WhatIf preview exports even with an explicit destination' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitBulkGroupMemberResult -Results $rows -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'keeps failed uncertain skipped and not-run rows distinct from success' {
  $states=@('Failed','Unverified','NotRun','Unsupported','Duplicate','AlreadyMember','Planned')
  $mixed=@($states | ForEach-Object { [pscustomobject]@{Record=2;Group='Example';GroupId='offline';UserPrincipalName='user@contoso.com';UserId='offline';Result=$_;Detail='fixture'} })
  $r=Show-ToolkitBulkGroupMemberResult -Results $mixed -NoInteractive -ExportDirectory $TestDrive -ReportName 'mixed'
  $r.Status | Should -Be 'Saved'
  $m=Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json
  $m.TaskId | Should -Be 'groups.add-bulkgroupmember'
  $m.Status | Should -Be 'ResultSummary'
  $m.Successful | Should -Be 0
  foreach ($state in $states) { $m.$state | Should -Be 1 }
  ($mixed.Result -join ',') | Should -Be ($states -join ',')
 }
 It 'retains result rows when export fails' {
  (Show-ToolkitBulkGroupMemberResult -Results $rows -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $rows[0].Result | Should -Be 'Success'
 }
 It 'refuses existing bundles without overwriting files' {
  $folder=Join-Path $TestDrive 'existing';$null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  (Show-ToolkitBulkGroupMemberResult -Results $rows -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'does not offer export for empty result sets' {
  (Show-ToolkitBulkGroupMemberResult -Results @()).Status | Should -Be 'NoResults'
  Should -Invoke Read-Host -Times 0
 }
 It 'preserves preflight approval backup write guard and raw passthrough wiring' {
  $text=Get-Content $entry -Raw
  $text.IndexOf('Import-BGMCsv') | Should -BeLessThan $text.IndexOf('Initialize-UMTask')
  $backup=$text.IndexOf('$null=Save-UMJson')
  $backup | Should -BeGreaterThan $text.IndexOf('Confirm-M365Action')
  $backup | Should -BeGreaterThan $text.IndexOf('$PSCmdlet.ShouldProcess')
  $backup | Should -BeLessThan $text.IndexOf('$null=Invoke-UMGraph -Method POST')
  $text | Should -Match 'if \(\$PassThru\) \{ \$results \}'
  $text | Should -Match 'PreviewOnly:\$WhatIfPreference'
  $text | Should -Not -Match 'Get-M365OutputPath -Type Reports|Export-Csv'
 }
 It 'contains no cloud operations or backup commands in the output helper' {
  $text=Get-Content (Join-Path $root 'Tools/Toolkit.BulkGroupMembers.Output.ps1') -Raw
  $text | Should -Not -Match 'Invoke-UMGraph|Invoke-MgGraphRequest|Save-UMJson|Assert-M365Connection|Confirm-M365Action'
 }
}
