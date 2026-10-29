BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Exchange/Search-InboxRules.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Write-M365Log { param($Message,$Level,[switch]$Quiet) }
 function Assert-M365Connection { param($Service) }
 function Get-Mailbox { [CmdletBinding()]param($Identity,$RecipientTypeDetails,$ResultSize) throw 'Unmocked mailbox read blocked' }
 function Get-InboxRule { [CmdletBinding()]param($Mailbox,[switch]$IncludeHidden) throw 'Unmocked rule read blocked' }
 function New-Phase15Mailbox { [pscustomobject]@{PrimarySmtpAddress='user@contoso.com';RecipientTypeDetails='UserMailbox';ForwardingAddress=$null;ForwardingSmtpAddress=$null;DeliverToMailboxAndForward=$false} }
 function New-Phase15Rule {
  [pscustomobject]@{Name='=Review [abc]';Identity='rule-1';Enabled=$true;Priority=1;IsHidden=$true;ForwardTo=@('external@example.com');ForwardAsAttachmentTo=@();RedirectTo=@();DeleteMessage=$false;MarkAsRead=$false;MoveToFolder='';StopProcessingRules=$false;Description='Offline fixture'}
 }
}
Describe 'Phase 15 inbox rule review optional output' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365Connection {}
  Mock Get-Mailbox { New-Phase15Mailbox }
  Mock Get-InboxRule { New-Phase15Rule }
  Mock Show-M365Results {}
  Mock Write-M365Log {}
  Mock Write-Host {}
  Mock Write-Warning {}
  Mock Start-Sleep {}
  Mock Read-Host { 'n' }
 }
 It 'displays findings and coverage before offering export and declining writes nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 2 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -MailboxIdentity 'user@contoso.com' -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  $r.Paths.Csv | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save in noninteractive mode by default' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -MailboxIdentity 'user@contoso.com' -NoInteractive -PassThru
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 2 -ParameterFilter { $NoPaging }
 }
 It 'exports three declared files safely while retaining raw rule values' {
  $r=& $entry -MailboxIdentity 'user@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'rules' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('InboxRules.csv','MailboxCoverage.csv','Run.json')
  (Import-Csv $r.Paths.Csv).RuleName | Should -Be "'=Review [abc]"
  $r.Rows[0].RuleName | Should -Be '=Review [abc]'
  $r.Paths.Coverage | Should -Be (Join-Path $r.ReportFolder 'Run.json')
  Should -Invoke Get-InboxRule -Times 1 -ParameterFilter { $IncludeHidden }
 }
 It 'supports AllMailboxes with omitted identities without false conflict' {
  $r=& $entry -AllMailboxes -NoInteractive -PassThru
  $r.Rows.Count | Should -Be 1
  $r.Metadata.AllMailboxes | Should -BeTrue
  Should -Invoke Get-Mailbox -Times 1 -ParameterFilter { $ResultSize -eq 'Unlimited' }
 }
 It 'requires explicit mailbox scope in noninteractive mode before authentication' {
  { & $entry -NoInteractive } | Should -Throw '*Specify MailboxIdentity or AllMailboxes*'
  Should -Invoke Assert-M365Connection -Times 0
  Should -Invoke Read-Host -Times 0
 }
 It 'preserves failed rule-read coverage separately from successfully saved output' {
  Mock Get-InboxRule { throw 'Synthetic rule read denial' }
  $r=& $entry -MailboxIdentity 'user@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'partial' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.Complete | Should -BeFalse
  $r.Manifest.Status | Should -Be 'PartialCoverage'
  $r.MailboxCoverage[0].Status | Should -Be 'Failed'
  (Get-Content $r.Paths.Coverage -Raw | ConvertFrom-Json).Complete | Should -BeFalse
 }
 It 'retains failed mailbox-resolution coverage without pretending it was scanned' {
  Mock Get-Mailbox { throw 'Synthetic mailbox lookup denial' }
  $r=& $entry -MailboxIdentity 'missing@contoso.com' -NoInteractive -PassThru
  $r.Metadata.Complete | Should -BeFalse
  $r.MailboxCoverage[0].Mailbox | Should -Be 'missing@contoso.com'
  $r.MailboxCoverage[0].Status | Should -Be 'Failed'
  Should -Invoke Get-InboxRule -Times 0
 }
 It 'keeps mailbox forwarding separate and unaffected by the rule text filter' {
  Mock Get-Mailbox { $m=New-Phase15Mailbox;$m.ForwardingSmtpAddress='smtp:external@example.com';$m }
  $r=& $entry -MailboxIdentity 'user@contoso.com' -SearchText 'no-match' -NoInteractive -PassThru
  $r.Rows.Count | Should -Be 1
  $r.Rows[0].Scope | Should -Be 'MailboxForwarding'
  $r.Metadata.ForwardingTextFilterApplied | Should -BeFalse
 }
 It 'retains disabled and nonsuspicious rule filtering flags' {
  Mock Get-InboxRule { $rule=New-Phase15Rule;$rule.Enabled=$false;$rule.ForwardTo=@();$rule }
  $default=& $entry -MailboxIdentity 'user@contoso.com' -NoInteractive -PassThru
  $default.Rows.Count | Should -Be 0
  $inclusive=& $entry -MailboxIdentity 'user@contoso.com' -IncludeDisabled -IncludeNonSuspicious -NoInteractive -PassThru
  $inclusive.Rows.Count | Should -Be 1
 }
 It 'preserves literal search and explicit headers for empty filtered findings' {
  $matched=& $entry -MailboxIdentity 'user@contoso.com' -SearchText '[abc]' -NoInteractive -PassThru
  $matched.Rows.Count | Should -Be 1
  $empty=& $entry -MailboxIdentity 'user@contoso.com' -SearchText 'no-match' -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru
  $empty.Rows.Count | Should -Be 0
  $empty.Metadata.Complete | Should -BeTrue
  (Get-Content $empty.Paths.Csv -First 1) | Should -Be '"Mailbox","Scope","RuleName","RuleIdentity","Enabled","Priority","HiddenReported","Signals","ForwardTo","ForwardAsAttachmentTo","RedirectTo","DeleteMessage","MarkAsRead","MoveToFolder","StopProcessingRules","DeliverToMailboxAndForward","Description","MatchedTextFilter"'
 }
 It 'keeps retrieval completeness and findings on export failure' {
  $r=& $entry -MailboxIdentity 'user@contoso.com' -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Metadata.Complete | Should -BeTrue
  $r.Rows.Count | Should -Be 1
  $r.Paths.Csv | Should -BeNullOrEmpty
 }
 It 'blocks conflicting scopes and removes the legacy automatic exporter' {
  { & $entry -MailboxIdentity 'user@contoso.com' -AllMailboxes -NoInteractive } | Should -Throw '*MailboxIdentity OR AllMailboxes*'
  Should -Invoke Get-Mailbox -Times 0
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Export-ERReport|Get-M365OutputPath|Export-Csv'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
