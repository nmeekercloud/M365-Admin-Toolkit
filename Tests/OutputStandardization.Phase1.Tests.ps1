BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $core=Join-Path $root 'Modules/M365Toolkit.Core'
 $script:ToolkitRoot=$root; $script:M365Session=$null
 . (Join-Path $core 'Private/ExternalPath.ps1')
 . (Join-Path $core 'Private/OutputControl.ps1')
 . (Join-Path $core 'Private/LogHelpers.ps1')
 . (Join-Path $core 'Public/Show-M365Results.ps1')
 . (Join-Path $core 'Public/Export-M365Csv.ps1')
 . (Join-Path $core 'Public/Set-M365FileLogging.ps1')
 . (Join-Path $core 'Public/Write-M365Log.ps1')
 . (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1')
 function Get-ToolkitSetting { param($Path,$Default) return $Default }
 function Get-ToolkitSessionLabel { 'no-tenant' }
 function Get-M365LogPath { throw 'Legacy log-path creation must not be called' }
 function Get-ToolkitDataRoot { throw 'Legacy automatic data-root creation must not be called' }
}
Describe 'Output standardization phase 1' {
 BeforeEach {
  $script:ToolkitFileLogPath=$null
  $script:ToolkitDefaultFileLogging=$false
  $script:rows=@([pscustomobject]@{User='example@contoso.com';Result='Success'})
  $script:answers=[Collections.Generic.Queue[string]]::new()
  Mock Read-Host {
   if ($script:answers.Count -eq 0) { throw 'Unexpected prompt' }
   $script:answers.Dequeue()
  }
  Mock Write-Host {}
  Mock New-Item { throw 'Unexpected directory creation' } -ParameterFilter { $Path -like '*forbidden-phase1*' }
 }
 It 'declining export creates no files or directories' {
  $script:answers.Enqueue('n')
  $r=Export-M365Csv -InputObject $script:rows -PassThru
  $r.Status | Should -Be 'Declined'
  Should -Invoke Read-Host -Times 1 -Exactly
 }
 It 'Enter defaults to no export' {
  $script:answers.Enqueue('')
  (Export-M365Csv -InputObject $script:rows -PassThru).Status | Should -Be 'Declined'
 }
 It 'blank full-path prompt cancels saving without creating a folder' {
  $script:answers.Enqueue('y'); $script:answers.Enqueue('')
  $r=Export-M365Csv -InputObject $script:rows -PassThru
  $r.Status | Should -Be 'Cancelled'
 }
 It 'uses the exact selected filename and location' {
  $path=Join-Path $TestDrive 'chosen-name.csv'
  $r=Export-M365Csv -InputObject $script:rows -Path $path -NoInteractive -PassThru
  $r.Status | Should -Be 'Saved'
  $r.Path | Should -Be $path
  @(Import-Csv $path).Count | Should -Be 1
  Should -Invoke Read-Host -Times 0
 }
 It 'does not create a missing parent in noninteractive mode' {
  $dir=Join-Path $TestDrive 'not-created-auto'
  $r=Export-M365Csv -InputObject $script:rows -Path (Join-Path $dir 'report.csv') -NoInteractive -PassThru -WarningAction SilentlyContinue
  $r.Status | Should -Be 'ExportFailed'
  Test-Path $dir | Should -BeFalse
 }
 It 'declining folder creation creates no folder' {
  $dir=Join-Path $TestDrive 'not-created-interactive'
  $script:answers.Enqueue('n')
  (Export-M365Csv -InputObject $script:rows -Path (Join-Path $dir 'report.csv') -PassThru).Status | Should -Be 'Cancelled'
  Test-Path $dir | Should -BeFalse
 }
 It 'creates an approved folder only after receiving the complete destination' {
  $dir=Join-Path $TestDrive 'approved-directory'
  $script:answers.Enqueue('y')
  $r=Export-M365Csv -InputObject $script:rows -Path (Join-Path $dir 'report.csv') -PassThru
  $r.Status | Should -Be 'Saved'
  Test-Path $r.Path | Should -BeTrue
 }
 It 'preserves an existing file when overwrite is declined' {
  $path=Join-Path $TestDrive 'preserve.csv'; Set-Content $path 'original'
  $script:answers.Enqueue('n')
  (Export-M365Csv -InputObject $script:rows -Path $path -PassThru).Status | Should -Be 'Cancelled'
  (Get-Content $path -Raw).Trim() | Should -Be 'original'
 }
 It 'requires explicit overwrite in noninteractive mode' {
  $path=Join-Path $TestDrive 'preserve-auto.csv'; Set-Content $path 'original'
  (Export-M365Csv -InputObject $script:rows -Path $path -NoInteractive -PassThru -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  (Get-Content $path -Raw).Trim() | Should -Be 'original'
 }
 It 'accepts explicitly approved overwrite' {
  $path=Join-Path $TestDrive 'replace.csv'; Set-Content $path 'original'
  (Export-M365Csv -InputObject $script:rows -Path $path -NoInteractive -Overwrite -PassThru).Status | Should -Be 'Saved'
  (Import-Csv $path).Result | Should -Be 'Success'
 }
 It 'rejects output inside the repository' {
  $path=Join-Path $root 'forbidden-phase1.csv'
  (Export-M365Csv -InputObject $script:rows -Path $path -NoInteractive -PassThru -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  Test-Path $path | Should -BeFalse
 }
 It 'requires the CSV extension instead of inventing a filename' {
  $path=Join-Path $TestDrive 'extension-missing'
  (Export-M365Csv -InputObject $script:rows -Path $path -NoInteractive -PassThru -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  Test-Path $path | Should -BeFalse
 }
 It 'does not prompt in noninteractive mode without an export path' {
  (Export-M365Csv -InputObject $script:rows -NoInteractive -PassThru).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
 }
 It 'keeps all data after stopping console pagination' {
  $many=@(1..103 | ForEach-Object { [pscustomobject]@{Number=$_;Result='Success'} })
  $script:answers.Enqueue('q')
  Show-M365Results -InputObject $many -PageSize 50
  $path=Join-Path $TestDrive 'all-103.csv'
  Export-M365Csv -InputObject $many -Path $path -NoInteractive
  @(Import-Csv $path).Count | Should -Be 103
  Should -Invoke Read-Host -Times 1 -Exactly
 }
 It 'emits no result objects from display by default' {
  @(Show-M365Results -InputObject $script:rows).Count | Should -Be 0
 }
 It 'writes no persistent log for any level when explicitly disabled' {
  foreach ($level in @('Debug','Info','Success','Change','Warning','Error')) { Write-M365Log -Message 'message' -Level $level -Quiet }
  $script:ToolkitFileLogPath | Should -BeNullOrEmpty
 }
 It 'automatic default logging does not request approval or a path' {
  Set-M365FileLogging
  $script:ToolkitDefaultFileLogging | Should -BeTrue
  $script:ToolkitFileLogPath | Should -BeNullOrEmpty
  Should -Invoke Read-Host -Times 0
 }
 It 'writes redacted content only after explicit log selection' {
  $path=Join-Path $TestDrive 'approved.log'
  Set-M365FileLogging -Path $path -NoInteractive
  Write-M365Log -Message 'client_secret=DummySensitiveValue' -Level Change -Quiet
  $text=Get-Content $path -Raw
  $text | Should -Match 'REDACTED'
  $text | Should -Not -Match 'DummySensitiveValue'
 }
 It 'disabling persistent logging stops subsequent file writes' {
  $path=Join-Path $TestDrive 'disable.log'
  Set-M365FileLogging -Path $path -NoInteractive
  Write-M365Log 'first' -Quiet
  Set-M365FileLogging -Disable
  Write-M365Log 'second' -Quiet
  Get-Content $path -Raw | Should -Not -Match 'second'
 }
 It 'does not silently append an existing log' {
  $path=Join-Path $TestDrive 'existing.log'; Set-Content $path 'original'
  Set-M365FileLogging -Path $path -NoInteractive -WarningAction SilentlyContinue
  Write-M365Log 'not-approved' -Quiet
  (Get-Content $path -Raw).Trim() | Should -Be 'original'
 }
 It 'does not run legacy automatic retention deletion' {
  { Remove-ToolkitExpiredLog } | Should -Not -Throw
 }
 It 'shows user-workflow results before offering export' {
  $script:events=[Collections.Generic.List[string]]::new()
  Mock Show-M365Results { $script:events.Add('display') }
  Mock Export-M365Csv { $script:events.Add('export'); [pscustomobject]@{Status='Declined';Path=$null} }
  Mock Write-M365Log {}
  Write-UMResults -Results $script:rows -Label 'Workflow'
  ($script:events -join ',') | Should -Be 'display,export'
 }
 It 'an export failure does not change successful workflow results' {
  Mock Show-M365Results {}
  Mock Export-M365Csv { [pscustomobject]@{Status='ExportFailed';Path=$null} }
  Mock Write-M365Log {}
  { Write-UMResults -Results $script:rows -Label 'Workflow' } | Should -Not -Throw
  $script:rows[0].Result | Should -Be 'Success'
 }
 It 'does not create companion files for a CSV export' {
  $dir=Join-Path $TestDrive 'single-csv'; $null=New-Item -ItemType Directory $dir
  Export-M365Csv -InputObject $script:rows -Path (Join-Path $dir 'report.csv') -NoInteractive
  @(Get-ChildItem $dir -File).Count | Should -Be 1
 }
}
