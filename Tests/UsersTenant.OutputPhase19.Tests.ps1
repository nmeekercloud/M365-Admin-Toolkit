BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.UsersTenantOutput.ps1')
 function Show-M365Results {param($InputObject,$Title,[switch]$NoPaging)}
 function Complete-WFStep {param($Action,$Target,$Status,[switch]$PassThru,$Detail) if ($PassThru) {[pscustomobject]@{Action=$Action;Target=$Target;Status=$Status;Detail=$Detail}}}
 function Assert-M365TaskAccess {param($AccessMode,$TaskId)}
 function Assert-M365Connection {param($Service,$GraphScopes)}
 function Invoke-MgGraphRequest {[CmdletBinding()]param($Method,$Uri,$OutputType) throw 'Unmocked Graph blocked'}
 $userFiles=@('Block-UserAccess.ps1','Remove-UserLicenses.ps1','Copy-UserAccess.ps1','Invoke-BulkUserManagement.ps1','New-User.ps1','Disable-User.ps1')
}
Describe 'Phase 19 combined Users and Tenant output' {
 BeforeEach {
  Mock Show-M365Results {};Mock Write-Host {};Mock Read-Host {'n'}
  $UT19State=[pscustomobject]@{ResultsShown=$false};$WorkflowApproval=$null;$PlanOnly=$false
  $ExportDirectory=$null;$ReportName=$null;$NoOutputPrompt=$true
  $tables=@{'Results.csv'=@([pscustomobject]@{Target='user@contoso.com';Result='VerificationIncomplete';Error='=Fixture';TemporaryPassword='NEVER-EXPORT'})}
  $cols=@{'Results.csv'=@('Target','Result','Error')};$manifest=@{Task='offline';Status='OutcomeSummary'}
 }
 It 'displays before offering export and declining writes nothing' {
  Mock Read-Host {Should -Invoke Show-M365Results -Times 1 -Exactly;'n'}
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-UT19Output -Tables $tables -Columns $cols -Manifest $manifest).Status | Should -Be 'Declined'
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save with NoOutputPrompt by default' {
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-UT19Output -Tables $tables -Columns $cols -Manifest $manifest -NoOutputPrompt).Status | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only declared safe columns and preserves raw uncertainty' {
  $r=Invoke-UT19Output -Tables $tables -Columns $cols -Manifest $manifest -NoOutputPrompt -ExportDirectory $TestDrive -ReportName 'safe'
  $r.Status | Should -Be 'Saved'
  (Get-Content (Join-Path $r.ReportFolder 'Results.csv') -Raw) | Should -Not -Match 'NEVER-EXPORT|TemporaryPassword'
  (Import-Csv (Join-Path $r.ReportFolder 'Results.csv')).Error | Should -Be "'=Fixture"
  $tables['Results.csv'][0].Result | Should -Be 'VerificationIncomplete'
 }
 It 'blocks credential column names and nested credential metadata' {
  {Invoke-UT19Output -Tables $tables -Columns @{'Results.csv'=@('TemporaryPassword')} -Manifest $manifest} | Should -Throw '*credential*'
  {Invoke-UT19Output -Tables $tables -Columns $cols -Manifest @{Nested=@{AccessToken='secret'}}} | Should -Throw '*credential*'
 }
 It 'suppresses preview exports even with an explicit destination' {
  Mock New-Item {throw 'Unexpected directory creation'}
  (Invoke-UT19Output -Tables $tables -Columns $cols -Manifest $manifest -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview').Status | Should -Be 'PreviewOnly'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'retains empty CSV headers' {
  $r=Invoke-UT19Output -Tables @{'Domains.csv'=@()} -Columns @{'Domains.csv'=@('Domain','Verified')} -Manifest $manifest -NoOutputPrompt -ExportDirectory $TestDrive -ReportName 'empty'
  (Get-Content (Join-Path $r.ReportFolder 'Domains.csv') -First 1) | Should -Be '"Domain","Verified"'
 }
 It 'keeps results on export failure' {
  (Invoke-UT19Output -Tables $tables -Columns $cols -Manifest $manifest -NoOutputPrompt -ExportDirectory 'relative' -ReportName 'bad' -WarningAction SilentlyContinue).Status | Should -Be 'ExportFailed'
  $tables['Results.csv'][0].Result | Should -Be 'VerificationIncomplete'
 }
 It 'suppresses nested approved-workflow exports and preserves completion shape' {
  $WorkflowApproval=[pscustomobject]@{Token='offline'}
  Write-UT19Results -Results @([pscustomobject]@{Product='License';Result='Unverified';Detail='fixture'}) -Label LicenseRemoval
  $r=Complete-UT19Step -Action 'License removal' -Target 'user@contoso.com' -Status Unverified -PassThru
  $r.Status | Should -Be 'Unverified'
  Should -Invoke Read-Host -Times 0
 }
 It 'does not offer a second export after standalone license detail rows' {
  $NoOutputPrompt=$false
  Write-UT19Results -Results @([pscustomobject]@{Product='License';Result='Success'}) -Label LicenseRemoval
  $r=Complete-UT19Step -Action 'License removal' -Target 'user@contoso.com' -Status Success -PassThru
  $r.Status | Should -Be 'Success'
  Should -Invoke Read-Host -Times 1 -Exactly
 }
 It 'preserves PlanOnly outcome contracts without optional reports' {
  $PlanOnly=$true
  $r=Complete-UT19Step -Action 'License removal' -Target 'user@contoso.com' -Status Cancelled -PassThru
  $r.Status | Should -Be 'Cancelled'
  Should -Invoke Show-M365Results -Times 0
  Should -Invoke Read-Host -Times 0
 }
 It 'parses all user targets and exposes output-only controls without claiming unattended execution' {
  foreach ($file in $userFiles) {
   $tokens=$null;$errors=$null
   $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('Scripts/Users/'+$file)),[ref]$tokens,[ref]$errors)
   @($errors).Count | Should -Be 0
   $names=@($ast.ParamBlock.Parameters | ForEach-Object {$_.Name.VariablePath.UserPath})
   foreach ($name in @('ExportDirectory','ReportName','NoOutputPrompt')) {$names | Should -Contain $name}
   $names | Should -Not -Contain 'NoInteractive'
  }
 }
 It 'retains user mutation backups approval guards and original workflow helper definitions' {
  foreach ($file in $userFiles) {
   $text=Get-Content (Join-Path $root ('Scripts/Users/'+$file)) -Raw
   if ($file -ne 'Disable-User.ps1') {$text | Should -Match 'Save-UMJson';$text | Should -Match '\$PSCmdlet.ShouldProcess'}
  }
  (Get-Content (Join-Path $root 'Scripts/Users/UserManagement.Common.ps1') -Raw) | Should -Match 'function Write-UMResults'
 }
 It 'retains new-user password disclosure cleanup and checkpoint safeguards' {
  $text=Get-Content (Join-Path $root 'Scripts/Users/New-User.ps1') -Raw
  $text | Should -Match 'Show-ToolkitGeneratedPassword'
  $text | Should -Match 'ZeroFreeBSTR'
  $text | Should -Match 'NewUser-CreatedIdentity'
  $text | Should -Match 'No duplicate create or automatic adoption'
 }
 It 'keeps workflow-only deletion unchanged and offboarding child result validation intact' {
  $delete=Get-Content (Join-Path $root 'Scripts/Users/Remove-OffboardedUser.ps1') -Raw
  $delete | Should -Match 'Invoke-WF7BDeleteOnce'
  $delete | Should -Not -Match 'Complete-UT19Step|Write-UT19Results'
  $workflow=Get-Content (Join-Path $root 'Scripts/Users/Disable-User.ps1') -Raw
  $workflow | Should -Match 'Child task did not return exactly one structured outcome'
  $workflow | Should -Match 'Write-UT19Results -Results \$displayResults'
 }
 It 'runs Tenant Details offline through its actual entrypoint and retains verified-session fields' {
  Mock Get-Module {[pscustomobject]@{Name='M365Toolkit.Core'}} -ParameterFilter {$Name -eq 'M365Toolkit.Core'}
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection {[pscustomobject]@{TenantName='Offline';TenantId='tenant-id';InitialDomain='contoso.onmicrosoft.com';DefaultDomain='contoso.com';Account='admin@contoso.com';AccountType='Member';ConnectedServices=@('Graph');ConnectedAt='offline'}}
  $r=& (Join-Path $root 'Scripts/Tenant/Get-TenantDetails.ps1') -NoInteractive -PassThru
  $r.'Tenant ID' | Should -Be 'tenant-id'
  Should -Invoke Read-Host -Times 0
 }
 It 'runs Tenant Domains offline with optional export and preserves all columns' {
  Mock Get-Module {[pscustomobject]@{Name='M365Toolkit.Core'}} -ParameterFilter {$Name -eq 'M365Toolkit.Core'}
  Mock Assert-M365TaskAccess {}
  Mock Assert-M365Connection {[pscustomobject]@{TenantName='Offline';TenantId='tenant-id'}}
  Mock Invoke-MgGraphRequest {[pscustomobject]@{value=@([pscustomobject]@{id='contoso.com';isDefault=$true;isInitial=$false;isVerified=$true;authenticationType='Managed';supportedServices=@('Email','OfficeCommunicationsOnline')})}}
  $r=@(& (Join-Path $root 'Scripts/Tenant/Get-TenantDomains.ps1') -NoInteractive -ExportDirectory $TestDrive -ReportName 'domains' -PassThru)
  $r[0].Domain | Should -Be 'contoso.com'
  $r[0].SupportedServices | Should -Be 'Email; OfficeCommunicationsOnline'
  @((Get-ChildItem (Join-Path $TestDrive 'domains') -File).Name | Sort-Object) | Should -Be @('Domains.csv','Run.json')
 }
}
