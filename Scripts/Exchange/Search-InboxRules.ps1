#Requires -Version 7.4
<#
.SYNOPSIS
Read-only inbox-rule review with explicit per-mailbox coverage.
.DESCRIPTION
Search selected user/shared mailboxes or explicitly choose AllMailboxes. Includes
hidden rules in the request. Review signals are not proof of malicious activity.
Mailbox-level forwarding is reported separately from inbox rules. No rules change.
.EXAMPLE
.\Search-InboxRules.ps1 -MailboxIdentity user@contoso.com -IncludeDisabled -IncludeNonSuspicious
.NOTES
Services: ExchangeOnline. GraphScopes: none. Impact: read-only.
#>
[CmdletBinding()]
param([string[]]$MailboxIdentity,[switch]$AllMailboxes,[switch]$IncludeDisabled,
      [switch]$IncludeNonSuspicious,[string]$SearchText,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and -not $AllMailboxes -and -not $MailboxIdentity) { throw 'Specify MailboxIdentity or AllMailboxes with NoInteractive.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeReports.ps1')
Initialize-ERTask
if ($AllMailboxes -and $MailboxIdentity) { throw 'Use MailboxIdentity OR AllMailboxes.' }
if (-not $AllMailboxes -and -not $MailboxIdentity) {
    $inputText=([string](Read-Host 'Mailbox SMTP addresses, comma-separated, or ALL (blank cancels)')).Trim()
    if (-not $inputText) { return }
    if ($inputText -ceq 'ALL') { $AllMailboxes=$true } else { $MailboxIdentity=@($inputText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
$rows=[System.Collections.Generic.List[object]]::new()
$coverage=[System.Collections.Generic.List[object]]::new()
$mailboxes=[System.Collections.Generic.List[object]]::new()
if ($AllMailboxes) {
    foreach ($mailbox in @(Invoke-ERRead { Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited -ErrorAction Stop })) { $mailboxes.Add($mailbox) }
} else {
    foreach ($id in @($MailboxIdentity | Select-Object -Unique)) {
        try {
            $mailbox=Invoke-ERRead { Get-Mailbox -Identity $id -ErrorAction Stop }
            if ($mailbox.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox')) { throw 'Only user/shared mailboxes supported.' }
            $mailboxes.Add($mailbox)
        } catch { $coverage.Add([pscustomobject]@{Mailbox=$id;Status='Failed';RulesRead=0;RowsReturned=0;Error=$_.Exception.Message}) }
    }
}
Write-Host 'Read-only review. Hidden rules requested. Signals are not a malicious/benign verdict.'
foreach ($mailbox in @($mailboxes.ToArray() | Sort-Object PrimarySmtpAddress -Unique)) {
    $smtp=[string]$mailbox.PrimarySmtpAddress
    $startCount=$rows.Count
    # Forwarding settings are a separate mechanism, not an inbox-rule finding.
    if ($mailbox.ForwardingAddress -or $mailbox.ForwardingSmtpAddress) {
        $rows.Add([pscustomobject]@{Mailbox=$smtp;Scope='MailboxForwarding';RuleName='';RuleIdentity='';Enabled=$true;Priority='';HiddenReported='NotApplicable';Signals='MailboxForwardingConfigured';ForwardTo=[string]$mailbox.ForwardingAddress;ForwardAsAttachmentTo='';RedirectTo=[string]$mailbox.ForwardingSmtpAddress;DeleteMessage='';MarkAsRead='';MoveToFolder='';StopProcessingRules='';DeliverToMailboxAndForward=$mailbox.DeliverToMailboxAndForward;Description='Mailbox-level forwarding; not an inbox rule';MatchedTextFilter='NotApplied'})
    }
    try {
        $rules=@(Invoke-ERRead { Get-InboxRule -Mailbox $smtp -IncludeHidden -ErrorAction Stop })
        foreach ($rule in $rules) {
            if (-not $IncludeDisabled -and -not $rule.Enabled) { continue }
            $signals=@(Get-ERRuleSignals $rule)
            if (-not $IncludeNonSuspicious -and -not $signals.Count) { continue }
            $searchable=@($rule.Name,$rule.Description,@($rule.ForwardTo),@($rule.ForwardAsAttachmentTo),@($rule.RedirectTo),$rule.MoveToFolder) -join ' '
            if ($SearchText -and $searchable.IndexOf($SearchText,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $hidden=if ($rule.PSObject.Properties['IsHidden']) { [string]$rule.IsHidden } else { 'Unknown' }
            $rows.Add([pscustomobject]@{Mailbox=$smtp;Scope='InboxRule';RuleName=[string]$rule.Name;RuleIdentity=[string]$rule.Identity;Enabled=$rule.Enabled;Priority=$rule.Priority;HiddenReported=$hidden;Signals=($signals -join '; ');ForwardTo=(@($rule.ForwardTo) -join '; ');ForwardAsAttachmentTo=(@($rule.ForwardAsAttachmentTo) -join '; ');RedirectTo=(@($rule.RedirectTo) -join '; ');DeleteMessage=$rule.DeleteMessage;MarkAsRead=$rule.MarkAsRead;MoveToFolder=[string]$rule.MoveToFolder;StopProcessingRules=$rule.StopProcessingRules;DeliverToMailboxAndForward='';Description=[string]$rule.Description;MatchedTextFilter=$SearchText})
        }
        $coverage.Add([pscustomobject]@{Mailbox=$smtp;Status='Scanned';RulesRead=$rules.Count;RowsReturned=($rows.Count-$startCount);Error=''})
    } catch {
        $coverage.Add([pscustomobject]@{Mailbox=$smtp;Status='Failed';RulesRead=0;RowsReturned=($rows.Count-$startCount);Error=$_.Exception.Message})
        Write-M365Log -Message "Inbox-rule read failed for $smtp : $($_.Exception.Message)" -Level Warning
    }
}
$failed=@($coverage.ToArray() | Where-Object Status -eq 'Failed').Count
$metadata=[pscustomobject]@{Task='SearchInboxRules';Complete=($failed -eq 0);Scope='User/shared mailbox direct inbox rules plus configured mailbox forwarding';AllMailboxes=[bool]$AllMailboxes;IncludeHiddenRequested=$true;IncludeDisabled=[bool]$IncludeDisabled;IncludeNonSuspicious=[bool]$IncludeNonSuspicious;SearchText=$SearchText;ForwardingTextFilterApplied=$false;MailboxCoverage=@($coverage.ToArray());Limitations='Review signals only; no effective-access audit, no transport-rule coverage, no proof of compromise. Hidden state may be unreported.'}
$columns=@('Mailbox','Scope','RuleName','RuleIdentity','Enabled','Priority','HiddenReported','Signals','ForwardTo','ForwardAsAttachmentTo','RedirectTo','DeleteMessage','MarkAsRead','MoveToFolder','StopProcessingRules','DeliverToMailboxAndForward','Description','MatchedTextFilter')
Show-M365Results -InputObject @($rows.ToArray() | Select-Object Mailbox,Scope,RuleName,Enabled,Signals,ForwardTo,RedirectTo) -Title 'Inbox rule and mailbox forwarding review' -NoPaging:$NoInteractive
Show-M365Results -InputObject $coverage.ToArray() -Title 'Mailbox collection coverage' -NoPaging:$NoInteractive
$metadata | Format-List | Out-Host
Write-Host "Report rows: $($rows.Count); failed mailboxes: $failed. An empty filtered result is not a clean-bill-of-health verdict."
if ($failed) { Write-Warning 'Partial mailbox coverage. Inspect coverage before drawing conclusions; saved Run.json retains the details.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportBundle.ps1')
$manifest=[ordered]@{}
foreach ($property in $metadata.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
$manifest['Status']=if ($metadata.Complete) {'CompletedWithinDeclaredScope'} else {'PartialCoverage'}
$manifest['FinishedUtc']=[datetime]::UtcNow.ToString('o')
$export=Export-ToolkitReportBundle -Tables @{'InboxRules.csv'=$rows;'MailboxCoverage.csv'=$coverage} -Manifest $manifest -Columns @{'InboxRules.csv'=$columns;'MailboxCoverage.csv'=@('Mailbox','Status','RulesRead','RowsReturned','Error')} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
$paths=[pscustomobject]@{Csv=$null;Coverage=$null;MailboxCoverage=$null}
if ($export.Status -eq 'Saved') {
 $paths.Csv=Join-Path $export.ReportFolder 'InboxRules.csv'
 $paths.Coverage=Join-Path $export.ReportFolder 'Run.json'
 $paths.MailboxCoverage=Join-Path $export.ReportFolder 'MailboxCoverage.csv'
}
Write-Host ('Export status: '+$export.Status)
if ($PassThru) { [pscustomobject]@{Rows=@($rows.ToArray());Metadata=$metadata;Paths=$paths;MailboxCoverage=@($coverage.ToArray());ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
