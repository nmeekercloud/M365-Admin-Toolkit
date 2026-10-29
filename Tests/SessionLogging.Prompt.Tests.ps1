BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Modules/M365Toolkit.Core/Public/Set-M365FileLogging.ps1')
 function Request-ToolkitSaveFile { param($Path,$Extension,[switch]$NoInteractive,[switch]$AllowExisting,$ExistingAction) throw 'Unmocked custom save request blocked' }
}
Describe 'Automatic activity-log selection (supersedes startup prompt)' {
 BeforeEach {
  $script:ToolkitFileLogPath=$null; $script:ToolkitDefaultFileLogging=$false
  Mock Write-Host {}
  Mock Read-Host { throw 'Unexpected startup logging prompt' }
  Mock Request-ToolkitSaveFile { [pscustomobject]@{Path='selected-session.log';ExistingApproved=$false} }
 }
 It 'enables the default log without prompting for approval or filename' {
  Set-M365FileLogging
  $script:ToolkitDefaultFileLogging | Should -BeTrue
  $script:ToolkitFileLogPath | Should -BeNullOrEmpty
  Should -Invoke Read-Host -Times 0
  Should -Invoke Request-ToolkitSaveFile -Times 0
 }
 It 'preserves explicit custom-file selection' {
  Set-M365FileLogging -Path 'selected-session.log' -NoInteractive
  $script:ToolkitDefaultFileLogging | Should -BeFalse
  $script:ToolkitFileLogPath | Should -Be 'selected-session.log'
  Should -Invoke Request-ToolkitSaveFile -Times 1 -Exactly -ParameterFilter { $Extension -eq 'log' -and $ExistingAction -eq 'Append' }
 }
 It 'also enables default logging for no-path noninteractive calls' {
  Set-M365FileLogging -NoInteractive
  $script:ToolkitDefaultFileLogging | Should -BeTrue
  Should -Invoke Read-Host -Times 0
 }
 It 'still allows file logging to be disabled without prompts' {
  $script:ToolkitDefaultFileLogging=$true
  Set-M365FileLogging -Disable
  $script:ToolkitDefaultFileLogging | Should -BeFalse
  $script:ToolkitFileLogPath | Should -BeNullOrEmpty
  Should -Invoke Read-Host -Times 0
 }
}
