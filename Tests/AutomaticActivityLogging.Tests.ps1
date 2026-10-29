BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $core=Join-Path $root 'Modules/M365Toolkit.Core'
 $script:ToolkitRoot=$root; $script:M365Session=$null
 . (Join-Path $core 'Private/ExternalPath.ps1')
 . (Join-Path $core 'Private/OutputControl.ps1')
 . (Join-Path $core 'Private/LogHelpers.ps1')
 . (Join-Path $core 'Public/Set-M365FileLogging.ps1')
 . (Join-Path $core 'Public/Get-M365LogPath.ps1')
 . (Join-Path $core 'Public/Write-M365Log.ps1')
 . (Join-Path $core 'Public/Show-M365ConnectionStatus.ps1')
 function Get-ToolkitDataRoot { return $script:testRoot }
 function Get-ToolkitSetting { param($Path,$Default) return $Default }
 function Get-ToolkitSessionLabel { 'no-tenant' }
 function Get-M365TenantInfo { param([switch]$Refresh) return $null }
 function Get-M365ConnectionStatus { return @() }
 function Show-M365Header { param($Title) }
}
Describe 'Automatic daily tenant-scoped activity logging' {
 BeforeEach {
  $script:testRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $script:ToolkitFileLogPath=$null; $script:ToolkitDefaultFileLogging=$true; $script:M365Session=$null
  Mock Read-Host { throw 'Unexpected automatic logging prompt' }
  Mock Write-Host {}
  Mock Get-M365TenantInfo { $null }
  Mock Get-M365ConnectionStatus { @() }
  Mock Show-M365Header {}
 }
 It 'private-state initialization enables defaults but does not create files on import' {
  . (Join-Path $core 'Private/OutputControl.ps1')
  $script:ToolkitDefaultFileLogging | Should -BeTrue
  Test-Path $script:testRoot | Should -BeFalse
 }
 It 'enabling the default through the launcher API requires no prompt or file selection' {
  Set-M365FileLogging -NoInteractive
  $script:ToolkitDefaultFileLogging | Should -BeTrue
  Should -Invoke Read-Host -Times 0
  Test-Path $script:testRoot | Should -BeFalse
 }
 It 'writes the first message to the expected default Logs directory' {
  Write-M365Log 'first automatic message' -Quiet
  $path=Get-M365LogPath
  [IO.Path]::GetDirectoryName($path) | Should -Be (Join-Path $script:testRoot 'Logs')
  [IO.Path]::GetFileName($path) | Should -Match '^\d{4}-\d{2}-\d{2}_no-tenant\.log$'
  Get-Content $path -Raw | Should -Match 'first automatic message'
  Should -Invoke Read-Host -Times 0
 }
 It 'follows the tenant label after switching instead of mixing default tenant logs' {
  Mock Get-ToolkitSessionLabel { 'tenant-a.onmicrosoft.com' }
  Write-M365Log 'tenant a message' -Quiet
  $a=Get-M365LogPath
  Mock Get-ToolkitSessionLabel { 'tenant-b.onmicrosoft.com' }
  Write-M365Log 'tenant b message' -Quiet
  $b=Get-M365LogPath
  $a | Should -Not -Be $b
  Get-Content $a -Raw | Should -Not -Match 'tenant b message'
  Get-Content $b -Raw | Should -Not -Match 'tenant a message'
 }
 It 'gives the log viewer the same folder used by the writer' {
  Write-M365Log 'viewer check' -Quiet
  (Get-M365LogPath -Folder) | Should -Be ([IO.Path]::GetDirectoryName((Get-M365LogPath)))
 }
 It 'honors an explicit disable without creating a default directory' {
  Set-M365FileLogging -Disable
  Write-M365Log 'not persisted' -Level Error -Quiet
  Test-Path $script:testRoot | Should -BeFalse
 }
 It 'keeps secret-pattern redaction enabled for automatic logs' {
  Write-M365Log 'password=DummyExampleValue' -Level Warning -Quiet
  $text=Get-Content (Get-M365LogPath) -Raw
  $text | Should -Match 'REDACTED'
  $text | Should -Not -Match 'DummyExampleValue'
 }
 It 'uses custom explicit paths consistently for writer and log viewer' {
  $path=Join-Path $TestDrive 'custom-selected.log'
  Set-M365FileLogging -Path $path -NoInteractive
  Write-M365Log 'custom message' -Quiet
  Get-M365LogPath | Should -Be $path
  Get-M365LogPath -Folder | Should -Be $TestDrive
  Get-Content $path -Raw | Should -Match 'custom message'
 }
 It 'status shows the current default log path without a logging prompt' {
  Show-M365ConnectionStatus
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Log file:*no-tenant.log' }
  Should -Invoke Read-Host -Times 0
 }
 It 'a logging I/O failure does not fail the administrative caller or loop' {
  Mock Add-Content { throw 'Synthetic log write failure' }
  { Write-M365Log 'activity' -Quiet -WarningAction SilentlyContinue } | Should -Not -Throw
  $script:ToolkitDefaultFileLogging | Should -BeFalse
  $script:ToolkitFileLogPath | Should -BeNullOrEmpty
 }
}
