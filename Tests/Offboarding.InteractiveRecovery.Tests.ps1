BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.OffboardingDeletionChecks.ps1')
 # Local stubs prevent module autoload/network access. All cloud commands are mocked.
 function Write-M365Log { param($Message,$Level) throw 'Unmocked log call blocked' }
 function Get-MgContext { [CmdletBinding()]param() throw 'Unmocked context access blocked' }
 function Get-MgRequestContext { [CmdletBinding()]param() throw 'Unmocked retry context blocked' }
 function Set-MgRequestContext { [CmdletBinding(SupportsShouldProcess)]param([int]$MaxRetry) throw 'Unmocked retry update blocked' }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked network request blocked' }
 function Connect-MgGraph { [CmdletBinding()]param($TenantId,$ClientId,$Environment,$Scopes,$ContextScope,[switch]$NoWelcome) throw 'Unmocked authentication blocked' }
}
Describe 'Single-send deletion interactive recovery' {
 BeforeEach {
  $script:retry=3; $script:readCount=0; $script:failRead=$false; $script:failAgain=$false
  $script:identity=[pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';ClientId='99999999-8888-7777-6666-555555555555';Account='admin@contoso.com';Environment='Global';AuthType='Delegated';TokenCredentialType='InteractiveBrowser';Scopes=@('User.Read','User.ReadWrite.All')}
  Mock Get-MgContext { $script:identity }
  Mock Get-MgRequestContext { [pscustomobject]@{MaxRetry=$script:retry} }
  Mock Set-MgRequestContext { $script:retry=$MaxRetry }
  Mock Connect-MgGraph {}
  Mock Read-Host { throw 'Unexpected toolkit confirmation prompt' }
  Mock Write-M365Log {}
  Mock Invoke-MgGraphRequest {
   if ($Method -eq 'DELETE') { return }
   if ($Uri -like '*/organization?*') { return [pscustomobject]@{value=@([pscustomobject]@{id='11111111-2222-3333-4444-555555555555'})} }
   $script:readCount++
   if ($script:failRead -and ($script:readCount -eq 1 -or $script:failAgain)) { throw [System.UriFormatException]::new('Simulated SDK credential URI failure') }
   [pscustomobject]@{id='22222222-2222-2222-2222-222222222222';userPrincipalName='admin@contoso.com'}
  }
  $script:target=[guid]'33333333-3333-3333-3333-333333333333'
 }
 It 'sends DELETE once on a healthy connection and restores retry settings' {
  Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true }
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'https://graph.microsoft.com/v1.0/users/33333333-3333-3333-3333-333333333333' }
  Should -Invoke Connect-MgGraph -Times 0
  $script:retry | Should -Be 3
 }
 It 'reconnects once interactively before DELETE and retains identity parameters' {
  $script:failRead=$true
  Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true }
  Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $TenantId -eq '11111111-2222-3333-4444-555555555555' -and $ClientId -eq '99999999-8888-7777-6666-555555555555' -and $Environment -eq 'Global' -and $ContextScope -eq 'Process' -and $Scopes -contains 'User.ReadWrite.All' }
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
  Should -Invoke Read-Host -Times 0 -Exactly
  Should -Invoke Write-M365Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Info' -and $Message -like 'Refreshing Graph sign-in*' }
  $script:readCount | Should -Be 2
  $script:retry | Should -Be 3
 }
 It 'blocks if Microsoft interactive reconnect is cancelled without prompting again' {
  $script:failRead=$true
  Mock Connect-MgGraph { throw [OperationCanceledException]::new('Simulated Microsoft sign-in cancellation') }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*sign-in cancellation*'
  Should -Invoke Connect-MgGraph -Times 1 -Exactly
  Should -Invoke Read-Host -Times 0 -Exactly
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
  $script:retry | Should -Be 3
 }
 It 'does not reconnect indefinitely' {
  $script:failRead=$true; $script:failAgain=$true
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*AfterReconnect*'
  Should -Invoke Connect-MgGraph -Times 1 -Exactly
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'does not retry DELETE on timeout' {
  Mock Invoke-MgGraphRequest { throw [TimeoutException]::new('Simulated uncertain DELETE') } -ParameterFilter { $Method -eq 'DELETE' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*Request may have been sent*'
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
  Should -Invoke Connect-MgGraph -Times 0
 }
 It 'blocks a changed account during reconnect' {
  $script:failRead=$true; Mock Connect-MgGraph { $script:identity.Account='other@contoso.com' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*identity changed*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks a changed tenant during reconnect' {
  $script:failRead=$true; Mock Connect-MgGraph { $script:identity.TenantId='44444444-4444-4444-4444-444444444444' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*identity changed*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks a device-code flow substituted during recovery' {
  $script:failRead=$true; Mock Connect-MgGraph { $script:identity.TokenCredentialType='DeviceCode' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*another flow*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks if reconnect reenables SDK retries' {
  $script:failRead=$true; Mock Connect-MgGraph { $script:retry=3 }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*retry policy*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks an expired approval after reconnect' {
  $script:failRead=$true
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { throw 'Workflow approval expired' } } | Should -Throw '*approval expired*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks a negative final target check' {
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $false } } | Should -Throw '*did not approve*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'does not reconnect for unrelated read errors' {
  Mock Invoke-MgGraphRequest { throw 'Simulated forbidden' } -ParameterFilter { $Method -eq 'GET' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*forbidden*'
  Should -Invoke Connect-MgGraph -Times 0
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'blocks a missing account in the initial context' {
  $script:identity.Account=''
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } } | Should -Throw '*complete delegated*'
  Should -Invoke Invoke-MgGraphRequest -Times 0
 }
 It 'blocks empty immutable target IDs' {
  { Invoke-WF7BDeleteOnce -UserId ([guid]::Empty) -BeforeDelete { $true } } | Should -Throw '*Empty deletion target*'
  Should -Invoke Invoke-MgGraphRequest -Times 0
 }
 It 'checks final approval after authentication reads and before DELETE' {
  $script:finalReadCount=0
  Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $script:finalReadCount=$script:readCount; $true }
  $script:finalReadCount | Should -BeGreaterThan 0
 }
}
