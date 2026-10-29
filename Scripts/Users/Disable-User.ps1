#Requires -Version 7.4
<# .SYNOPSIS
Guided offboarding: reuse standalone tasks and pass the resolved user ID to each.
.DESCRIPTION
Settings are collected before one workflow approval; standalone tasks retain confirmations. Failing a step
stops the remaining workflow, including license removal. OneDrive archive uses server-side moves; failures/exclusions stop later work.
WhatIf is explicitly passed to every child; this dispatcher performs no tenant mutations.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt,
            [ValidateSet('BlockAccess','Forwarding','AutoReply','ConvertShared','Delegation','RemoveLicenses','ArchiveOneDrive','DeleteUser')][string[]]$Actions)
$ErrorActionPreference='Stop'
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'users.disable-user' -TaskName 'Plan guided user offboarding' -Scopes @('User.Read.All')
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'User UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { return }
$user=Get-UMUser $UserPrincipalName; Assert-UMCloudMember -User $user -Tenant $tenant
Write-Host ('OFFBOARD: '+$user['displayName']+' <'+$user['userPrincipalName']+'>') -ForegroundColor Cyan
$signInStatus=if ($user['accountEnabled'] -eq $true) { 'Allowed' } elseif ($user['accountEnabled'] -eq $false) { 'Blocked' } else { 'Unknown' }
Write-Host ('Current sign-in status: '+$signInStatus) -ForegroundColor DarkGray

# Guided collection only. No tenant changes occur before final approval.
$wizardMode=-not $PSBoundParameters.ContainsKey('Actions')
$wizardMailboxPlans=@{}
$wizardLicensePlan=$null
$wizardArchivePlan=$null
function Read-WFOffboardingAnswer {
    param([string]$Prompt)
    while ($true) {
        $answer=([string](Read-Host ($Prompt+' [y/N]; C cancels'))).Trim()
        if ($answer -imatch '^c(ancel)?$') { return 'Cancel' }
        if (-not $answer -or $answer -imatch '^n(o)?$') { return 'No' }
        if ($answer -imatch '^y(es)?$') { return 'Yes' }
        Write-Host 'Enter Y, N, or C.' -ForegroundColor Yellow
    }
}
if ($wizardMode) {
    $Actions=@()
    $questions=@(
        @{Number=1;Action='BlockAccess';Label='Block sign-in and revoke sessions?'},
        @{Number=2;Action='Forwarding';Label='Configure mailbox forwarding?';Path='../Exchange/Set-MailboxForwarding.ps1'},
        @{Number=3;Action='AutoReply';Label='Configure automatic replies?';Path='../Exchange/Set-MailboxAutoReply.ps1'},
        @{Number=4;Action='ConvertShared';Label='Convert the existing mailbox to shared?'},
        @{Number=5;Action='Delegation';Label='Configure mailbox delegation?';Path='../Exchange/Set-MailboxDelegates.ps1'},
        @{Number=6;Action='ArchiveOneDrive';Label='Archive OneDrive to SharePoint'},
        @{Number=7;Action='RemoveLicenses';Label='Remove selected direct user licenses?'},
        @{Number=8;Action='DeleteUser';Label='Delete the Microsoft 365 user account?'}
    )
    Write-Host 'Answer each question. Enter skips; C cancels. Changes run only after the final approval.' -ForegroundColor Cyan
    foreach ($question in $questions) {
        $answer=Read-WFOffboardingAnswer ('[{0}/8] {1}' -f $question.Number,$question.Label)
        if ($answer -eq 'Cancel') { Write-Host 'Cancelled. No workflow steps executed.'; return }
        if ($answer -ne 'Yes') { continue }
        if ($question.Action -eq 'DeleteUser' -and 'ConvertShared' -in $Actions) {
            Write-Host 'Shared conversion preserves the account; deletion defeats that intent.' -ForegroundColor Yellow
            $resolve=Read-WFOffboardingAnswer 'Drop shared conversion and include account deletion instead?'
            if ($resolve -eq 'Cancel') { Write-Host 'Cancelled. No workflow steps executed.'; return }
            if ($resolve -ne 'Yes') { Write-Host 'Deletion skipped; shared conversion retained.'; continue }
            $Actions=@($Actions | Where-Object { $_ -ne 'ConvertShared' })
            # A previously planned license removal may depend on conversion.
            if ('RemoveLicenses' -in $Actions) {
                Write-Host 'License removal was planned with shared conversion. Restart and select a compatible plan; no changes executed.' -ForegroundColor Yellow
                return
            }
        }
        if ($question.ContainsKey('Path')) {
            $collected=@(& (Join-Path $PSScriptRoot $question.Path) -UserPrincipalName $user['id'] -PlanOnly)
            if ($collected.Count -ne 1 -or $collected[0].PlanKind -ne 'Offboarding6B' -or $collected[0].Settings -isnot [hashtable]) {
                Write-Host 'Settings cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
                return
            }
            $entry=$collected[0]
            if ($entry.Settings.Operation -eq 'View' -or $entry.Settings.State -eq 'View') {
                Write-Host 'View only; no change added to the plan.' -ForegroundColor DarkGray
                continue
            }
            $wizardMailboxPlans[$question.Action]=$entry
        }
        if ($question.Action -eq 'ArchiveOneDrive') {
            $archiveOutput=@(& (Join-Path $PSScriptRoot '../OneDrive/Backup-OneDrive.ps1') -UserPrincipalName $user['id'] -PlanOnly)
            if ($archiveOutput.Count -ne 1 -or $archiveOutput[0].PlanKind -ne 'OffboardingArchive' -or $archiveOutput[0].Settings -isnot [hashtable]) {
                Write-Host 'Archive planning cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
                return
            }
            if ($archiveOutput[0].NoOp) { Write-Host 'OneDrive is empty; archive step skipped.'; continue }
            $wizardArchivePlan=$archiveOutput[0]
        }
        if ($question.Action -eq 'RemoveLicenses') {
            $licenseOutput=@(& (Join-Path $PSScriptRoot 'Remove-UserLicenses.ps1') -UserPrincipalName $user['id'] -PlanOnly -PlannedBlockAccess:('BlockAccess' -in $Actions -or 'ConvertShared' -in $Actions) -PlannedSharedConversion:('ConvertShared' -in $Actions))
            if ($licenseOutput.Count -ne 1 -or $licenseOutput[0].PlanKind -ne 'Offboarding6C' -or $licenseOutput[0].Settings -isnot [hashtable]) {
                Write-Host 'License planning cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
                return
            }
            if ($licenseOutput[0].NoOp) { Write-Host 'No assigned licenses; license removal skipped.'; continue }
            $wizardLicensePlan=$licenseOutput[0]
        }
        $Actions+=,[string]$question.Action
    }
    if (-not $Actions.Count) { Write-Host 'No actions selected. No changes made.'; return }
}

# Remember explicit deletion selection. The existing deletion-planning
# section will add the actual deletion step only after eligibility checks.
$explicitDeleteRequested = 'DeleteUser' -in $Actions

if ($explicitDeleteRequested -and 'ConvertShared' -in $Actions) {
    throw 'Delete user and Convert mailbox to shared cannot be selected together. No workflow steps executed.'
}

if ($explicitDeleteRequested) {
    # Remove the planning marker; deletion is appended later, exactly once.
    $Actions = @($Actions | Where-Object { $_ -ne 'DeleteUser' })

}
# Phase 7A: conversion always includes both blocking sign-in and revocation.
if ('ConvertShared' -in $Actions -and 'BlockAccess' -notin $Actions) {
    $Actions=@('BlockAccess')+@($Actions)
    Write-Host 'Added Block sign-in and revoke sessions because shared conversion is selected. Review this in the final plan.' -ForegroundColor Yellow
}
$routes=@(
    @{Action='BlockAccess';Path='Block-UserAccess.ps1'},
    @{Action='ConvertShared';Path='../Exchange/ConvertTo-SharedMailbox.ps1'},
    @{Action='Forwarding';Path='../Exchange/Set-MailboxForwarding.ps1'},
    @{Action='AutoReply';Path='../Exchange/Set-MailboxAutoReply.ps1'},
    @{Action='Delegation';Path='../Exchange/Set-MailboxDelegates.ps1'},
    @{Action='ArchiveOneDrive';Path='../OneDrive/Backup-OneDrive.ps1'},
    @{Action='RemoveLicenses';Path='Remove-UserLicenses.ps1'}
)
$steps=@($routes | Where-Object { $_.Action -in $Actions })
if (-not $steps.Count -and -not $explicitDeleteRequested) { return }
foreach ($step in $steps) { if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $step.Path) -PathType Leaf)) { throw ('Required task missing: '+$step.Path) } }
# Phase 6A: read-only preflight; existing execution and approvals remain unchanged.
if (@($Actions | Where-Object { $_ -in @('BlockAccess','ConvertShared') }).Count) {
    . (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingPlan.ps1')
    $foundationPlan=New-WFOffboardingFoundationPlan -User $user -Tenant $tenant -Actions $Actions
    Write-Verbose ($foundationPlan | Out-String)
}

# Phase 6B: collect exact mailbox settings before any offboarding writes.
$mailboxPlans=@{}
foreach ($key in $wizardMailboxPlans.Keys) { $mailboxPlans[$key]=$wizardMailboxPlans[$key] }
foreach ($mailStep in @($steps | Where-Object { $_.Action -in @('Forwarding','AutoReply','Delegation') })) {
    if ($mailboxPlans.ContainsKey($mailStep.Action)) { continue }
    Write-Host ('Collect settings: '+$mailStep.Action+' (no changes yet)') -ForegroundColor Cyan
    $collected=@(& (Join-Path $PSScriptRoot $mailStep.Path) -UserPrincipalName $user['id'] -PlanOnly)
    if ($collected.Count -ne 1 -or $collected[0].PlanKind -ne 'Offboarding6B' -or $collected[0].Settings -isnot [hashtable]) {
        Write-Host 'Planning cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
        return
    }
    # View-only is excluded so a Viewed outcome cannot stop later selected tasks.
    $entry=$collected[0]
    if ($entry.Settings.Operation -eq 'View' -or $entry.Settings.State -eq 'View') {
        Write-Host ($mailStep.Action+': view only; excluded from execution.') -ForegroundColor Yellow
        $steps=@($steps | Where-Object { $_.Action -ne $mailStep.Action })
        continue
    }
    $mailboxPlans[$mailStep.Action]=$entry
}
if (-not $steps.Count -and -not $explicitDeleteRequested) { Write-Host 'No executable steps selected.'; return }
# Collect archive settings before any execution. Execution route is before licensing/deletion.
if ('ArchiveOneDrive' -in $Actions) {
    if ($wizardMode -and $null -ne $wizardArchivePlan) { $archiveOutput=@($wizardArchivePlan) }
    else { $archiveOutput=@(& (Join-Path $PSScriptRoot '../OneDrive/Backup-OneDrive.ps1') -UserPrincipalName $user['id'] -PlanOnly) }
    if ($archiveOutput.Count -ne 1 -or $archiveOutput[0].PlanKind -ne 'OffboardingArchive' -or $archiveOutput[0].Settings -isnot [hashtable]) {
        Write-Host 'Archive planning cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
        return
    }
    if ($archiveOutput[0].NoOp) { $steps=@($steps | Where-Object Action -ne 'ArchiveOneDrive') }
    else { $mailboxPlans['ArchiveOneDrive']=$archiveOutput[0] }
}

# Collect license choices only when license removal was selected.
# Phase 6C: select exact direct licenses before the initial workflow approval.
if (@($steps | Where-Object Action -eq 'RemoveLicenses').Count) {
    if ($wizardMode -and $null -ne $wizardLicensePlan) {
        $licenseOutput=@($wizardLicensePlan)
    } else {
    $licenseOutput=@(& (Join-Path $PSScriptRoot 'Remove-UserLicenses.ps1') -UserPrincipalName $user['id'] -PlanOnly -PlannedBlockAccess:('BlockAccess' -in $Actions) -PlannedSharedConversion:('ConvertShared' -in $Actions))
    }
    if ($licenseOutput.Count -ne 1 -or $licenseOutput[0].PlanKind -ne 'Offboarding6C' -or $licenseOutput[0].Settings -isnot [hashtable]) {
        Write-Host 'License planning cancelled or incomplete. No workflow steps executed.' -ForegroundColor Yellow
        return
    }
    if ($licenseOutput[0].NoOp) {
        Write-Host $licenseOutput[0].Summary
        $steps=@($steps | Where-Object Action -ne 'RemoveLicenses')
    } else {
        $mailboxPlans['RemoveLicenses']=$licenseOutput[0]
        Write-Verbose $licenseOutput[0].Summary
    }
}
if (-not $steps.Count -and -not $explicitDeleteRequested) { Write-Host 'No executable steps selected.'; return }
# Never permit a Planned or unverified live prerequisite to authorize license removal.

# Collect account deletion warnings before final workflow approval.
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingDeletionPlan.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.AccountDeletionWarnings.ps1')
$deletionIntent=[pscustomobject]@{
    EligibleForPrompt=$true
    Reason='Account deletion is optional. Mailbox, forwarding and license conditions are reviewed warnings.'
    Requested=$false
    Executable=$false
}
if ($explicitDeleteRequested) {
    $deletionIntent.Requested=$true
} elseif (-not $wizardMode -and 'ConvertShared' -notin $Actions) {
    $deletionIntent=Read-WF7ADeletionIntent -Decision $deletionIntent
} else {
    $deletionIntent.Reason='Account retained; deletion was not selected.'
}
if ($deletionIntent.Requested) {
    $review=Get-WFAccountDeletionWarnings -User $user -Tenant $tenant
    # Warnings and acknowledgment are included in the single final approval.
    $null=Assert-M365Connection -Service Graph -GraphScopes @('User.Read.All','User.ReadWrite.All') -TaskName 'Prepare optional user deletion' -TaskId 'users.disable-user'
    $required=@(
        foreach ($plannedStep in $steps) {
            [string]$plannedStep['Action']
        }
    )
    $mailboxPlans['DeleteUser']=[pscustomobject]@{
        Settings=@{
            RequiredStepIds=$required
            PreservationReviewed=$true
            DeletionWarningsAcknowledged=$true
            ApprovedWarningCodes=[string[]]@($review.Codes)
        }
        Summary=('DELETE ACCOUNT LAST: '+$user['userPrincipalName']+' | ID '+$user['id']+"`n"+($review.Messages -join "`n"))
    }
    $deletePath=Join-Path $PSScriptRoot 'Remove-OffboardedUser.ps1'
    if (-not (Test-Path -LiteralPath $deletePath -PathType Leaf)) { throw 'Deletion task missing. No workflow steps executed.' }
    $steps+=@{Action='DeleteUser';Path='Remove-OffboardedUser.ps1'}
    $deletionIntent.Executable=$true
}

$stepLabels=@{
    BlockAccess='Block sign-in and revoke sessions'
    ConvertShared='Convert mailbox to shared'
    Forwarding='Configure mailbox forwarding'
    AutoReply='Configure automatic replies'
    Delegation='Manage mailbox delegation'
    ArchiveOneDrive='MOVE OneDrive to SharePoint'
    RemoveLicenses='Remove selected direct licenses'
    DeleteUser='DELETE user account (last; no permanent purge)'
}
$stepNames=@($steps | ForEach-Object { $stepLabels[$_.Action] })
Write-Verbose ('Execution order: '+($stepNames -join ' -> '))
$frozenSettings=@{}
foreach ($step in $steps) {
    $settings=@{}
    if ($mailboxPlans.ContainsKey($step.Action)) { $settings=Copy-WF6DSettings $mailboxPlans[$step.Action].Settings }
    $frozenSettings[$step.Action]=$settings
}
Write-Host ''
$title=if ($deletionIntent.Requested -and $steps.Count -eq 1) { 'DELETE MICROSOFT 365 USER' } else { 'OFFBOARD USER' }
Write-Host $title -ForegroundColor Cyan
Write-Host ('User: '+$user['displayName']+' <'+$user['userPrincipalName']+'>')
$tenantLabel=if ($tenant.InitialDomain) { $tenant.InitialDomain } else { $tenant.TenantId }
Write-Host ('Tenant: '+$tenantLabel)
Write-Host ''
Write-Host 'Planned actions:'
foreach ($step in $steps) {
    Write-Host ('- '+$stepLabels[$step.Action])
    if ($step.Action -eq 'ArchiveOneDrive') {
        Write-Host ('  '+$mailboxPlans['ArchiveOneDrive'].Summary)
        if ($frozenSettings['ArchiveOneDrive'].CreateSite) { Write-Host ('  Create site: '+$frozenSettings['ArchiveOneDrive'].SiteTitle) }
        Write-Host ('  Grant destination SITE Edit: '+(@($frozenSettings['ArchiveOneDrive'].AccessUsers) -join ', '))
        Write-Host ('  Add temporary source admin if needed: '+$frozenSettings['ArchiveOneDrive'].GrantSourceAdmin+'; remove only the grant added by this run.')
    } elseif ($mailboxPlans.ContainsKey($step.Action) -and $step.Action -ne 'DeleteUser') {
        foreach ($setting in $frozenSettings[$step.Action].GetEnumerator() | Sort-Object Key) {
            $value=$setting.Value
            if ($value -is [datetime]) { $value=$value.ToString('o') }
            elseif ($value -is [array]) { $value=$value -join ', ' }
            Write-Host ('  '+$setting.Key+': '+[string]$value)
        }
    }
}
if ($deletionIntent.Requested) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($code in @($review.Codes)) {
        $warning=switch ($code) {
            'SharedMailbox' {'Shared mailbox exists; deleting this account affects that mailbox.'}
            'Forwarding' {'Forwarding is configured; account-based forwarding may stop.'}
            'AssignedLicenses' {'Licenses are assigned. Deletion does not reduce purchased subscription quantities.'}
            'MailboxUnknown' {'Mailbox impact could not be verified.'}
            'RecipientOther' {'An Exchange recipient is associated with this account; its impact is unverified.'}
            'LicensesUnknown' {'Assigned licenses could not be verified.'}
            default { 'Unverified account impact: '+$code }
        }
        Write-Host ('- '+$warning) -ForegroundColor Yellow
    }
    Write-Host '- Deletion affects access and associated data. Review preservation obligations. No permanent purge.' -ForegroundColor Yellow
}
$planId=[guid]::NewGuid().ToString('N')
if (-not $WhatIfPreference) {
    if ($deletionIntent.Requested) {
        if (([string](Read-Host 'Execute this plan, including account deletion? Type DELETE to confirm; Enter cancels')).Trim() -cne 'DELETE') { return }
    } elseif ($frozenSettings.ContainsKey('ArchiveOneDrive')) {
        $word=if ($frozenSettings['ArchiveOneDrive'].ConflictBehavior -eq 1) {'OVERWRITE'} else {'MOVE'}
        if (([string](Read-Host ('Execute this plan? Type '+$word+' to confirm; Enter cancels'))).Trim() -cne $word) { return }
    } else {
        if ((Read-Host 'Execute this plan? [y/N]') -notmatch '^(?i)y(es)?$') { return }
    }
}
$workflowApprovals=@{}
if (-not $WhatIfPreference) {
    foreach ($step in $steps) {
        $delegateId=''
        if ($step.Action -eq 'Delegation') { $delegateId=[string]$mailboxPlans['Delegation'].DelegateId; if (-not $delegateId) { throw 'Missing planned delegate identity. No steps executed.' } }
        $settings=Copy-WF6DSettings $frozenSettings[$step.Action]
        $workflowApprovals[$step.Action]=[pscustomobject]@{
            Kind='Offboarding6D';Approved=$true;PlanId=$planId;ExpiresUtc=[datetime]::UtcNow.AddHours(1)
            TenantId=[string]$tenant.TenantId;UserId=[string]$user['id'];UPN=[string]$user['userPrincipalName'];Action=$step.Action
            Settings=$settings;SettingsText=(Get-WF6DSettingsText $settings);DelegateId=$delegateId
        }
    }
}
$results=@()
foreach ($step in $steps) {
    try {
        $childArgs=@{UserPrincipalName=$user['id'];PassThru=$true;WhatIf=[bool]$WhatIfPreference}
        foreach ($key in $frozenSettings[$step.Action].Keys) { $childArgs[$key]=$frozenSettings[$step.Action][$key] }
        if ($workflowApprovals.ContainsKey($step.Action)) { $childArgs.WorkflowApproval=$workflowApprovals[$step.Action] }
        if ($step.Action -eq 'DeleteUser') { $childArgs.PriorResults=@($results) }
        $output=@(& (Join-Path $PSScriptRoot $step.Path) @childArgs)
        $outcomes=@($output | Where-Object { $_.PSObject.Properties['Status'] })
        if ($outcomes.Count -ne 1) { throw 'Child task did not return exactly one structured outcome.' }
        $outcome=$outcomes[0]
        $results+=[pscustomobject]@{Step=$step.Action;Result=$outcome.Status;Detail=$outcome.Detail}
        if ($outcome.Status -ne 'Success' -and -not ($WhatIfPreference -and $outcome.Status -eq 'Planned')) { Write-Host 'Workflow stopped; later steps were not executed.' -ForegroundColor DarkYellow; break }
    } catch {
        $results+=[pscustomobject]@{Step=$step.Action;Result='Failed';Detail=$_.Exception.Message}
        Write-M365Log -Message ('Offboarding stopped at '+$stepLabels[$step.Action]+' ['+$step.Action+']: '+$_.Exception.Message) -Level Error
        break
    }
}
$completed=@($results.Step)
foreach ($step in $steps) {
    if ($step.Action -notin $completed) { $results+=[pscustomobject]@{Step=$step.Action;Result='Not run';Detail='Earlier step stopped the workflow'} }
}
# Keep internal action IDs for completion/dependency tracking; translate only
# the final user-facing output. StepId preserves the original report identifier.
$displayResults=@($results | ForEach-Object {
    $displayLabel=if ($stepLabels.ContainsKey([string]$_.Step)) { $stepLabels[[string]$_.Step] } else { [string]$_.Step }
    [pscustomobject]@{Step=$displayLabel;StepId=$_.Step;Result=$_.Result;Detail=$_.Detail}
})
Write-UT19Results -Results $displayResults -Label 'OffboardingWorkflow'
