BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.OneDriveOutput.ps1')
 . (Join-Path $root 'Tools/Toolkit.OneDriveSharingStorage.Helpers.ps1')
 function Show-M365Results {param($InputObject,$Title,[switch]$NoPaging)}
 function Complete-WFStep {param($Action,$Target,$Status,[switch]$PassThru,$Detail) if ($PassThru) {[pscustomobject]@{Action=$Action;Target=$Target;Status=$Status;Detail=$Detail}}}
 $files=@('Get-OneDriveStorage.ps1','Get-OneDrivePermissions.ps1','Set-OneDrivePermissions.ps1','New-OneDriveSharingLink.ps1','Backup-OneDrive.ps1')
}
Describe 'Phase 18 combined OneDrive output' {
 BeforeEach {
  Mock Show-M365Results {};Mock Write-Host {};Mock Read-Host {'n'}
  $tables=@{'Outcome.csv'=@([pscustomobject]@{Status='Unverified';Detail='=Fixture';SharingUrl='https://secret.invalid/bearer'})}
  $columns=@{'Outcome.csv'=@('Status','Detail')}
  $manifest=@{Task='offline';Status='OutcomeSummary'}
  $WorkflowApproval=$null;$PlanOnly=$false;$NoInteractive=$true;$ExportDirectory=$null;$ReportName=$null
 }
 It 'displays before offering export and declining creates nothing' {
  Mock Read-Host {Should -Invoke Show-M365Results -Times 1 -Exactly;'n'}
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest).Status | Should -Be 'Declined'
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save in noninteractive mode by default' {
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest -NoInteractive).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only declared safe columns without bearer URLs or raw mutation alteration' {
  $r=Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest -NoInteractive -ExportDirectory $TestDrive -ReportName 'safe'
  $r.Status | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('Outcome.csv','Run.json')
  $csv=Get-Content (Join-Path $r.ReportFolder 'Outcome.csv') -Raw
  $csv | Should -Not -Match 'secret.invalid|SharingUrl'
  (Import-Csv (Join-Path $r.ReportFolder 'Outcome.csv')).Detail | Should -Be "'=Fixture"
  $tables['Outcome.csv'][0].Status | Should -Be 'Unverified'
  $tables['Outcome.csv'][0].Detail | Should -Be '=Fixture'
 }
 It 'blocks explicit secret columns and manifest keys before output' {
  {Invoke-OD18Output -Tables $tables -Columns @{'Outcome.csv'=@('SharingUrl')} -Manifest $manifest} | Should -Throw '*Sensitive*'
  {Invoke-OD18Output -Tables $tables -Columns $columns -Manifest @{Nested=@{Token='secret'}}} | Should -Throw '*Sensitive*'
  Should -Invoke Show-M365Results -Times 0
 }
 It 'suppresses preview export with an explicit destination' {
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'keeps partial scan status when the export succeeds' {
  $manifest.Status='PartialCoverage';$manifest.Gaps=@(@{Stage='RootWeb';Error='offline denial'})
  $r=Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest -NoInteractive -ExportDirectory $TestDrive -ReportName 'partial'
  $r.Status | Should -Be 'Saved'
  (Get-Content (Join-Path $r.ReportFolder 'Run.json') -Raw | ConvertFrom-Json).Status | Should -Be 'PartialCoverage'
 }
 It 'preserves headers for empty coverage tables' {
  $r=Invoke-OD18Output -Tables @{'Gaps.csv'=@()} -Columns @{'Gaps.csv'=@('Stage','Object','Error')} -Manifest $manifest -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty'
  $r.Status | Should -Be 'Saved'
  (Get-Content (Join-Path $r.ReportFolder 'Gaps.csv') -First 1) | Should -Be '"Stage","Object","Error"'
 }
 It 'does not change raw results or scan metadata on export failure' {
  (Invoke-OD18Output -Tables $tables -Columns $columns -Manifest $manifest -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $tables['Outcome.csv'][0].Status | Should -Be 'Unverified'
  $manifest.Status | Should -Be 'OutcomeSummary'
 }
 It 'preserves storage arithmetic and missing metric semantics' {
  $owner=@{id='offline';userPrincipalName='owner@contoso.com'}
  $row=New-OD34StorageRow -Owner $owner -PersonalSite @{Url='https://contoso-my.sharepoint.com/personal/owner';Details=@{StorageUsageCurrent=1024;StorageQuota=2048}}
  $row.UsedGiB | Should -Be 1
  $row.UtilizationPercent | Should -Be 50
  $missing=New-OD34StorageRow -Owner $owner -PersonalSite @{Url='offline';Details=@{StorageUsageCurrent=$null;StorageQuota=2048}}
  $missing.UsedGiB | Should -BeNullOrEmpty
  $missing.Status | Should -Be 'PartialMetricCoverage'
 }
 It 'keeps approved archive completion objects without nested export prompts' {
  $WorkflowApproval=[pscustomobject]@{Token='offline'}
  $r=Complete-OD18ArchiveStep -Action 'Move OneDrive archive' -Target 'owner@contoso.com' -Status Partial -Detail 'fixture' -PassThru
  $r.Status | Should -Be 'Partial'
  Should -Invoke Show-M365Results -Times 0
  Should -Invoke Read-Host -Times 0
 }
 It 'keeps planned archive completion without export writes' {
  Mock New-Item {throw 'Unexpected preview export'}
  $r=Complete-OD18ArchiveStep -Action 'Move OneDrive archive' -Target 'owner@contoso.com' -Status Planned -PassThru
  $r.Status | Should -Be 'Planned'
  Should -Invoke New-Item -Times 0
 }
 It 'parses all five entrypoints and exposes output parameters' {
  foreach ($file in $files) {
   $tokens=$null;$errors=$null
   $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('Scripts/OneDrive/'+$file)),[ref]$tokens,[ref]$errors)
   @($errors).Count | Should -Be 0
   $names=@($ast.ParamBlock.Parameters | ForEach-Object {$_.Name.VariablePath.UserPath})
   foreach ($n in @('ExportDirectory','ReportName','NoInteractive','PassThru')) {$names | Should -Contain $n}
  }
 }
 It 'preserves archive journals move engine and cleanup safeguards' {
  $text=Get-Content (Join-Path $root 'Scripts/OneDrive/Backup-OneDrive.ps1') -Raw
  $text | Should -Match 'Save-UMJson -Value \$report -Label ''OneDriveArchive-Result'''
  $text | Should -Match 'OD-Move-SingleSourceItem'
  $text | Should -Match 'OD-Move-FolderWithMerge'
  $text | Should -Match 'if \(\$script:ODJobUncertain\)'
  $text | Should -Match 'Remove-PnPSiteCollectionAdmin'
  $text | Should -Match 'Complete-OD18ArchiveStep'
 }
 It 'preserves required backups before administrator and sharing mutations' {
  $admin=Get-Content (Join-Path $root 'Scripts/OneDrive/Set-OneDrivePermissions.ps1') -Raw
  $admin.IndexOf('Get-M365OutputPath -Type Backups') | Should -BeLessThan $admin.IndexOf('Add-PnPSiteCollectionAdmin')
  $link=Get-Content (Join-Path $root 'Scripts/OneDrive/New-OneDriveSharingLink.ps1') -Raw
  $link.IndexOf('Get-M365OutputPath -Type Backups') | Should -BeLessThan $link.IndexOf('Invoke-MgGraphRequest -Method POST')
  $link | Should -Match 'if \(\$linkUrl -and \$ShowLink\)'
  $link | Should -Not -Match 'Get-M365OutputPath -Type Reports'
 }
 It 'requires complete noninteractive archive settings before service imports' {
  {& (Join-Path $root 'Scripts/OneDrive/Backup-OneDrive.ps1') -NoInteractive} | Should -Throw '*complete existing plan*'
 }
 It 'rejects unattended legacy ExportCsv without an explicit destination' {
  foreach ($file in @('Get-OneDrivePermissions.ps1','Get-OneDriveStorage.ps1')) {
   {& (Join-Path $root ('Scripts/OneDrive/'+$file)) -UserPrincipalName 'owner@contoso.com' -NoInteractive -ExportCsv} | Should -Throw '*requires ExportDirectory and ReportName*'
  }
 }
}
