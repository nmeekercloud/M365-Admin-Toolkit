BeforeAll {
 if (Test-Path variable:global:M365Phase3MockState) { throw 'Reserved test state already exists; use a fresh PowerShell window.' }
 $global:M365Phase3MockState=[pscustomobject]@{Answers=$null;Events=$null}
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph call blocked' }
 function Get-PnPTenant { [CmdletBinding()]param($Connection) throw 'Unmocked tenant call blocked' }
 function Get-PnPTenantSite { [CmdletBinding()]param($Identity,[switch]$Detailed,$Connection) throw 'Unmocked site call blocked' }
 function Get-M365OutputPath { param($Type) throw 'Automatic output-path creation is blocked in tests' }
 $fakeCore=New-Module -Name Phase3OfflineCore -ScriptBlock {
  $script:M365Session=[pscustomobject]@{SharePoint=[pscustomobject]@{Connection=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}}}
 }
 $configPath=Join-Path $root 'Scripts/SharePoint/Get-SharePointExternalSharingConfig.ps1'
 $storagePath=Join-Path $root 'Scripts/SharePoint/Get-SharePointStorageReport.ps1'
}
Describe 'SharePoint option 4/7 output migration' {
 BeforeEach {
  $global:M365Phase3MockState.Answers=[Collections.Generic.Queue[string]]::new()
  $global:M365Phase3MockState.Events=[Collections.Generic.List[string]]::new()
  Mock Read-Host {
   $global:M365Phase3MockState.Events.Add('prompt')
   if (-not $global:M365Phase3MockState.Answers.Count) { throw 'Unexpected prompt' }
   $global:M365Phase3MockState.Answers.Dequeue()
  }
  Mock Get-Module { $fakeCore } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest { @{webUrl='https://contoso.sharepoint.com'} }
  Mock Get-PnPTenant {
   $data=@{SharingCapability='ExternalUserSharingOnly'}
   foreach ($key in @('OneDriveSharingCapability','SharingDomainRestrictionMode','SharingAllowedDomainList','SharingBlockedDomainList','DefaultSharingLinkType','DefaultLinkPermission','RequireAcceptingAccountMatchInvitedAccount','PreventExternalUsersFromResharing','RequireAnonymousLinksExpireInDays')) { $data[$key]=$null }
   $data
  }
  Mock Get-PnPTenantSite {
   $data=@{Url='https://contoso.sharepoint.com/sites/test';Title='Test';Template='GROUP#0';Owner='owner@contoso.com';LockState='Unlock';LastContentModifiedDate='2026-10-28';StorageUsageCurrent=1024;StorageQuota=2048;StorageQuotaWarningLevel=1800;SharingCapability='ExternalUserSharingOnly'}
   foreach ($key in @('SharingDomainRestrictionMode','SharingAllowedDomainList','SharingBlockedDomainList','DefaultSharingLinkType','DefaultLinkPermission','OverrideTenantAnonymousLinkExpirationPolicy','AnonymousLinkExpirationInDays','OverrideTenantExternalUserExpirationPolicy','ExternalUserExpirationInDays')) { $data[$key]=$null }
   [pscustomobject]$data
  }
  Mock Show-M365Results { $global:M365Phase3MockState.Events.Add('display') }
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Write-Progress {}
 }
 It 'option 4 displays results first and declining export creates no folders' {
  Mock New-Item { throw 'Unexpected directory write' }
  $global:M365Phase3MockState.Answers.Enqueue('n')
  $r=& $configPath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Declined'
  $r.ReportFolder | Should -BeNullOrEmpty
  ($global:M365Phase3MockState.Events -join ',') | Should -Be 'display,display,prompt'
  Should -Invoke New-Item -Times 0
 }
 It 'option 7 displays results first and declining export creates no folders' {
  Mock New-Item { throw 'Unexpected directory write' }
  $global:M365Phase3MockState.Answers.Enqueue('')
  $r=& $storagePath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Declined'
  ($global:M365Phase3MockState.Events -join ',') | Should -Be 'display,prompt'
  Should -Invoke New-Item -Times 0
 }
 It 'option 4 supports no-prompt no-save execution' {
  $r=& $configPath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
 }
 It 'option 7 supports no-prompt no-save execution and preserves storage math' {
  $r=& $storagePath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'NotRequested'
  $r.Sites[0].UsedGiB | Should -Be 1
  $r.Sites[0].QuotaGiB | Should -Be 2
  $r.Sites[0].UtilizationPercent | Should -Be 50
  $r.Summary.KnownSelectedUsageGiB | Should -Be 1
  Should -Invoke Read-Host -Times 0
 }
 It 'option 4 exports only its declared three files' {
  $r=& $configPath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory $TestDrive -ReportName 'sharing-config' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Run.json','SiteSharing.csv','TenantSharing.csv')
 }
 It 'option 7 exports only its declared CSV and two JSON files' {
  $r=& $storagePath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory $TestDrive -ReportName 'storage-report' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Run.json','SiteStorage.csv','Summary.json')
  (Get-Content (Join-Path $r.ReportFolder 'Summary.json') -Raw | ConvertFrom-Json).KnownSelectedUsageGiB | Should -Be 1
 }
 It 'cancelling a sharing-config destination leaves results available' {
  $global:M365Phase3MockState.Answers.Enqueue('y'); $global:M365Phase3MockState.Answers.Enqueue('')
  $r=& $configPath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -PassThru -Confirm:$false
  $r.ExportStatus | Should -Be 'Cancelled'
  @($r.Sites).Count | Should -Be 1
 }
 It 'storage export failure does not change a completed report into read failure' {
  $r=& $storagePath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -ExportDirectory 'relative-path' -ReportName 'invalid' -PassThru -Confirm:$false -WarningAction SilentlyContinue
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Status | Should -Be 'CompletedWithinDeclaredScope'
 }
 It 'retains partial configuration results and warnings when a site read fails' {
  Mock Get-PnPTenantSite { throw 'Synthetic site read denial' }
  $r=& $configPath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.Status | Should -Be 'PartialConfigurationCoverage'
  $r.Sites[0].ReadStatus | Should -Be 'Error'
  $r.ExportStatus | Should -Be 'NotRequested'
 }
 It 'retains null storage metrics when site reads fail' {
  Mock Get-PnPTenantSite { throw 'Synthetic site read denial' }
  $r=& $storagePath -SiteUrls 'https://contoso.sharepoint.com/sites/test' -NoInteractive -PassThru -Confirm:$false
  $r.Status | Should -Be 'PartialMetricCoverage'
  $r.Sites[0].UsedGiB | Should -BeNullOrEmpty
  $r.Summary.AllSelectedUsageKnown | Should -BeFalse
 }
 It 'refuses path traversal in declared CSV filenames before any write' {
  $r=Export-ToolkitReportBundle -Tables @{'../escape.csv'=@()} -Columns @{'../escape.csv'=@('Name')} -Manifest @{Status='Complete'} -OutputDirectory $TestDrive -BundleName 'bad-csv' -NoInteractive -WarningAction SilentlyContinue
  $r.Status | Should -Be 'ExportFailed'
  Test-Path (Join-Path $TestDrive 'bad-csv') | Should -BeFalse
 }
 It 'refuses JSON filenames that replace the run manifest' {
  $r=Export-ToolkitReportBundle -Tables @{'Data.csv'=@()} -Columns @{'Data.csv'=@('Name')} -JsonFiles @{'Run.json'=@{Status='wrong'}} -Manifest @{Status='Complete'} -OutputDirectory $TestDrive -BundleName 'bad-json' -NoInteractive -WarningAction SilentlyContinue
  $r.Status | Should -Be 'ExportFailed'
  Test-Path (Join-Path $TestDrive 'bad-json') | Should -BeFalse
 }
 It 'requires explicit columns for each exported CSV' {
  $r=Export-ToolkitReportBundle -Tables @{'Data.csv'=@()} -Columns @{} -Manifest @{Status='Complete'} -OutputDirectory $TestDrive -BundleName 'no-columns' -NoInteractive -WarningAction SilentlyContinue
  $r.Status | Should -Be 'ExportFailed'
 }
 It 'removes automatic file-writing commands from both report entrypoints' {
  foreach ($path in @($configPath,$storagePath)) {
   $text=Get-Content -LiteralPath $path -Raw
   $text | Should -Not -Match 'Get-M365OutputPath|Export-Csv|Set-Content|New-Item|Move-Item|\.partial'
  }
 }
}

AfterAll { Remove-Variable -Name M365Phase3MockState -Scope Global -ErrorAction SilentlyContinue }
