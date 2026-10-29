#Requires -Version 7.4
<# .SYNOPSIS
Convert an existing cloud user mailbox to shared; no license removal or user deletion.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and -not $UserPrincipalName) { throw 'NoInteractive requires UserPrincipalName.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-WFTask -TaskId 'exchange.convert-shared' -TaskName 'Convert user mailbox to shared' -Exchange
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'User UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-EX17Step 'Convert to shared' '' Cancelled -PassThru:$PassThru; return }
$target=Get-WFMailboxTarget $UserPrincipalName $tenant
if ($target.User['accountEnabled'] -ne $false -and -not $WhatIfPreference) { throw "Sign-in must already be Blocked. Run 'Block sign-in and revoke sessions' first. Shared mailbox conversion itself does not block sign-in." }
if ([string]$target.Mailbox.RecipientTypeDetails -eq 'SharedMailbox') { Complete-EX17Step 'Convert to shared' $target.Identity Success -Detail 'Already shared' -PassThru:$PassThru; return }
if (-not @($target.User['assignedLicenses']).Count) { throw 'The user must still be licensed before conversion.' }
Write-Host 'Convert to shared only. Keep the user account. License eligibility and delegation are separate steps.' -ForegroundColor DarkYellow
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $target.User -Action 'ConvertShared' -Bound $PSBoundParameters
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action 'Convert user mailbox to shared; retain account and licenses' -Target $target.Identity -Impact High)) { Complete-EX17Step 'Convert to shared' $target.Identity Cancelled -PassThru:$PassThru; return }
if (-not $PSCmdlet.ShouldProcess($target.Identity,'Convert mailbox to shared')) { Complete-EX17Step 'Convert to shared' $target.Identity Planned -PassThru:$PassThru; return }
$null=Save-UMJson -Value ($target.Mailbox | Select-Object Identity,RecipientTypeDetails,ExchangeGuid,PrimarySmtpAddress) -Label 'SharedConversion-Before'
Set-Mailbox -Identity $target.Identity -Type Shared -Confirm:$false -ErrorAction Stop
$verified=$false
for ($attempt=0; $attempt -lt 6; $attempt++) {
    $after=Get-Mailbox -Identity $target.Identity -ErrorAction Stop
    if ([string]$after.RecipientTypeDetails -eq 'SharedMailbox') { $verified=$true; break }
    Start-Sleep -Seconds 5
}
if (-not $verified) { throw 'Conversion requested but not yet verified. Do not remove licenses; inspect Exchange before retrying.' }
Complete-EX17Step 'Convert to shared' $target.Identity Success -PassThru:$PassThru
