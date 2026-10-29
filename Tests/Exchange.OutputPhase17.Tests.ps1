BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.ExchangeOutput.ps1')
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Complete-WFStep { param($Action,$Target,$Status,[switch]$PassThru,$Detail) if ($PassThru) { [pscustomobject]@{Action=$Action;Target=$Target;Status=$Status;Detail=$Detail} } }
 $files=@('Set-MailboxAutoReply.ps1','Set-MailboxForwarding.ps1','Set-MailboxDelegates.ps1','ConvertTo-SharedMailbox.ps1','Copy-MailboxPermissions.ps1','Invoke-SharedMailboxManagement.ps1')
}
Describe 'Phase 17 combined Exchange output' {
 BeforeEach {
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Read-Host { 'n' }
  $rows=@([pscustomobject]@{Mailbox='mailbox@contoso.com';Delegate='delegate@contoso.com';Right='FullAccess';Result='AppliedUnverified';Error='=Fixture'})
  $cols=@('Mailbox','Delegate','Right','Result','Error')
  $ExportDirectory=$null;$ReportName=$null;$NoInteractive=$false;$WorkflowApproval=$null;$PlanOnly=$false
 }
 It 'displays before offering export and declining creates nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=@(Show-EX17Output -Rows $rows -Columns $cols -PassThru)
  $r[0].Result | Should -Be 'AppliedUnverified'
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  Show-EX17Output -Rows $rows -Columns $cols -NoInteractive
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'exports only Results.csv and Run.json with safe CSV without altering uncertainty' {
  $r=@(Show-EX17Output -Rows $rows -Columns $cols -NoInteractive -ExportDirectory $TestDrive -ReportName 'results' -PassThru)
  $folder=Join-Path $TestDrive 'results'
  @((Get-ChildItem $folder -File).Name | Sort-Object) | Should -Be @('Results.csv','Run.json')
  (Import-Csv (Join-Path $folder 'Results.csv')).Error | Should -Be "'=Fixture"
  $r[0].Error | Should -Be '=Fixture'
  $r[0].Result | Should -Be 'AppliedUnverified'
 }
 It 'does not export preview or cancelled output even with a destination' {
  Mock New-Item { throw 'Unexpected directory creation' }
  Show-EX17Output -Rows $rows -Columns $cols -PreviewOnly -ExportDirectory $TestDrive -ReportName 'preview'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'retains empty list headers and explicit view context' {
  Show-EX17Output -Rows @() -Columns @('Delegate','Right','Denied') -Label 'View' -Metadata @{Mailbox='mailbox@contoso.com'} -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty'
  (Get-Content (Join-Path $TestDrive 'empty/Results.csv') -First 1) | Should -Be '"Delegate","Right","Denied"'
  (Get-Content (Join-Path $TestDrive 'empty/Run.json') -Raw | ConvertFrom-Json).Mailbox | Should -Be 'mailbox@contoso.com'
 }
 It 'keeps returned results when export fails' {
  $r=@(Show-EX17Output -Rows $rows -Columns $cols -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru -WarningAction SilentlyContinue)
  $r[0].Result | Should -Be 'AppliedUnverified'
 }
 It 'preserves approved-workflow completion objects without export prompts' {
  $WorkflowApproval=[pscustomobject]@{Token='offline-test'}
  Mock New-Item { throw 'Unexpected workflow export' }
  $r=Complete-EX17Step -Action Forwarding -Target 'user@contoso.com' -Status Success -PassThru
  $r.Action | Should -Be 'Forwarding'
  $r.Status | Should -Be 'Success'
  Should -Invoke Read-Host -Times 0
  Should -Invoke Show-M365Results -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'preserves PlanOnly completion behavior without optional output' {
  $PlanOnly=$true
  $r=Complete-EX17Step -Action Delegation -Target 'user@contoso.com' -Status Cancelled -PassThru
  $r.Status | Should -Be 'Cancelled'
  Should -Invoke Read-Host -Times 0
  Should -Invoke Show-M365Results -Times 0
 }
 It 'keeps standalone completion shape and avoids exporting cancellation' {
  Mock New-Item { throw 'Unexpected cancellation export' }
  $r=Complete-EX17Step -Action Forwarding -Target 'user@contoso.com' -Status Cancelled -PassThru
  @($r.PSObject.Properties.Name) | Should -Be @('Action','Target','Status','Detail')
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
 }
 It 'retains E12 result row contracts with no output prompt in noninteractive mode' {
  $NoInteractive=$true
  $r=@(Write-EX17Results -Results $rows -Label CopyMailboxPermissions -PassThru)
  $r[0].Result | Should -Be 'AppliedUnverified'
  Should -Invoke Read-Host -Times 0
 }
 It 'parses all six changed entrypoints and exposes consistent output arguments' {
  foreach ($file in $files) {
   $tokens=$null;$errors=$null
   $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('Scripts/Exchange/'+$file)),[ref]$tokens,[ref]$errors)
   @($errors).Count | Should -Be 0
   $names=@($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
   foreach ($name in @('ExportDirectory','ReportName','NoInteractive','PassThru')) { $names | Should -Contain $name }
  }
 }
 It 'retains original backup and approval guards in all six entrypoints' {
  foreach ($file in $files) {
   $text=Get-Content (Join-Path $root ('Scripts/Exchange/'+$file)) -Raw
   $text | Should -Match 'Confirm-M365Action'
   $text | Should -Match '\$PSCmdlet.ShouldProcess'
   $text | Should -Match 'Save-(UMJson|E12Backup)'
   $text | Should -Not -Match 'Write-E12Results|Complete-WFStep'
  }
 }
 It 'rejects incomplete unattended inputs before any service initialization' {
  foreach ($file in $files) {
   { & (Join-Path $root ('Scripts/Exchange/'+$file)) -NoInteractive } | Should -Throw '*NoInteractive requires*'
  }
 }
 It 'leaves shared workflow and mutation helpers free of new output code' {
  foreach ($file in @('Toolkit.UserWorkflows.ps1','Toolkit.Exchange12.ps1')) {
   (Get-Content (Join-Path $root ('Tools/'+$file)) -Raw) | Should -Not -Match 'Complete-EX17Step|Write-EX17Results|Show-EX17Output'
  }
 }
}
