BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.OffboardingDeletionChecks.ps1')
 function Get-MgContext { [CmdletBinding()]param() throw 'Unmocked context blocked' }
 function Get-MgRequestContext { [CmdletBinding()]param() throw 'Unmocked retry access blocked' }
 function Set-MgRequestContext { [CmdletBinding(SupportsShouldProcess)]param([int]$MaxRetry) throw 'Unmocked retry update blocked' }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked cloud call blocked' }
 function Connect-MgGraph { [CmdletBinding()]param($TenantId,$ClientId,$Environment,$Scopes,$ContextScope,[switch]$NoWelcome) throw 'Unmocked login blocked' }
 function New-VerificationHttpError {
  param([int]$Code,[int]$RetryAfter=0)
  $e=[Exception]::new('Synthetic HTTP error')
  $e | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue $Code
  if ($RetryAfter) { $e | Add-Member -NotePropertyName ResponseHeaders -NotePropertyValue @{'Retry-After'=[string]$RetryAfter} }
  return $e
 }
}
Describe 'Delete and verification share one retry-context lifetime' {
 BeforeEach {
  $script:retry=3; $script:events=[Collections.Generic.List[string]]::new(); $script:verificationCalls=0
  $script:target=[guid]'33333333-3333-3333-3333-333333333333'
  Mock Get-MgContext { [pscustomobject]@{TenantId='11111111-2222-3333-4444-555555555555';ClientId='99999999-8888-7777-6666-555555555555';Account='admin@contoso.com';Environment='Global';AuthType='Delegated';TokenCredentialType='InteractiveBrowser';Scopes=@('User.Read','User.ReadWrite.All')} }
  Mock Get-MgRequestContext { [pscustomobject]@{MaxRetry=$script:retry} }
  Mock Set-MgRequestContext { $script:retry=$MaxRetry; $script:events.Add("retry=$MaxRetry") }
  Mock Start-Sleep {}
  Mock Connect-MgGraph {}
  Mock Read-Host { 'n' }
  Mock Invoke-MgGraphRequest {
   if ($Method -eq 'DELETE') { $script:events.Add('DELETE'); return }
   if ($Uri -like '*/directory/deletedItems/*') {
    $script:verificationCalls++
    $script:events.Add("verify:retry=$script:retry")
    return @{id=$script:target.ToString();'@odata.type'='#microsoft.graph.user'}
   }
   if ($Uri -like '*/organization?*') { return [pscustomobject]@{value=@([pscustomobject]@{id='11111111-2222-3333-4444-555555555555'})} }
   return [pscustomobject]@{id='22222222-2222-2222-2222-222222222222';userPrincipalName='admin@contoso.com'}
  }
 }
 It 'verifies before retry restoration and sends DELETE exactly once' {
  $r=Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } -AfterDelete { Test-WF7BDeletedUser -UserId $script:target }
  $r.Status | Should -Be 'Success'
  ($script:events -join ',') | Should -Be 'retry=0,DELETE,verify:retry=0,retry=3'
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'returns VerificationIncomplete and stops after one URI failure' {
  Mock Invoke-MgGraphRequest { throw [UriFormatException]::new('Synthetic credential URI failure') } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } -AfterDelete { Test-WF7BDeletedUser -UserId $script:target }
  $r.Status | Should -Be 'VerificationIncomplete'
  $r.ReadAttempts | Should -Be 1
  $r.Detail | Should -Match 'Do not retry deletion'
  $script:retry | Should -Be 3
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  Should -Invoke Start-Sleep -Times 0
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'bounds 404 read retries and never resends DELETE' {
  Mock Invoke-MgGraphRequest { throw (New-VerificationHttpError 404) } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } -AfterDelete { Test-WF7BDeletedUser -UserId $script:target }
  $r.Status | Should -Be 'VerificationIncomplete'
  $r.ReadAttempts | Should -Be 4
  Should -Invoke Start-Sleep -Times 3 -Exactly
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
 }
 It 'allows a later verification read to succeed' {
  Mock Invoke-MgGraphRequest {
   $script:verificationCalls++
   if ($script:verificationCalls -lt 3) { throw (New-VerificationHttpError 404) }
   @{id=$script:target.ToString();'@odata.type'='#microsoft.graph.user'}
  } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Test-WF7BDeletedUser -UserId $script:target
  $r.Status | Should -Be 'Success'
  $r.ReadAttempts | Should -Be 3
 }
 It 'does not retry 403 permission failures' {
  Mock Invoke-MgGraphRequest { throw (New-VerificationHttpError 403) } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Test-WF7BDeletedUser -UserId $script:target
  $r.ReadAttempts | Should -Be 1
  $r.Status | Should -Be 'VerificationIncomplete'
  Should -Invoke Start-Sleep -Times 0
 }
 It 'does not retry unknown failures' {
  Mock Invoke-MgGraphRequest { throw 'Synthetic unknown error' } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  (Test-WF7BDeletedUser -UserId $script:target).ReadAttempts | Should -Be 1
  Should -Invoke Start-Sleep -Times 0
 }
 It 'honors Retry-After for throttled reads' {
  Mock Invoke-MgGraphRequest { throw (New-VerificationHttpError 429 20) } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Test-WF7BDeletedUser -UserId $script:target
  $r.Status | Should -Be 'VerificationIncomplete'
  Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -ge 20 }
 }
 It 'does not violate long server retry delays' {
  Mock Invoke-MgGraphRequest { throw (New-VerificationHttpError 429 120) } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $r=Test-WF7BDeletedUser -UserId $script:target
  $r.ReadAttempts | Should -Be 1
  Should -Invoke Start-Sleep -Times 0
 }
 It 'rejects mismatched deleted-object IDs' {
  Mock Invoke-MgGraphRequest { @{id='44444444-4444-4444-4444-444444444444';'@odata.type'='#microsoft.graph.user'} } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  (Test-WF7BDeletedUser -UserId $script:target).Status | Should -Be 'VerificationIncomplete'
 }
 It 'rejects non-user deleted objects' {
  Mock Invoke-MgGraphRequest { @{id=$script:target.ToString();'@odata.type'='#microsoft.graph.group'} } -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  (Test-WF7BDeletedUser -UserId $script:target).Status | Should -Be 'VerificationIncomplete'
 }
 It 'never retries a failed DELETE and restores context' {
  Mock Invoke-MgGraphRequest { throw [TimeoutException]::new('Synthetic uncertain deletion') } -ParameterFilter { $Method -eq 'DELETE' }
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } -AfterDelete { Test-WF7BDeletedUser -UserId $script:target } } | Should -Throw '*Request may have been sent*'
  Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/directory/deletedItems/*' }
  $script:retry | Should -Be 3
 }
 It 'converts callback failures into verification-incomplete outcomes' {
  $r=Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $true } -AfterDelete { throw 'Synthetic verification callback failure' }
  $r.Status | Should -Be 'VerificationIncomplete'
  $script:retry | Should -Be 3
 }
 It 'does not delete if final approval fails' {
  { Invoke-WF7BDeleteOnce -UserId $script:target -BeforeDelete { $false } -AfterDelete { Test-WF7BDeletedUser -UserId $script:target } } | Should -Throw '*did not approve*'
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
  $script:retry | Should -Be 3
 }
 It 'wires structured verification into the child task and removes the old external read loop' {
  $source=Get-Content -LiteralPath (Join-Path $root 'Scripts/Users/Remove-OffboardedUser.ps1') -Raw
  $source | Should -Match '\$verification=Invoke-WF7BDeleteOnce'
  $source | Should -Match '\-AfterDelete\s*\{\s*Test-WF7BDeletedUser'
  $source | Should -Not -Match '\$verified=\$false'
  $source | Should -Match 'VerificationIncomplete'
 }
}
