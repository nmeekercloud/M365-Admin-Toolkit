BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.HubAssociatedSites.Helpers.ps1')
 . (Join-Path $root 'Tools/Toolkit.HubNavigationDiscovery.Helpers.ps1')
 function Get-PnPTenantSite { [CmdletBinding()]param($Connection,[switch]$Detailed) throw 'Unmocked read blocked' }
 function Get-PnPHubSite { [CmdletBinding()]param($Connection) throw 'Unmocked read blocked' }
 function Connect-PnPOnline { [CmdletBinding()]param($Url,$AccessToken,[switch]$ReturnConnection) throw 'Unmocked connection blocked' }
 function Get-PnPWeb { [CmdletBinding()]param($Includes,$Connection) throw 'Unmocked web read blocked' }
 function Get-PnPNavigationNode { [CmdletBinding()]param($Location,$Connection) throw 'Unmocked menu read blocked' }
 function Get-PnPProperty { [CmdletBinding()]param($ClientObject,$Property,$Connection) throw 'Unmocked child read blocked' }
 function Get-PnPAccessToken { [CmdletBinding()]param($ResourceTypeName,$Connection) throw 'Unmocked token read blocked' }
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Export-M365Csv { param($InputObject,$ReportName,$Path,[switch]$NoInteractive,[switch]$Overwrite,[switch]$PassThru) throw 'Unmocked export blocked' }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function New-TestMenuNode { param($Id,$Title,$Url,[object[]]$Children=@()) [pscustomobject]@{Id=$Id;Title=$Title;Url=$Url;Children=$Children} }
}
Describe 'Hub navigation discovery' {
 BeforeEach {
  $script:selected=[pscustomobject]@{Title='Home';SiteUrl='https://contoso.sharepoint.com';ID='11111111-2222-3333-4444-555555555555'}
  $script:admin=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}
  Mock Assert-HNDToken {}
  Mock Get-PnPTenantSite {
   [pscustomobject]@{Url='https://contoso.sharepoint.com';Title='Home'}
   [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/hubB';Title='Hub B'}
   [pscustomobject]@{Url='https://contoso.sharepoint.com/sites/hr';Title='HR'}
  }
  Mock Get-PnPHubSite {
   [pscustomobject]@{SiteUrl='https://contoso.sharepoint.com';Title='Home'}
   [pscustomobject]@{SiteUrl='https://contoso.sharepoint.com/sites/hubB';Title='Hub B'}
  }
  Mock Connect-PnPOnline { [pscustomobject]@{Url=$Url} }
  Mock Get-PnPWeb { [pscustomobject]@{Url=$Connection.Url} }
  Mock Get-PnPProperty {}
  Mock Get-PnPNavigationNode {
   if ($Connection.Url -eq 'https://contoso.sharepoint.com') {
    New-TestMenuNode 1 'Departments' '#' @((New-TestMenuNode 2 'Hub B' '/sites/hubB'))
   } else {
    New-TestMenuNode 3 'HR' '/sites/hr/SitePages/Home.aspx'
    New-TestMenuNode 4 'Home' 'https://contoso.sharepoint.com'
   }
  }
 }
 It 'follows linked hub menus and finds their sites without granting access' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  $r.Metadata.DistinctSitesIncludingStart | Should -Be 3
  $r.Metadata.HubMenusRead | Should -Be 2
  @($r.Sites | Where-Object SiteUrl -eq 'https://contoso.sharepoint.com/sites/hr').Count | Should -Be 1
 }
 It 'does not revisit hub cycles' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  Should -Invoke Connect-PnPOnline -Times 2 -Exactly
 }
 It 'keeps a navigation trail through submenu headings' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  ($r.Sites | Where-Object SiteUrl -eq 'https://contoso.sharepoint.com/sites/hr').NavigationPath | Should -Match 'Home > Departments > Hub B > HR'
 }
 It 'does not crawl ordinary sites menus' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  Should -Invoke Connect-PnPOnline -Times 0 -ParameterFilter { $Url -eq 'https://contoso.sharepoint.com/sites/hr' }
 }
 It 'reports linked-hub depth truncation explicitly' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline' -MaxHubDepth 0
  $r.Metadata.Status | Should -Be 'PartialCoverage'
  $r.Metadata.HubMenusRead | Should -Be 1
  @($r.Sites | Where-Object SiteUrl -eq 'https://contoso.sharepoint.com/sites/hubB').Count | Should -Be 1
 }
 It 'stops at the global node limit and flags incomplete discovery' {
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline' -MaxNavigationNodes 1
  $r.Metadata.Status | Should -Be 'PartialCoverage'
  $r.Metadata.NavigationNodesProcessed | Should -Be 1
 }
 It 'retains other sites when a linked hub menu is inaccessible' {
  Mock Get-PnPNavigationNode { throw 'Synthetic access denial' } -ParameterFilter { $Connection.Url -like '*/sites/hubB' }
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  $r.Metadata.Status | Should -Be 'PartialCoverage'
  $r.Metadata.DistinctSitesIncludingStart | Should -Be 2
 }
 It 'does not label failed hub-catalog enumeration as complete' {
  Mock Get-PnPHubSite { throw 'Synthetic hub catalog failure' }
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  $r.Metadata.HubCatalogComplete | Should -BeFalse
  $r.Metadata.Status | Should -Be 'PartialCoverage'
 }
 It 'retains links but never queries other-host destinations' {
  Mock Get-PnPNavigationNode { New-TestMenuNode 1 'Other' 'https://other.example/path?token=hidden' }
  $r=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  $r.Links[0].Status | Should -Be 'OtherHostNotScanned'
  $r.Links[0].NavigationUrl | Should -Not -Match 'token=hidden'
  Should -Invoke Connect-PnPOnline -Times 1 -Exactly
 }
 It 'has no scan-time file writes' {
  Mock New-Item { throw 'Unapproved directory write' }; Mock Export-Csv { throw 'Unapproved file write' }
  $null=Get-HNDNavigationReport -SelectedHub $script:selected -Admin $script:admin -RootHost 'contoso.sharepoint.com' -Token 'offline'
  Should -Invoke New-Item -Times 0
  Should -Invoke Export-Csv -Times 0
 }
}
Describe 'Navigation URL resolution' {
 BeforeAll { $inventory=@([pscustomobject]@{Url='https://contoso.sharepoint.com';Title='Home'},[pscustomobject]@{Url='https://contoso.sharepoint.com/sites/hr';Title='HR'},[pscustomobject]@{Url='https://contoso.sharepoint.com/sites/hrsecure';Title='HR Secure'}) }
 It 'maps document/page URLs to the containing site without prefix collisions' {
  (Resolve-HNDLink '/sites/hrsecure/Docs/file.docx' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/hrsecure'
 }
 It 'resolves relative links against the source hub' {
  (Resolve-HNDLink 'SitePages/Home.aspx' 'https://contoso.sharepoint.com/sites/hr' 'contoso.sharepoint.com' $inventory).SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/hr'
 }
 It 'does not assign an unknown managed-path site to the root site' {
  (Resolve-HNDLink '/sites/missing' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).Status | Should -Be 'Unresolved'
 }
 It 'recognizes submenu headings without inventing destinations' {
  (Resolve-HNDLink '#' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).Status | Should -Be 'HeadingOrAnchor'
 }
 It 'does not follow script or mail links' {
  (Resolve-HNDLink 'mailto:someone@example.test' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).Status | Should -Be 'NonWebLink'
 }
 It 'omits opaque sharing URLs rather than exporting redeemable tokens' {
  $r=Resolve-HNDLink 'https://contoso.sharepoint.com/:u:/s/hr/opaque-value' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory
  $r.Status | Should -Be 'OpaqueSharingOrRedirect'
  $r.NavigationUrl | Should -Not -Match 'opaque-value'
 }
 It 'understands direct resource sharing URL paths' {
  (Resolve-HNDLink '/:w:/r/sites/hr/Docs/file.docx?e=secret' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/hr'
 }
 It 'rejects credential-bearing or custom-port navigation URLs' {
  (Resolve-HNDLink 'https://name@contoso.sharepoint.com/sites/hr' 'https://contoso.sharepoint.com' 'contoso.sharepoint.com' $inventory).Status | Should -Be 'Unresolved'
 }
}
Describe 'Navigation discovery export integration' {
 BeforeEach {
  Mock Get-PnPAccessToken { 'offline' }
  Mock Assert-HNDToken {}
  Mock Get-HNDNavigationReport { [pscustomobject]@{Metadata=[pscustomobject]@{DistinctSitesIncludingStart=1;Status='CompletedWithinDeclaredScope';CoverageGaps=0};Sites=@((New-HNDRow @{RecordType='Site';SiteTitle='Home';SiteUrl='https://contoso.sharepoint.com'}));Links=@();Coverage=@();ExportRows=@((New-HNDRow @{RecordType='RunSummary'}))} }
  Mock Show-M365Results {}
  Mock Export-M365Csv { [pscustomobject]@{Status='Declined';Path=$null;Error=$null} }
  Mock Write-M365Log {}
  Mock Write-Host {}
 }
 It 'offers optional export after displaying the three discovery sections' {
  $r=Invoke-HNDNavigationDiscovery -SelectedHub @{} -Admin @{} -RootHost 'contoso.sharepoint.com' -Tenant ([pscustomobject]@{TenantId='test';Account='test'}) -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  Should -Invoke Show-M365Results -Times 3 -Exactly
  Should -Invoke Export-M365Csv -Times 1 -Exactly -ParameterFilter { $ReportName -eq 'HubNavigationDiscovery' }
 }
 It 'passes noninteractive no-save intent to the shared exporter' {
  $null=Invoke-HNDNavigationDiscovery -SelectedHub @{} -Admin @{} -RootHost 'contoso.sharepoint.com' -Tenant ([pscustomobject]@{TenantId='test';Account='test'}) -NoInteractive
  Should -Invoke Export-M365Csv -Times 1 -Exactly -ParameterFilter { $NoInteractive -and -not $Path }
 }
}
