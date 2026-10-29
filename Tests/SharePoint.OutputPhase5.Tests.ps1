BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.BulkSiteAccess.Output.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 $entry=Join-Path $root 'Scripts/SharePoint/Grant-BulkSiteAccess.ps1'
}
Describe 'Phase 5 optional bulk site access result export' {
 BeforeEach {
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  $rows=@([pscustomobject]@{Record=2;SiteUrl='https://contoso.sharepoint.com/sites/test';WebId='offline';SharePointGroupId=7;GroupName='Members';UserPrincipalName='user@contoso.com';UserId='offline';Result='Success';Detail='=Example'})
 }
 It 'displays before asking and declining creates no directory' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory write' }
  $r=Show-ToolkitBulkSiteAccessResult -Results $rows
  $r.Status | Should -Be 'Declined'
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or export by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory write' }
  (Show-ToolkitBulkSiteAccessResult -Results $rows -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports exactly Results.csv and Run.json with safe CSV and unmodified rows' {
  $r=Show-ToolkitBulkSiteAccessResult -Results $rows -TenantId 'offline' -NoInteractive -ExportDirectory $TestDrive -ReportName 'results'
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Results.csv','Run.json')
  (Import-Csv (Join-Path $r.ReportFolder 'Results.csv')).Detail | Should -Be "'=Example"
  $rows[0].Detail | Should -Be '=Example'
 }
 It 'does not export or prompt during WhatIf preview even with an explicit destination' {
  Mock New-Item { throw 'Unexpected directory write' }
  (Show-ToolkitBulkSiteAccessResult -Results $rows -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'does not label uncertain or failed membership rows as successful' {
  $rows[0].Result='Unverified'
  $r=Show-ToolkitBulkSiteAccessResult -Results $rows -NoInteractive -ExportDirectory $TestDrive -ReportName 'uncertain'
  $r.Status | Should -Be 'Saved'
  $manifest=Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json
  $manifest.Status | Should -Be 'ResultSummary'
  $manifest.Unverified | Should -Be 1
  $manifest.Successful | Should -Be 0
  $rows[0].Result | Should -Be 'Unverified'
 }
 It 'preserves rows when export fails' {
  (Show-ToolkitBulkSiteAccessResult -Results $rows -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $rows[0].Result | Should -Be 'Success'
 }
 It 'never overwrites existing result bundles' {
  $folder=Join-Path $TestDrive 'existing'
  $null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  (Show-ToolkitBulkSiteAccessResult -Results $rows -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'skips empty result sets without prompting' {
  (Show-ToolkitBulkSiteAccessResult -Results @()).Status | Should -Be 'NoResults'
  Should -Invoke Read-Host -Times 0
 }
 It 'keeps the mandatory backup before the membership write and retains raw passthrough' {
  $text=Get-Content $entry -Raw
  $text.IndexOf('Get-M365OutputPath -Type Backups') | Should -BeGreaterThan 0
  $text.IndexOf('Get-M365OutputPath -Type Backups') | Should -BeLessThan $text.IndexOf('$null=Add-PnPGroupMember')
  $text | Should -Match 'if \(\$PassThru\) \{ \$results \}'
  $text | Should -Not -Match 'Get-M365OutputPath -Type Reports|Export-Csv'
 }
 It 'contains no cloud writes in the output helper' {
  $text=Get-Content (Join-Path $root 'Tools/Toolkit.BulkSiteAccess.Output.ps1') -Raw
  $text | Should -Not -Match 'Add-PnP|Set-PnP|Remove-PnP|Assert-M365Connection|Confirm-M365Action'
 }
}
