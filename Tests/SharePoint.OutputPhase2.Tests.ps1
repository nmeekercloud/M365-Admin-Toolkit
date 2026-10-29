BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.SharePointAccessScanner.ps1')
 . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked network call blocked' }
 function Get-PnPAccessToken { [CmdletBinding()]param($ResourceTypeName,$Connection) throw 'Unmocked token access blocked' }
 function Get-PnPTenantSite { [CmdletBinding()]param($Identity,$Connection) throw 'Unmocked tenant call blocked' }
 function Connect-PnPOnline { [CmdletBinding()]param($Url,$AccessToken,[switch]$ReturnConnection) throw 'Unmocked connection blocked' }
 function Get-PnPWeb { [CmdletBinding()]param($Includes,$Connection) throw 'Unmocked site call blocked' }
 function Get-PnPSiteCollectionAdmin { [CmdletBinding()]param($Connection) throw 'Unmocked admin call blocked' }
 function Get-M365OutputPath { param($Type) throw 'Legacy automatic output path must not be used' }
 $fakeCore=New-Module -Name SAROfflineCore -ScriptBlock {
  $script:M365Session=[pscustomobject]@{SharePoint=[pscustomobject]@{Connection=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}}}
 }
}
Describe 'SharePoint optional bundle output phase 2' {
 BeforeEach {
  $script:answers=[Collections.Generic.Queue[string]]::new()
  Mock Read-Host { if (-not $script:answers.Count) { throw 'Unexpected prompt' }; $script:answers.Dequeue() }
  Mock Write-Host {}
  Mock Write-M365Log {}
  Mock Show-M365Results {}
  $script:context=New-SARMemoryContext -Mode All -MaxRows 100
  $script:context.Rows['Grants.csv'].Add([pscustomobject]@{Name='example';Value='Read'})
  $script:manifest=[ordered]@{Status='CompletedWithinDeclaredScope';Scope='RootWeb'}
  $script:columns=@{'Grants.csv'=@('Name','Value');'Links.csv'=@('Name');'Coverage.csv'=@('Status','Detail')}
 }
 It 'declining export creates no files or directories' {
  $script:answers.Enqueue('n')
  Mock New-Item { throw 'Unapproved directory write' }
  $r=Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns
  $r.Status | Should -Be 'Declined'
  Should -Invoke New-Item -Times 0
 }
 It 'Enter defaults to no export' {
  $script:answers.Enqueue('')
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns).Status | Should -Be 'Declined'
 }
 It 'blank directory cancels without writing' {
  $script:answers.Enqueue('y'); $script:answers.Enqueue('')
  Mock New-Item { throw 'Unapproved directory write' }
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns).Status | Should -Be 'Cancelled'
  Should -Invoke New-Item -Times 0
 }
 It 'blank bundle name cancels without creating the selected directory' {
  $dir=Join-Path $TestDrive 'cancelled-dir'
  $script:answers.Enqueue('y'); $script:answers.Enqueue($dir); $script:answers.Enqueue('')
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns).Status | Should -Be 'Cancelled'
  Test-Path $dir | Should -BeFalse
 }
 It 'saves only the disclosed four files in the chosen named folder' {
  $r=Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $TestDrive -BundleName 'chosen-bundle' -NoInteractive
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Coverage.csv','Grants.csv','Links.csv','Run.json')
  (Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json).Status | Should -Be 'CompletedWithinDeclaredScope'
 }
 It 'preserves headers for empty tables' {
  $r=Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $TestDrive -BundleName 'empty-tables' -NoInteractive
  (Get-Content (Join-Path $r.ReportFolder 'Coverage.csv') -First 1) | Should -Be '"Status","Detail"'
 }
 It 'refuses to overwrite or merge with an existing bundle' {
  $dir=Join-Path $TestDrive 'existing-bundle'; $null=New-Item -ItemType Directory $dir
  Set-Content (Join-Path $dir 'keep.txt') 'original'
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $TestDrive -BundleName 'existing-bundle' -NoInteractive -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  @(Get-ChildItem $dir -File).Count | Should -Be 1
 }
 It 'refuses repository-local destinations' {
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $root -BundleName 'forbidden' -NoInteractive -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  Test-Path (Join-Path $root 'forbidden') | Should -BeFalse
 }
 It 'refuses path traversal in bundle names' {
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $TestDrive -BundleName '../outside' -NoInteractive -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
 }
 It 'does not prompt or save by default in noninteractive mode' {
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
 }
 It 'does not create a missing noninteractive parent directory' {
  $dir=Join-Path $TestDrive 'missing-auto'
  (Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $dir -BundleName 'report' -NoInteractive -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  Test-Path $dir | Should -BeFalse
 }
 It 'buffers rows without invoking export or directory creation' {
  Mock Export-Csv { throw 'Unapproved file write' }; Mock New-Item { throw 'Unapproved directory write' }
  Write-SARRow -Context $script:context -File 'Links.csv' -Row ([pscustomobject]@{Name='link'})
  $script:context.Rows['Links.csv'].Count | Should -Be 1
  Should -Invoke Export-Csv -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'stops at the explicit memory row limit without spilling to disk' {
  $ctx=New-SARMemoryContext -Mode All -MaxRows 1
  Write-SARRow $ctx 'Coverage.csv' ([pscustomobject]@{Status='First'})
  { Write-SARRow $ctx 'Coverage.csv' ([pscustomobject]@{Status='Second'}) } | Should -Throw '*row limit*'
  $ctx.Rows['Coverage.csv'].Count | Should -Be 1
  $ctx.OutputFailed | Should -BeTrue
 }
 It 'keeps export failure separate from scan status' {
  $r=Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory 'relative-dir' -BundleName 'report' -NoInteractive -WarningAction SilentlyContinue
  $r.Status | Should -Be 'ExportFailed'
  $script:manifest.Status | Should -Be 'CompletedWithinDeclaredScope'
 }
 It 'protects CSV cells without modifying the buffered raw data' {
  $script:context.Rows['Grants.csv'].Clear()
  $script:context.Rows['Grants.csv'].Add([pscustomobject]@{Name='=FORMULA';Value='Read'})
  $r=Export-ToolkitReportBundle -Tables $script:context.Rows -Manifest $script:manifest -Columns $script:columns -OutputDirectory $TestDrive -BundleName 'safe-csv' -NoInteractive
  (Import-Csv (Join-Path $r.ReportFolder 'Grants.csv')).Name | Should -Be "'=FORMULA"
  $script:context.Rows['Grants.csv'][0].Name | Should -Be '=FORMULA'
 }
 It 'removes disk-write commands from the scan orchestrator' {
  $tokens=$null; $errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Tools/Toolkit.SharePointAccessScanner.ps1'),[ref]$tokens,[ref]$errors)
  $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SARReport'},$true)
  $fn.Extent.Text | Should -Not -Match 'Get-M365OutputPath|Set-Content|New-Item|Move-Item|Initialize-SARCsv'
 }
}
Describe 'SharePoint scanner read-only integration' {
 BeforeEach {
  $script:displayed=[Collections.Generic.List[string]]::new()
  Mock Get-Module { $fakeCore } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest { @{webUrl='https://contoso.sharepoint.com'} }
  Mock Get-PnPAccessToken { 'offline-token-placeholder' }
  Mock Assert-SARToken {}
  Mock Get-PnPTenantSite { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test';Template='GROUP#0'} }
  Mock Connect-PnPOnline { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test'} }
  Mock Get-PnPWeb { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test';Title='Test'} }
  Mock Get-PnPSiteCollectionAdmin { @() }
  Mock Read-SARRoles { Write-SARRow $Context 'Grants.csv' ([pscustomobject]@{SiteUrl=$Site;PrincipalTitle='Example';RoleNames='Read'}); $Context.GrantRows++ }
  Mock Show-M365Results { $script:displayed.Add($Title) }
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  Mock New-Item { throw 'Scan must not create directories' }
 }
 It 'displays all tables and returns raw data without saving' {
  $r=Invoke-SARReport -TaskId 'sharepoint.get-sharepointaccessreport' -Mode All -SiteUrls 'https://contoso.sharepoint.com/sites/test' -ScanScope RootWeb -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Declined'
  $r.ReportFolder | Should -BeNullOrEmpty
  @($r.Grants).Count | Should -Be 1
  $script:displayed.Count | Should -Be 3
  Should -Invoke New-Item -Times 0
 }
 It 'supports no-prompt no-save noninteractive scanning' {
  $r=Invoke-SARReport -TaskId 'sharepoint.get-sharepointaccessreport' -Mode All -SiteUrls 'https://contoso.sharepoint.com/sites/test' -ScanScope RootWeb -NoInteractive -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
}
