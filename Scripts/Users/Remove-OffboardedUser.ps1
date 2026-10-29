#Requires -Version 7.4
<# .SYNOPSIS
Workflow-only final user deletion. No permanent purge and no automatic delete retries.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$UserPrincipalName,
      [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RequiredStepIds,
      [bool]$PreservationReviewed=$false,[object[]]$PriorResults=@(),
      [bool]$DeletionWarningsAcknowledged=$false,[AllowEmptyCollection()][string[]]$ApprovedWarningCodes=@(),
      [object]$WorkflowApproval,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingDeletionPlan.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingDeletionChecks.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.AccountDeletionWarnings.ps1')
# This task is only exposed through the guided offboarding plan, not a standalone menu.
$tenant=Initialize-WFTask -TaskId 'users.disable-user' -TaskName 'Final approved offboarding user deletion' -Scopes @('User.Read.All','User.ReadWrite.All')
$user=Get-UMUser $UserPrincipalName
Assert-UMCloudMember -User $user -Tenant $tenant
Assert-WF7BPrerequisites -RequiredStepIds $RequiredStepIds -PriorResults $PriorResults -WhatIfMode:([bool]$WhatIfPreference)
if (-not $PreservationReviewed) { throw 'Independent preservation review was not acknowledged.' }
$approved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $user -Action DeleteUser -Bound $PSBoundParameters
if (-not $approved -and -not $WhatIfPreference) { throw 'Deletion requires a fresh approved guided-offboarding plan; standalone execution is blocked.' }
if ($approved) { $ConfirmPreference='None' }
if ('BlockAccess' -in $RequiredStepIds -and -not $WhatIfPreference -and $user['accountEnabled'] -ne $false) { throw 'Selected block-sign-in prerequisite was not verified.' }
# Reinspect impacts. Previously accepted warning categories are permitted.
# Newly discovered categories require a rebuilt plan, not silent expansion.
if (-not $DeletionWarningsAcknowledged) { throw 'Deletion impact warnings were not acknowledged.' }
$review=Get-WFAccountDeletionWarnings -User $user -Tenant $tenant
foreach ($message in $review.Messages) { Write-Verbose $message }
$newWarnings=@($review.Codes | Where-Object { $_ -notin $ApprovedWarningCodes })
if ($newWarnings.Count) { throw ('New deletion impact warnings require a fresh plan and acceptance: '+($newWarnings -join ', ')) }
if (-not $PSCmdlet.ShouldProcess(($user['userPrincipalName']+' | '+$user['id']),'Delete user account; no permanent purge')) {
    Complete-WFStep 'Delete user account' $user['userPrincipalName'] Planned -PassThru:$PassThru
    return
}
$null=Save-UMJson -Value $user -Label 'UserDeletion-Before'
# Re-read identity and block state immediately before the request.
$fresh=Get-UMUser $user['id']
Assert-UMCloudMember -User $fresh -Tenant $tenant
if ([string]$fresh['id'] -ine [string]$user['id'] -or [string]$fresh['userPrincipalName'] -ine [string]$user['userPrincipalName'] -or ('BlockAccess' -in $RequiredStepIds -and $fresh['accountEnabled'] -ne $false)) { throw 'Target changed before deletion. Rebuild the plan.' }
# Revalidate approval expiry and arguments after potentially slow preflight reads.
$null=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $fresh -Action DeleteUser -Bound $PSBoundParameters
$id=[guid]::Empty
if (-not [guid]::TryParse([string]$fresh['id'],[ref]$id)) { throw 'Invalid immutable target ID.' }
try {
    # Send once. No retry loop around DELETE, including after timeouts.
    $deleteBound=@{}
    foreach ($key in $PSBoundParameters.Keys) { $deleteBound[$key]=$PSBoundParameters[$key] }
    $verification=Invoke-WF7BDeleteOnce -UserId $id -BeforeDelete {
        # Recheck after any interactive reconnect; never trust an expired approval.
        $lastRead=Get-UMUser $user['id']
        Assert-UMCloudMember -User $lastRead -Tenant $tenant
        if ([string]$lastRead['id'] -ine [string]$user['id'] -or
            [string]$lastRead['userPrincipalName'] -ine [string]$user['userPrincipalName'] -or
            ('BlockAccess' -in $RequiredStepIds -and $lastRead['accountEnabled'] -ne $false)) {
            throw 'Target changed during authentication. Rebuild the plan.'
        }
        Assert-WF7BPrerequisites -RequiredStepIds $RequiredStepIds -PriorResults $PriorResults
        $lastReview=Get-WFAccountDeletionWarnings -User $lastRead -Tenant $tenant
        if (@($lastReview.Codes | Where-Object { $_ -notin $ApprovedWarningCodes }).Count) {
            throw 'New deletion warnings appeared. Rebuild the plan.'
        }
        if (-not (Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $lastRead -Action DeleteUser -Bound $deleteBound)) {
            throw 'Final workflow approval was not accepted.'
        }
        return $true
    } -AfterDelete { Test-WF7BDeletedUser -UserId $id }
} catch {
    Write-M365Log -Message ('User deletion failed or response uncertain for '+$id+': '+$_.Exception.Message+'. Do not automatically retry; inspect active/deleted users.') -Level Error
    throw ('Deletion did not complete: '+$_.Exception.Message+' No automatic retry; inspect active/deleted users before retrying.')
}
if ($null -eq $verification -or $verification.Status -notin @('Success','VerificationIncomplete')) {
    $verification=[pscustomobject]@{Status='VerificationIncomplete';Detail='DELETE returned, but no valid structured verification result was received. Do not retry deletion; inspect active/deleted users.'}
}
if ($verification.Status -eq 'VerificationIncomplete') {
    Write-M365Log -Message $verification.Detail -Level Warning
}
Complete-WFStep 'Delete user account' $user['userPrincipalName'] $verification.Status -Detail $verification.Detail -PassThru:$PassThru
