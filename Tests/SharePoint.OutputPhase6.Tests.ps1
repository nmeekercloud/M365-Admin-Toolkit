BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.CopySitePermissions.Output.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 $entry=Join-Path $root 'Scripts/SharePoint/Copy-SitePermissions.ps1'
}
Describe 'Phase 6 copy site membership result output' {
 BeforeEach {
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  $rows=@([pscustomobject]@{SiteUrl='https://contoso.sharepoint.com/sites/test';GroupId=7;GroupName='=Members';Target='target@contoso.com';Result='Success';Detail='Verified offline fixture'})
 }
 It 'displays before the export prompt and declining creates nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=Show-ToolkitCopySitePermissionsResult -Results $rows
  $r.Status | Should -Be 'Declined'
  $r.ReportFolder | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or export in noninteractive mode by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitCopySitePermissionsResult -Results $rows -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only the declared files and preserves raw data and column order' {
  $r=Show-ToolkitCopySitePermissionsResult -Results $rows -TenantId 'offline' -NoInteractive -ExportDirectory $TestDrive -ReportName 'copy-results'
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Results.csv','Run.json')
  (Get-Content (Join-Path $r.ReportFolder 'Results.csv') -First 1) | Should -Be '"SiteUrl","GroupId","GroupName","Target","Result","Detail"'
  (Import-Csv (Join-Path $r.ReportFolder 'Results.csv')).GroupName | Should -Be "'=Members"
  $rows[0].GroupName | Should -Be '=Members'
  (Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json).TaskId | Should -Be 'sharepoint.copy-sitepermissions'
 }
 It 'suppresses preview exports even when a destination is supplied' {
  Mock New-Item { throw 'Unexpected directory creation' }
  (Show-ToolkitCopySitePermissionsResult -Results $rows -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'reports failed uncertain and not-run rows without calling them successful' {
  $mixed=@('Failed','Unverified','NotRun' | ForEach-Object { [pscustomobject]@{SiteUrl='offline';GroupId=7;GroupName='Members';Target='target@contoso.com';Result=$_;Detail='fixture'} })
  $r=Show-ToolkitCopySitePermissionsResult -Results $mixed -NoInteractive -ExportDirectory $TestDrive -ReportName 'mixed'
  $r.Status | Should -Be 'Saved'
  $m=Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json
  $m.Status | Should -Be 'ResultSummary'
  $m.Successful | Should -Be 0
  $m.Failed | Should -Be 1
  $m.Unverified | Should -Be 1
  $m.NotRun | Should -Be 1
  ($mixed.Result -join ',') | Should -Be 'Failed,Unverified,NotRun'
 }
 It 'does not change successful rows when export fails' {
  (Show-ToolkitCopySitePermissionsResult -Results $rows -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $rows[0].Result | Should -Be 'Success'
 }
 It 'rejects existing bundles without overwriting their data' {
  $folder=Join-Path $TestDrive 'existing'
  $null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  (Show-ToolkitCopySitePermissionsResult -Results $rows -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'does not offer export for empty results' {
  (Show-ToolkitCopySitePermissionsResult -Results @()).Status | Should -Be 'NoResults'
  Should -Invoke Read-Host -Times 0
 }
 It 'preserves required backup and write guard ordering and raw passthrough' {
  $text=Get-Content $entry -Raw
  $backup=$text.IndexOf('Get-M365OutputPath -Type Backups')
  $backup | Should -BeGreaterThan $text.IndexOf('$PSCmdlet.ShouldProcess')
  $backup | Should -BeLessThan $text.IndexOf('$null=Add-PnPGroupMember')
  $text.IndexOf('Confirm-M365Action') | Should -BeLessThan $backup
  $text | Should -Match 'if \(\$PassThru\) \{ \$results \}'
  $text | Should -Not -Match 'Get-M365OutputPath -Type Reports|Export-Csv'
  $text | Should -Match 'PreviewOnly:\$WhatIfPreference'
 }
 It 'contains no cloud writes or authentication in the output helper' {
  $text=Get-Content (Join-Path $root 'Tools/Toolkit.CopySitePermissions.Output.ps1') -Raw
  $text | Should -Not -Match 'Add-PnP|Set-PnP|Remove-PnP|Assert-M365Connection|Confirm-M365Action'
 }
}
