#Requires -Version 7.4
<# .SYNOPSIS
View/add/remove direct user FullAccess, SendAs and SendOnBehalf rights; additive changes preserve others.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$DelegateUserPrincipalName,
      [ValidateSet('View','Add','Remove')][string]$Operation,
      [ValidateSet('FullAccess','SendAs','SendOnBehalf')][string[]]$Rights,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[switch]$PlanOnly,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and (-not $UserPrincipalName -or -not $Operation -or ($Operation -ne 'View' -and (-not $DelegateUserPrincipalName -or -not $Rights)))) { throw 'NoInteractive requires mailbox, Operation and delegate/Rights for changes.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-WFTask -TaskId 'exchange.set-mailboxdelegates' -TaskName 'Mailbox delegates' -Exchange
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'Mailbox user UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-EX17Step 'Delegation' '' Cancelled -PassThru:$PassThru; return }
$target=Get-WFMailboxTarget $UserPrincipalName $tenant
$permissions=@(Get-MailboxPermission -Identity $target.Identity -ErrorAction Stop | Where-Object { -not $_.IsInherited })
$sendAs=@(Get-RecipientPermission -Identity $target.Identity -ErrorAction Stop)
$permissions | Select-Object User,AccessRights,Deny | Format-Table | Out-Host
$sendAs | Select-Object Trustee,AccessRights,AccessControlType | Format-Table | Out-Host
Write-Host ('Send on behalf: '+(@($target.Mailbox.GrantSendOnBehalfTo) -join ', '))
if ($WorkflowApproval) { if (-not $Operation -or -not $DelegateUserPrincipalName -or -not @($Rights).Count) { throw 'Approved workflow settings are incomplete. Rebuild the plan.' } }
if (-not $Operation) {
    $choice=([string](Read-Host '[1] Add direct user rights [2] Remove direct user rights [0] View only')).Trim()
    $Operation=switch ($choice) {'1' {'Add'} '2' {'Remove'} default {'View'}}
}
if ($Operation -eq 'View' -and $PlanOnly) { [pscustomobject]@{PlanKind='Offboarding6B';Settings=@{Operation='View'};Summary='View delegation only; no change'}; return }
if ($Operation -eq 'View') { Complete-EX17Step 'Delegation' $target.Identity Viewed -PassThru:$PassThru; return }
if (-not $DelegateUserPrincipalName) { $DelegateUserPrincipalName=([string](Read-Host 'Delegate user UPN')).Trim() }
$delegateUser=Get-UMUser $DelegateUserPrincipalName
Assert-UMCloudMember -User $delegateUser -Tenant $tenant -AllowSelf
if ($delegateUser['id'] -eq $target.User['id']) { throw 'Mailbox owner cannot be selected as their own delegate.' }
$delegate=Get-Recipient -Identity $delegateUser['userPrincipalName'] -ErrorAction Stop
if (-not $delegate.ExternalDirectoryObjectId -or [string]$delegate.ExternalDirectoryObjectId -ine [string]$delegateUser['id']) { throw 'Delegate recipient identity mismatch.' }
if (@($Rights | Where-Object { $_ }).Count -eq 0) {
    $choice=([string](Read-Host 'Rights: 1 FullAccess, 2 SendAs, 3 SendOnBehalf (comma-separated; Enter cancels)')).Trim()
    if (-not $choice) { Complete-EX17Step 'Delegation' $target.Identity Cancelled -PassThru:$PassThru; return }
    $map=@{'1'='FullAccess';'2'='SendAs';'3'='SendOnBehalf'}
    $Rights=@(foreach ($n in @(ConvertTo-UMList $choice)) { if (-not $map.ContainsKey($n)) { throw 'Invalid permission choice.' }; $map[$n] })
}
$plan=@(foreach ($right in @($Rights | Select-Object -Unique)) {
    $exists=Test-WFDelegateRight $target.Identity $delegate $right
    [pscustomobject]@{Right=$right;Existing=$exists;Change=(($Operation -eq 'Add' -and -not $exists) -or ($Operation -eq 'Remove' -and $exists))}
})
$plan | Format-Table | Out-Host
if ($PlanOnly) {
    $settings=@{Operation=$Operation;DelegateUserPrincipalName=[string]$delegateUser['userPrincipalName'];Rights=@($Rights | Select-Object -Unique)}
    [pscustomobject]@{PlanKind='Offboarding6B';Settings=$settings;DelegateId=[string]$delegateUser['id'];Summary=(($settings | ConvertTo-Json -Compress)+'; current rights: '+($plan | ConvertTo-Json -Compress))}
    return
}
$changes=@($plan | Where-Object Change)
if (-not $changes.Count) { Complete-EX17Step 'Delegation' $target.Identity Success -Detail 'No changes needed' -PassThru:$PassThru; return }
$action=$Operation+' '+($changes.Right -join ', ')+' for '+$delegateUser['userPrincipalName']
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $target.User -Action 'Delegation' -Bound $PSBoundParameters -DelegateId ([string]$delegateUser['id'])
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action $action -Target $target.Identity -Impact High)) { Complete-EX17Step 'Delegation' $target.Identity Cancelled -PassThru:$PassThru; return }
$backedUp=$false
foreach ($item in $changes) {
    if (-not $PSCmdlet.ShouldProcess($target.Identity,($Operation+' '+$item.Right+' for '+$delegateUser['userPrincipalName']))) { continue }
    if (-not $backedUp) {
        $null=Save-UMJson -Value @{Mailbox=$target.Identity;FullAccess=$permissions;SendAs=$sendAs;SendOnBehalf=@($target.Mailbox.GrantSendOnBehalfTo)} -Label 'Delegates-Before'
        $backedUp=$true
    }
    switch ($item.Right) {
        'FullAccess' {
            if ($Operation -eq 'Add') { $null=Add-MailboxPermission -Identity $target.Identity -User $delegate.PrimarySmtpAddress -AccessRights FullAccess -InheritanceType All -AutoMapping $true -Confirm:$false -ErrorAction Stop }
            else { $null=Remove-MailboxPermission -Identity $target.Identity -User $delegate.PrimarySmtpAddress -AccessRights FullAccess -InheritanceType All -Confirm:$false -ErrorAction Stop }
        }
        'SendAs' {
            if ($Operation -eq 'Add') { $null=Add-RecipientPermission -Identity $target.Identity -Trustee $delegate.PrimarySmtpAddress -AccessRights SendAs -Confirm:$false -ErrorAction Stop }
            else { $null=Remove-RecipientPermission -Identity $target.Identity -Trustee $delegate.PrimarySmtpAddress -AccessRights SendAs -Confirm:$false -ErrorAction Stop }
        }
        'SendOnBehalf' {
            $delta=if ($Operation -eq 'Add') { @{Add=$delegate.Identity} } else { @{Remove=$delegate.Identity} }
            Set-Mailbox -Identity $target.Identity -GrantSendOnBehalfTo $delta -Confirm:$false -ErrorAction Stop
        }
    }
    $present=Test-WFDelegateRight $target.Identity $delegate $item.Right
    if ($present -ne ($Operation -eq 'Add')) { throw ('Permission not yet verified: '+$item.Right+'. Review Exchange before retrying.') }
    Write-M365Log -Message ($action+' on '+$target.Identity+' verified: '+$item.Right) -Level Change
}
$status=if ($WhatIfPreference) {'Planned'} else {'Success'}
Complete-EX17Step 'Delegation' $target.Identity $status -Detail $action -PassThru:$PassThru
