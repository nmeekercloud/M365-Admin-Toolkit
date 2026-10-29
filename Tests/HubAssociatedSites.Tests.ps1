BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.HubAssociatedSites.Helpers.ps1')
 . (Join-Path $root 'Tools/Toolkit.Catalog.ps1')
 $scriptPath=Join-Path $root 'Scripts/SharePoint/Get-HubAssociatedSites.ps1'
 function Get-PnPHubSite { [CmdletBinding()]param($Identity,$Connection) throw 'Unmocked hub read blocked' }
 function Get-PnPHubSiteChild { [CmdletBinding()]param($Identity,$Connection) throw 'Unmocked association read blocked' }
 function Get-PnPTenantSite { [CmdletBinding()]param($Identity,[switch]$Detailed,$Connection) throw 'Unmocked metadata read blocked' }
 function Get-MgContext { [CmdletBinding()]param() }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph call blocked' }
 function Assert-M365TaskAccess { param($AccessMode,$TaskId) }
 function Assert-M365Connection { param($Service,$GraphScopes,$TaskId,$TaskName) }
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Export-M365Csv { param($InputObject,$ReportName,$Path,[switch]$NoInteractive,[switch]$Overwrite,[switch]$PassThru) throw 'Unmocked export blocked' }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 $fakeCore=New-Module -Name HubReportOfflineCore -ScriptBlock {
  $script:M365Session=[pscustomobject]@{SharePoint=[pscustomobject]@{Connection=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}}}
 }
}
Describe 'Hub association inventory' {
 BeforeEach {
  $script:hub=[pscustomobject]@{ID='11111111-2222-3333-4444-555555555555';Title='Hub';SiteUrl='https://contoso.sharepoint.com/sites/hub'}
  $script:connection=[pscustomobject]@{Url='https://contoso-admin.sharepoint.com'}
  Mock Get-PnPHubSiteChild { 'https://contoso.sharepoint.com/sites/team1';'https://contoso.sharepoint.com/sites/team2' }
  Mock Get-PnPTenantSite { [pscustomobject]@{Url=$Identity;Title='Team';SiteId='22222222-2222-2222-2222-222222222222';HubSiteId='11111111-2222-3333-4444-555555555555'} }
 }
 It 'lists both associations with titles and confirmed hub IDs' {
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Sites.Count | Should -Be 2
  $r.Metadata.ConfirmedBySiteMetadata | Should -Be 2
  $r.Metadata.Status | Should -Be 'CompletedWithinDeclaredScope'
 }
 It 'deduplicates URLs case-insensitively and excludes the hub itself' {
  Mock Get-PnPHubSiteChild { 'https://contoso.sharepoint.com/sites/hub';'https://contoso.sharepoint.com/sites/team1';'https://CONTOSO.sharepoint.com/sites/team1/' }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Sites.Count | Should -Be 1
  $r.Metadata.HubSelfEntriesRemoved | Should -Be 1
  $r.Metadata.DuplicateUrlsRemoved | Should -Be 1
 }
 It 'retains site URLs if metadata lookup fails' {
  Mock Get-PnPTenantSite { throw 'Synthetic metadata denial' }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Sites.Count | Should -Be 2
  $r.Sites[0].DetailStatus | Should -Be 'LookupFailed'
  $r.Metadata.Status | Should -Be 'CompleteWithDetailGaps'
 }
 It 'does not report a failed hub query as a complete zero-site inventory' {
  Mock Get-PnPHubSiteChild { throw 'Synthetic enumeration denial' }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Metadata.EnumerationStatus | Should -Be 'Incomplete'
  $r.Metadata.Status | Should -Be 'PartialCoverage'
  $r.ExportRows[0].RecordType | Should -Be 'HubSummary'
 }
 It 'retains streamed records when enumeration later fails' {
  Mock Get-PnPHubSiteChild { Write-Output 'https://contoso.sharepoint.com/sites/team1'; throw 'Synthetic later read failure' }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Metadata.EnumerationStatus | Should -Be 'Incomplete'
  $r.Sites.Count | Should -Be 1
 }
 It 'returns an exportable summary for a genuinely empty hub' {
  Mock Get-PnPHubSiteChild { @() }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Metadata.EnumerationStatus | Should -Be 'Complete'
  $r.Metadata.ReportedSiteCount | Should -Be 0
  $r.ExportRows.Count | Should -Be 1
 }
 It 'keeps cross-host association evidence without querying that host' {
  Mock Get-PnPHubSiteChild { 'https://contosoeur.sharepoint.com/sites/team' }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Sites[0].DetailStatus | Should -Be 'CrossHostNotQueried'
  Should -Invoke Get-PnPTenantSite -Times 0
 }
 It 'marks site metadata that no longer points to the selected hub' {
  Mock Get-PnPTenantSite { [pscustomobject]@{Url=$Identity;Title='Team';HubSiteId=[guid]::Empty} }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Sites[0].AssociationState | Should -Be 'ChangedOrMismatched'
 }
 It 'retains malformed results as diagnostics rather than dropping them silently' {
  Mock Get-PnPHubSiteChild { [pscustomobject]@{Unknown='value'} }
  $r=Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com'
  $r.Metadata.Status | Should -Be 'PartialCoverage'
  $r.Diagnostics.Count | Should -Be 1
 }
 It 'handles object-shaped URL results as well as URL strings' {
  Mock Get-PnPHubSiteChild { [pscustomobject]@{SiteUrl='https://contoso.sharepoint.com/sites/team1'} }
  (Get-HARAssociatedSites -Hub $script:hub -Connection $script:connection -RootHost 'contoso.sharepoint.com').Sites.Count | Should -Be 1
 }
 It 'rejects unsafe or wrong-host selected hub URLs' {
  { ConvertTo-HARUrl 'https://other.sharepoint.com/sites/hub' 'contoso.sharepoint.com' } | Should -Throw '*verified*'
  { ConvertTo-HARUrl 'https://name@contoso.sharepoint.com/sites/hub' 'contoso.sharepoint.com' } | Should -Throw '*HTTPS*'
 }
 It 'registers the new read-only task in the SharePoint catalog' {
  $catalog=@(Get-ToolkitCatalog -Root $root)
  $tasks=@(($catalog | Where-Object Id -eq 'sharepoint').Tasks)
  $entry=@($tasks | Where-Object Id -eq 'sharepoint.hub-associated-sites')
  $entry.Count | Should -Be 1
  $entry[0].AccessMode | Should -Be 'ReadOnly'
  $entry[0].Order | Should -Be 80
 }
}
Describe 'Hub report display/export integration' {
 BeforeEach {

  Mock Get-Module { $fakeCore } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com'} }
  Mock Get-MgContext { [pscustomobject]@{Environment='Global'} }
  Mock Invoke-MgGraphRequest { @{webUrl='https://contoso.sharepoint.com'} }
  Mock Get-PnPHubSite { [pscustomobject]@{ID='11111111-2222-3333-4444-555555555555';Title='Hub';SiteUrl='https://contoso.sharepoint.com/sites/hub'} }
  Mock Get-PnPHubSiteChild { 'https://contoso.sharepoint.com/sites/team1' }
  Mock Get-PnPTenantSite { [pscustomobject]@{Url=$Identity;Title='Team';HubSiteId='11111111-2222-3333-4444-555555555555'} }
  Mock Show-M365Results {}
  Mock Export-M365Csv { [pscustomobject]@{Status='Declined';Path=$null;Error=$null} }
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Read-Host { throw 'Unexpected prompt' }
 }
 It 'displays associated sites before offering optional export' {
  $r=& $scriptPath -ReportMode Associations -HubUrl 'https://contoso.sharepoint.com/sites/hub' -PassThru -Confirm:$false
  Should -Invoke Show-M365Results -Times 1 -Exactly -ParameterFilter { $Title -like 'Sites reported as directly associated*' }
  Should -Invoke Export-M365Csv -Times 1 -Exactly -ParameterFilter { $ReportName -eq 'HubAssociatedSites' -and $InputObject.Count -eq 2 }
  # Verify ordering without mutable script-scope state in mocks.
  $entrypoint=Get-Content -LiteralPath $scriptPath -Raw
  $displayPosition=$entrypoint.IndexOf('Show-M365Results -InputObject @($report.Sites)',[StringComparison]::Ordinal)
  $exportPosition=$entrypoint.IndexOf('$export=Export-M365Csv',[StringComparison]::Ordinal)
  $displayPosition | Should -BeGreaterThan -1
  $exportPosition | Should -BeGreaterThan $displayPosition
  $r.ExportStatus | Should -Be 'Declined'
 }
 It 'passes noninteractive no-save intent through to the shared exporter' {
  $r=& $scriptPath -ReportMode Associations -HubUrl 'https://contoso.sharepoint.com/sites/hub' -NoInteractive -PassThru -Confirm:$false
  Should -Invoke Export-M365Csv -Times 1 -Exactly -ParameterFilter { $NoInteractive -and -not $Path }
  Should -Invoke Read-Host -Times 0
 }
 It 'requires a hub URL for noninteractive execution before connecting' {
  { & $scriptPath -ReportMode Associations -NoInteractive -Confirm:$false } | Should -Throw '*HubUrl is required*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'preserves raw results when export fails' {
  Mock Export-M365Csv { [pscustomobject]@{Status='ExportFailed';Path=$null;Error='Synthetic save error'} }
  $r=& $scriptPath -ReportMode Associations -HubUrl 'https://contoso.sharepoint.com/sites/hub' -PassThru -Confirm:$false
  $r.Metadata.ReportedSiteCount | Should -Be 1
  $r.ExportStatus | Should -Be 'ExportFailed'
 }
 It 'registers no direct file-write commands in the report entrypoint' {
  Get-Content $scriptPath -Raw | Should -Not -Match 'Export-Csv|Set-Content|New-Item|Add-Content|Get-M365OutputPath'
 }
 It 'supports selecting a hub from the interactive numbered list' {
  Mock Read-Host { '1' }
  $r=& $scriptPath -ReportMode Associations -PassThru -Confirm:$false
  $r.Metadata.HubUrl | Should -Be 'https://contoso.sharepoint.com/sites/hub'
  Should -Invoke Get-PnPHubSite -Times 1 -Exactly -ParameterFilter { -not $Identity }
 }
}
