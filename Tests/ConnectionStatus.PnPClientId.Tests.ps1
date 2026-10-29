BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Modules/M365Toolkit.Core/Public/Get-M365ConnectionStatus.ps1')
 . (Join-Path $root 'Modules/M365Toolkit.Core/Public/Show-M365ConnectionStatus.ps1')
 function Get-ToolkitGraphContext { throw 'Unmocked context read blocked' }
 function Get-ToolkitExchangeConnection { throw 'Unmocked context read blocked' }
 function Get-M365TenantInfo { param([switch]$Refresh) throw 'Unmocked tenant lookup blocked' }
 function Show-M365Header { param($Title) }
 function Get-M365LogPath { throw 'Legacy log-path creation must not be called' }
}
Describe 'PnP app client ID on status screen' {
 BeforeEach {
  $script:ToolkitFileLogPath=$null
  $script:ToolkitDefaultFileLogging=$false
  $script:M365Session=[pscustomobject]@{
   TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com'
   SharePoint=[pscustomobject]@{Connected=$true;ClientId='22222222-3333-4444-5555-666666666666';AdminUrl='https://contoso-admin.sharepoint.com'}
  }
  Mock Get-ToolkitGraphContext { $null }
  Mock Get-ToolkitExchangeConnection { $null }
  Mock Get-M365TenantInfo { $null }
  Mock Show-M365Header {}
  Mock Write-Host {}
  Mock Get-M365LogPath { throw 'Legacy log path was called' }
 }
 It 'returns the PnP app client ID as a separate SharePoint status property' {
  $sp=Get-M365ConnectionStatus | Where-Object Service -eq 'SharePoint'
  $sp.ClientId | Should -Be '22222222-3333-4444-5555-666666666666'
  $sp.Connected | Should -BeTrue
 }
 It 'prints the PnP app client ID when SharePoint is connected' {
  Show-M365ConnectionStatus
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq '  PnP app client ID: 22222222-3333-4444-5555-666666666666' }
 }
 It 'does not expose a stale app ID after SharePoint disconnects' {
  $script:M365Session.SharePoint.Connected=$false
  $sp=Get-M365ConnectionStatus | Where-Object Service -eq 'SharePoint'
  $sp.ClientId | Should -BeNullOrEmpty
  Show-M365ConnectionStatus
  Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*PnP app client ID*' }
 }
 It 'handles no tenant session without a client-ID line' {
  $script:M365Session=$null
  { Show-M365ConnectionStatus } | Should -Not -Throw
  Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*PnP app client ID*' }
 }
 It 'uses the SharePoint app ID rather than the Graph app ID' {
  Mock Get-ToolkitGraphContext { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';Account='admin@contoso.com';ClientId='99999999-8888-7777-6666-555555555555';Scopes=@('User.Read')} }
  Show-M365ConnectionStatus
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq '  PnP app client ID: 22222222-3333-4444-5555-666666666666' }
  Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*PnP app client ID*99999999*' }
 }
 It 'shows Unavailable for an empty stored PnP client ID without throwing' {
  $script:M365Session.SharePoint.ClientId=''
  Show-M365ConnectionStatus
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq '  PnP app client ID: Unavailable' }
 }
 It 'does not call the directory-creating legacy log helper when logging is off' {
  Show-M365ConnectionStatus
  Should -Invoke Get-M365LogPath -Times 0
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'File logging: Off' }
 }
 It 'shows the explicitly selected session-log destination without requesting a legacy path' {
  $script:ToolkitFileLogPath='selected-session.log'
  Show-M365ConnectionStatus
  Should -Invoke Get-M365LogPath -Times 0
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Log file: selected-session.log' }
 }
}
