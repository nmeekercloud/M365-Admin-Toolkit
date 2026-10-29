#Requires -Version 7.4
<# .SYNOPSIS
View, enable, disable or schedule automatic replies without changing calendar events.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[ValidateSet('View','Enabled','Disabled','Scheduled')][string]$State,
      [string]$InternalMessage,[string]$ExternalMessage,
      [ValidateSet('None','Known','All')][string]$ExternalAudience='None',
      [datetime]$StartTime,[datetime]$EndTime,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[switch]$PlanOnly,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and (-not $UserPrincipalName -or -not $State -or ($State -notin @('View','Disabled') -and (-not $InternalMessage -or ($ExternalAudience -ne 'None' -and -not $ExternalMessage))) -or ($State -eq 'Scheduled' -and (-not $PSBoundParameters.ContainsKey('StartTime') -or -not $PSBoundParameters.ContainsKey('EndTime'))))) { throw 'NoInteractive requires mailbox, State and all applicable message/schedule settings.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-WFTask -TaskId 'exchange.set-mailboxautoreply' -TaskName 'Mailbox automatic replies' -Exchange
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'Mailbox user UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-EX17Step 'Automatic replies' '' Cancelled -PassThru:$PassThru; return }
$target=Get-WFMailboxTarget $UserPrincipalName $tenant
$before=Get-MailboxAutoReplyConfiguration -Identity $target.Identity -ErrorAction Stop
$before | Select-Object AutoReplyState,StartTime,EndTime,ExternalAudience,InternalMessage,ExternalMessage | Format-List | Out-Host
if ($WorkflowApproval) { if (-not $State -or ($State -ne 'Disabled' -and (-not $InternalMessage -or -not $PSBoundParameters.ContainsKey('ExternalAudience') -or ($ExternalAudience -ne 'None' -and -not $ExternalMessage) -or ($State -eq 'Scheduled' -and (-not $PSBoundParameters.ContainsKey('StartTime') -or -not $PSBoundParameters.ContainsKey('EndTime')))))) { throw 'Approved workflow settings are incomplete. Rebuild the plan.' } }
if (-not $State) {
    $choice=([string](Read-Host '[1] Enable  [2] Disable  [3] Schedule  [0] View only')).Trim()
    $State=switch ($choice) {'1' {'Enabled'} '2' {'Disabled'} '3' {'Scheduled'} default {'View'}}
}
if ($State -eq 'View' -and $PlanOnly) { [pscustomobject]@{PlanKind='Offboarding6B';Settings=@{State='View'};Summary='View automatic replies only; no change'}; return }
if ($State -eq 'View') { Complete-EX17Step 'Automatic replies' $target.Identity Viewed -PassThru:$PassThru; return }
$params=@{Identity=$target.Identity;AutoReplyState=$State;ErrorAction='Stop';Confirm=$false}
if ($State -ne 'Disabled') {
    if (-not $InternalMessage) { $InternalMessage=[string](Read-Host 'Internal reply message') }
    if ([string]::IsNullOrWhiteSpace($InternalMessage)) { throw 'Internal message is required.' }
    if (-not $NoInteractive -and -not $PSBoundParameters.ContainsKey('ExternalAudience')) {
        $choice=([string](Read-Host 'External audience: [0] None [1] Known contacts [2] All [0]')).Trim()
        $ExternalAudience=switch ($choice) {'1' {'Known'} '2' {'All'} default {'None'}}
    }
    if ($ExternalAudience -ne 'None') {
        if (-not $ExternalMessage) { $ExternalMessage=[string](Read-Host 'External reply message') }
        if ([string]::IsNullOrWhiteSpace($ExternalMessage)) { throw 'External message is required for the selected audience.' }
    }
    $params.InternalMessage=$InternalMessage; $params.ExternalAudience=$ExternalAudience
    $params.ExternalMessage=if ($ExternalAudience -eq 'None') { $null } else { $ExternalMessage }
    if ($State -eq 'Scheduled') {
        Write-Host ('Times use this PowerShell session/local time zone: '+[TimeZoneInfo]::Local.DisplayName)
        if (-not $PSBoundParameters.ContainsKey('StartTime')) { $StartTime=[datetime]::ParseExact((Read-Host 'Start yyyy-MM-dd HH:mm'),'yyyy-MM-dd HH:mm',[cultureinfo]::InvariantCulture) }
        if (-not $PSBoundParameters.ContainsKey('EndTime')) { $EndTime=[datetime]::ParseExact((Read-Host 'End yyyy-MM-dd HH:mm'),'yyyy-MM-dd HH:mm',[cultureinfo]::InvariantCulture) }
        if ($EndTime -le $StartTime -or $EndTime -le (Get-Date)) { throw 'End must be in the future and later than start.' }
        $params.StartTime=$StartTime; $params.EndTime=$EndTime
    }
}
if ($PlanOnly) {
    $settings=@{State=$State}
    if ($State -ne 'Disabled') {
        $settings.InternalMessage=$InternalMessage; $settings.ExternalAudience=$ExternalAudience
        if ($ExternalAudience -ne 'None') { $settings.ExternalMessage=$ExternalMessage }
        if ($State -eq 'Scheduled') { $settings.StartTime=$StartTime; $settings.EndTime=$EndTime }
    }
    [pscustomobject]@{PlanKind='Offboarding6B';Settings=$settings;Summary=($settings | ConvertTo-Json -Compress)}
    return
}
$params.GetEnumerator() | Where-Object Key -notin @('ErrorAction','Confirm') | Sort-Object Key | Format-Table -Wrap | Out-Host
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $target.User -Action 'AutoReply' -Bound $PSBoundParameters
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action ('Set automatic replies: '+$State) -Target $target.Identity -Impact High)) { Complete-EX17Step 'Automatic replies' $target.Identity Cancelled -PassThru:$PassThru; return }
if (-not $PSCmdlet.ShouldProcess($target.Identity,('Set automatic replies: '+$State))) { Complete-EX17Step 'Automatic replies' $target.Identity Planned -PassThru:$PassThru; return }
$null=Save-UMJson -Value ($before | Select-Object AutoReplyState,StartTime,EndTime,ExternalAudience,InternalMessage,ExternalMessage) -Label 'AutoReply-Before'
Set-MailboxAutoReplyConfiguration @params
$after=Get-MailboxAutoReplyConfiguration -Identity $target.Identity -ErrorAction Stop
if ([string]$after.AutoReplyState -ine $State) { throw 'Automatic reply state not yet verified.' }
if ($State -ne 'Disabled' -and [string]$after.ExternalAudience -ine $ExternalAudience) { throw 'External audience not yet verified.' }
Complete-EX17Step 'Automatic replies' $target.Identity Success -PassThru:$PassThru
