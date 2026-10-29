BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/SharePoint/Export-SharePointStaffAccess.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked' }
 function Get-PnPTenantSite { [CmdletBinding()]param($Identity,$Connection) throw 'Unmocked tenant call blocked' }
 function Get-PnPAccessToken { [CmdletBinding()]param($ResourceTypeName,$Connection) throw 'Unmocked token call blocked' }
 function Connect-PnPOnline { [CmdletBinding()]param($Url,$AccessToken,[switch]$ReturnConnection) throw 'Unmocked connection blocked' }
 function Get-PnPWeb { [CmdletBinding()]param($Includes,$Connection) throw 'Unmocked web call blocked' }
 function Get-PnPSiteCollectionAdmin { [CmdletBinding()]param($Connection) throw 'Unmocked admin call blocked' }
 function Get-PnPProperty { [CmdletBinding()]param($ClientObject,$Property,$Connection) throw 'Unmocked property call blocked' }
 function Get-PnPGroupMember { [CmdletBinding()]param($Identity,$Connection) throw 'Unmocked group call blocked' }
 function Get-M365OutputPath { param($Type) throw 'Automatic output blocked' }
 $fakeCore=New-Module -Name Phase4OfflineCore -ScriptBlock {
  $script:M365Session=[pscustomobject]@{SharePoint=[pscustomobject]@{Connection=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}}}
 }
 if (Test-Path variable:global:M365Phase4TestState) { throw 'Reserved test variable already exists; use a fresh window.' }
 $global:M365Phase4TestState=[pscustomobject]@{Events=$null;Answers=$null}
}
AfterAll { Remove-Variable M365Phase4TestState -Scope Global -ErrorAction SilentlyContinue }
Describe 'Phase 4 staff site-access display-first output' {
 BeforeEach {
  $global:M365Phase4TestState.Events=[Collections.Generic.List[string]]::new()
  $global:M365Phase4TestState.Answers=[Collections.Generic.Queue[string]]::new()
  Mock Get-Module { $fakeCore } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest { @{webUrl='https://contoso.sharepoint.com'} }
  Mock Get-PnPTenantSite { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test';Title='Test';Template='GROUP#0'} }
  Mock Get-PnPAccessToken {
   $claims=@{tid='11111111-2222-3333-4444-555555555555';upn='admin@contoso.com';exp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+3600} | ConvertTo-Json -Compress
   $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($claims)).TrimEnd('=').Replace('+','-').Replace('/','_')
   'offline.'+$payload+'.unsigned'
  }
  Mock Connect-PnPOnline { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test'} }
  Mock Get-PnPWeb { [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/test';Title='Test';RoleAssignments=@()} }
  Mock Get-PnPSiteCollectionAdmin { [pscustomobject]@{Id=1;Title='=Example';LoginName='admin@contoso.com';PrincipalType='User'} }
  Mock Show-M365Results { $global:M365Phase4TestState.Events.Add('display') }
  Mock Read-Host {
   $global:M365Phase4TestState.Events.Add('prompt')
   if (-not $global:M365Phase4TestState.Answers.Count) { throw 'Unexpected prompt' }
   $global:M365Phase4TestState.Answers.Dequeue()
  }
  Mock Write-Host {}
  Mock Write-Progress {}
  Mock Write-M365Log {}
 }
 It 'displays both tables before asking to export and creates nothing when declined' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $global:M365Phase4TestState.Answers.Enqueue('n')
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Declined'
  ($global:M365Phase4TestState.Events -join ',') | Should -Be 'display,display,prompt'
  $r.AccessRows | Should -Be 1
  $r.Access[0].Title | Should -Be '=Example'
  $r.ReportFolder | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save in noninteractive mode by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'NotRequested'
  $r.Status | Should -Be 'CompletedWithinDeclaredScope'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only Access.csv Sites.csv and Run.json with safe CSV and raw passthrough' {
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory $TestDrive -ReportName 'access' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Access.csv','Run.json','Sites.csv')
  (Import-Csv (Join-Path $r.ReportFolder 'Access.csv')).Title | Should -Be "'=Example"
  $r.Access[0].Title | Should -Be '=Example'
 }
 It 'cancels an empty destination without losing rows' {
  $global:M365Phase4TestState.Answers.Enqueue('y');$global:M365Phase4TestState.Answers.Enqueue('')
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Cancelled'
  $r.AccessRows | Should -Be 1
 }
 It 'keeps export failure separate from scan completion' {
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -PassThru -Confirm:$false -WarningAction SilentlyContinue
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Status | Should -Be 'CompletedWithinDeclaredScope'
 }
 It 'retains failed-site coverage and excludes incomplete site grant rows' {
  Mock Get-PnPSiteCollectionAdmin { throw 'Synthetic denial' }
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.Status | Should -Be 'PartialCoverage'
  $r.Sites[0].ReadStatus | Should -Be 'Error'
  $r.AccessRows | Should -Be 0
  $r.ExportStatus | Should -Be 'NotRequested'
 }
 It 'preserves headers when there are no access rows' {
  Mock Get-PnPSiteCollectionAdmin { @() }
  $r=& $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  (Get-Content (Join-Path $r.ReportFolder 'Access.csv') -First 1) | Should -Match '^"SiteUrl","SiteTitle"'
 }
 It 'honors WhatIf before reading the token or writing output' {
  & $entry -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -WhatIf
  Should -Invoke Get-PnPAccessToken -Times 0
  Should -Invoke Show-M365Results -Times 0
 }
 It 'contains no automatic export or staging commands' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Get-M365OutputPath|Export-Csv|Set-Content|New-Item|Move-Item|Initialize-SACsv|\.partial'
 }
}
