#Requires -Version 7.4
<# .SYNOPSIS
View, set or remove mailbox-level forwarding. Does not change inbox rules or tenant policies.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[ValidateSet('View','Set','Remove')][string]$Operation,
      [string]$ForwardTo,[bool]$KeepCopy=$true,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[switch]$PlanOnly,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and (-not $UserPrincipalName -or -not $Operation -or ($Operation -eq 'Set' -and (-not $ForwardTo -or -not $PSBoundParameters.ContainsKey('KeepCopy'))))) { throw 'NoInteractive requires mailbox, Operation and explicit ForwardTo/KeepCopy for Set.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-WFTask -TaskId 'exchange.set-mailboxforwarding' -TaskName 'Mailbox forwarding' -Exchange
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'Mailbox user UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-EX17Step 'Forwarding' '' Cancelled -PassThru:$PassThru; return }
$target=Get-WFMailboxTarget $UserPrincipalName $tenant
$before=$target.Mailbox | Select-Object Identity,PrimarySmtpAddress,ForwardingAddress,ForwardingSmtpAddress,DeliverToMailboxAndForward
$before | Format-List | Out-Host
Write-Host 'Mailbox-level forwarding only. Inbox rules and outbound forwarding policies are separate; saving settings does not prove message delivery.' -ForegroundColor DarkYellow
if ($WorkflowApproval) { if (-not $Operation -or ($Operation -eq 'Set' -and (-not $ForwardTo -or -not $PSBoundParameters.ContainsKey('KeepCopy')))) { throw 'Approved workflow settings are incomplete. Rebuild the plan.' } }
if (-not $Operation) {
    $choice=([string](Read-Host '[1] Set  [2] Remove  [0] View only')).Trim()
    $Operation=switch ($choice) {'1' {'Set'} '2' {'Remove'} default {'View'}}
}
if ($Operation -eq 'View' -and $PlanOnly) { [pscustomobject]@{PlanKind='Offboarding6B';Settings=@{Operation='View'};Summary='View forwarding only; no change'}; return }
if ($Operation -eq 'View') { Complete-EX17Step 'Forwarding' $target.Identity Viewed -PassThru:$PassThru; return }
if ($Operation -eq 'Set') {
    if (-not $ForwardTo) { $ForwardTo=([string](Read-Host 'Forward to email address')).Trim() }
    try { $parsed=[System.Net.Mail.MailAddress]::new($ForwardTo); if ($parsed.Address -ne $ForwardTo) { throw 'Use an address only.' } } catch { throw 'Enter one valid email address, without a display name.' }
    if ($ForwardTo -ieq $target.Identity) { throw 'Cannot forward a mailbox to itself.' }
    if (-not $PSBoundParameters.ContainsKey('KeepCopy')) {
        $answer=([string](Read-Host 'Keep a copy in the original mailbox? [Y/n]')).Trim()
        $KeepCopy=($answer -notmatch '^(?i)n(o)?$')
    }
}
if ($PlanOnly) {
    $settings=@{Operation=$Operation}
    if ($Operation -eq 'Set') { $settings.ForwardTo=$ForwardTo; $settings.KeepCopy=$KeepCopy }
    [pscustomobject]@{PlanKind='Offboarding6B';Settings=$settings;Summary=($settings | ConvertTo-Json -Compress)}
    return
}
$action=if ($Operation -eq 'Remove') {'Remove mailbox-level forwarding'} else {"Set forwarding to $ForwardTo; keep local copy: $KeepCopy"}
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $target.User -Action 'Forwarding' -Bound $PSBoundParameters
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action $action -Target $target.Identity -Impact High)) { Complete-EX17Step 'Forwarding' $target.Identity Cancelled -PassThru:$PassThru; return }
if (-not $PSCmdlet.ShouldProcess($target.Identity,$action)) { Complete-EX17Step 'Forwarding' $target.Identity Planned -PassThru:$PassThru; return }
$null=Save-UMJson -Value $before -Label 'Forwarding-Before'
$params=@{Identity=$target.Identity;ForwardingAddress=$null;ErrorAction='Stop';Confirm=$false}
if ($Operation -eq 'Remove') { $params.ForwardingSmtpAddress=$null; $params.DeliverToMailboxAndForward=$false }
else { $params.ForwardingSmtpAddress=$ForwardTo; $params.DeliverToMailboxAndForward=$KeepCopy }
Set-Mailbox @params
$after=Get-Mailbox -Identity $target.Identity -ErrorAction Stop
if ($Operation -eq 'Remove') {
    if ($after.ForwardingAddress -or $after.ForwardingSmtpAddress) { throw 'Forwarding removal not yet verified.' }
} else {
    if (([string]$after.ForwardingSmtpAddress -replace '^smtp:','') -ine $ForwardTo -or [bool]$after.DeliverToMailboxAndForward -ne $KeepCopy -or $after.ForwardingAddress) { throw 'Forwarding settings not yet verified.' }
}
Complete-EX17Step 'Forwarding' $target.Identity Success -Detail $action -PassThru:$PassThru
