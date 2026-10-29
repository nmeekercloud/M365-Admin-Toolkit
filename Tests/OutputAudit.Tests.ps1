BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Invoke-ToolkitOutputAudit.ps1')
}
Describe 'Output audit static and non-destructive behavior' {
 BeforeEach {
  $fixture=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Path (Join-Path $fixture 'Scripts/Reports') -Force
  $null=New-Item -ItemType Directory -Path (Join-Path $fixture 'Tools') -Force
 }
 It 'parses target scripts without executing them' {
  Set-Content -LiteralPath (Join-Path $fixture 'Scripts/Reports/Test.ps1') -Value "throw 'DO NOT EXECUTE'"
  $r=Get-ToolkitOutputAudit $fixture
  $r.Summary.ScannedSourceFiles | Should -Be 1
  $r.Summary.ParseErrors | Should -Be 0
 }
 It 'reports syntax errors without executing or modifying source' {
  $file=Join-Path $fixture 'Scripts/Reports/Test.ps1';Set-Content $file 'if ('
  $before=(Get-FileHash $file).Hash
  $r=Get-ToolkitOutputAudit $fixture
  $r.Summary.ParseErrors | Should -BeGreaterThan 0
  (Get-FileHash $file).Hash | Should -Be $before
 }
 It 'distinguishes backup snapshots from direct report path allocation' {
  Set-Content -LiteralPath (Join-Path $fixture 'Scripts/Reports/Test.ps1') -Value @'
Save-UMJson -Value $value -Label 'Before'
Get-M365OutputPath -Type Backups
Get-M365OutputPath -Type Reports
'@
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Persistence | Where-Object Category -eq 'SnapshotOrJournal').Count | Should -Be 1
  @($r.Persistence | Where-Object Category -eq 'SnapshotPath').Count | Should -Be 1
  @($r.Review | Where-Object Category -eq 'DirectReportPath').Count | Should -Be 1
 }
 It 'identifies legacy helper definitions without claiming live reachability' {
  Set-Content -LiteralPath (Join-Path $fixture 'Tools/Legacy.ps1') -Value 'function Export-ERReport { Export-Csv -LiteralPath $path }'
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Persistence | Where-Object Category -eq 'LegacyHelperDefinition').Count | Should -Be 1
 }
 It 'exempts missing Planned scripts but flags missing Ready scripts' {
  Set-Content -LiteralPath (Join-Path $fixture 'Scripts/Reports/Planned.task.psd1') -Value "@{Status='Planned';Script='Missing.ps1'}"
  Set-Content -LiteralPath (Join-Path $fixture 'Scripts/Reports/Ready.task.psd1') -Value "@{Status='Ready';Script='Missing.ps1'}"
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Review | Where-Object Category -eq 'TaskDefinition').Count | Should -Be 1
 }
 It 'inventories backup artifacts without removing them' {
  $file=Join-Path $fixture 'Tools/Example.ps1.backup-old';Set-Content $file 'original'
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Review | Where-Object Category -eq 'RepositoryBackupArtifact').Count | Should -Be 1
  (Get-Content $file) | Should -Be 'original'
 }
 It 'flags legacy test expectations separately without running them' {
  $null=New-Item -ItemType Directory -Path (Join-Path $fixture 'Tests')
  Set-Content -LiteralPath (Join-Path $fixture 'Tests/Legacy.Tests.ps1') -Value "throw 'Export-ERReport'"
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Review | Where-Object Category -eq 'LegacyTestExpectationReview').Count | Should -Be 1
 }
 It 'records direct .NET write methods as candidates' {
  Set-Content -LiteralPath (Join-Path $fixture 'Scripts/Reports/Test.ps1') -Value '[IO.File]::WriteAllText($path,$text)'
  $r=Get-ToolkitOutputAudit $fixture
  @($r.Review | Where-Object Category -eq 'DotNetWriteReview').Count | Should -Be 1
 }
 It 'never labels static findings as globally completed output standardization' {
  $r=Get-ToolkitOutputAudit $fixture
  $r.Summary.Status | Should -Be 'ReviewRequired'
  $r.Summary.Limitations | Should -Match 'not data-flow/reachability'
 }
 It 'keeps a finite roster including original Phase 1 and the Phase 10 correction' {
  $roster=Import-PowerShellDataFile -LiteralPath (Join-Path $root 'Tools/OutputRegression.Roster.psd1')
  $roster.Suites.Name | Should -Contain 'OutputStandardization.Phase1.Tests.ps1'
  $roster.Suites.Name | Should -Contain 'Groups.OutputPhase10.Validation.Tests.ps1'
  ($roster.Suites | Measure-Object Expected -Sum).Sum | Should -Be 256
 }
}
