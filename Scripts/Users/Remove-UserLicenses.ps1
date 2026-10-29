#Requires -Version 7.4
<# .SYNOPSIS
Remove selected direct license assignments. Never changes licensing groups.
.DESCRIPTION
Requires a cloud member whose sign-in is Blocked, preservation review, and conservative Exchange checks.
Preservation review is an administrator attestation, NOT automated OneDrive/archive validation.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string[]]$LicenseSkuIds,[string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt,[switch]$PassThru,[switch]$PlanOnly,[switch]$PlannedBlockAccess,[switch]$PlannedSharedConversion,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-WFTask -TaskId 'users.remove-licenses' -TaskName 'Remove selected direct user licenses' -Scopes @('User.Read.All','LicenseAssignment.ReadWrite.All')
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'User UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-UT19Step 'License removal' '' Cancelled -PassThru:$PassThru; return }
$user=Get-UMUser $UserPrincipalName
Assert-UMCloudMember -User $user -Tenant $tenant
if ($user['accountEnabled'] -ne $false -and -not $WhatIfPreference -and -not ($PlanOnly -and $PlannedBlockAccess)) { throw "Sign-in must already be Blocked before removing offboarding licenses. Run 'Block sign-in and revoke sessions' first." }
$statePath='/users/'+$user['id']+'?$select=id,assignedLicenses,licenseAssignmentStates'
$state=Invoke-UMGraph -Path $statePath
$rows=@(Get-WFLicenseAssignmentRows -User $state -Skus @(Get-UMCollection '/subscribedSkus'))
$rows | Select-Object Number,Product,Assignment,Eligible | Format-Table -AutoSize | Out-Host
if (-not $rows.Count -and $PlanOnly) { [pscustomobject]@{PlanKind='Offboarding6C';Settings=@{};NoOp=$true;Summary='No assigned licenses; removal excluded'}; return }
if (-not $rows.Count) { Complete-UT19Step 'License removal' $user['userPrincipalName'] Success -Detail 'No assigned licenses' -PassThru:$PassThru; return }
if ($WorkflowApproval -and (-not $PSBoundParameters.ContainsKey('LicenseSkuIds') -or -not @($LicenseSkuIds).Count)) { throw 'Approved license selection missing. Rebuild the plan.' }
if (-not $PSBoundParameters.ContainsKey('LicenseSkuIds')) {
    $LicenseSkuIds=@(Read-WFSelection -Rows $rows -AllowAll -Prompt 'License numbers, ALL for direct assignments, or Enter to cancel' | ForEach-Object Id)
}
$selected=@($rows | Where-Object Id -in $LicenseSkuIds)
foreach ($id in $LicenseSkuIds) { if ($id -notin @($rows | Where-Object Eligible | ForEach-Object Id)) { throw 'A selected license is unknown or has no direct assignment. No group memberships will be changed.' } }
if (-not $selected.Count) { Complete-UT19Step 'License removal' $user['userPrincipalName'] Cancelled -PassThru:$PassThru; return }
# Inspect Exchange-related plans, excluding Exchange Foundation.
# FLOW_FREE includes EXCHANGE_S_FOUNDATION; that alone must not
# trigger mailbox-preservation checks.
$selectedExchangePlans = @(
    $selected |
        ForEach-Object {
            $_.Sku['servicePlans']
        } |
        Where-Object {
            $planName = [string]$_['servicePlanName']

            $planName -match 'EXCHANGE' -and
            $planName -ine 'EXCHANGE_S_FOUNDATION'
        }
)

$exchangePlan = $selectedExchangePlans.Count -gt 0
if ($PlanOnly) {
    $preservation='No selected Exchange service plan detected; independent preservation review still required'
    if ($exchangePlan) {
        $null=Assert-M365Connection -Service ExchangeOnline -GraphScopes @('User.Read.All','LicenseAssignment.ReadWrite.All') -TaskName 'Preflight mailbox preservation for license plan'
        $mailTarget=Get-WFMailboxTarget $user['id'] $tenant
        if ([string]$mailTarget.Mailbox.RecipientTypeDetails -ne 'SharedMailbox') {
            if (-not $PlannedSharedConversion) { throw 'Exchange-bearing removal requires an already-shared mailbox or planned conversion. No workflow steps executed.' }
            $preservation='PENDING: shared conversion must succeed, then all existing Exchange preservation checks must pass at execution. Planning has NOT cleared license removal.'
        } else {
            Assert-WFExchangeLicenseRemoval -Target $mailTarget
            $preservation='Existing Exchange preservation checks passed at planning time; all are required again at execution. This is not proof of all data preservation.'
        }
    }
    $selected | Select-Object Product,Id,Assignment,Inherited | Format-List | Out-Host
    Write-Host $preservation -ForegroundColor Yellow
    Write-Host 'Only direct assignments will be removed. Group-inherited licenses remain. Review retention, OneDrive, archives, compliance and licensing independently; this tool does not prove preservation.' -ForegroundColor Yellow
    $attestation=([string](Read-Host 'Type REVIEWED to attest to independent preservation/licensing review; anything else cancels the entire workflow')).Trim()
    if ($attestation -cne 'REVIEWED') { return }
    $summary=[pscustomobject]@{
        Licenses=@($selected | Select-Object Product,Id,Assignment,Inherited)
        SignInRequirement=$(if ($user['accountEnabled'] -eq $false) {'Currently blocked; checked again at execution'} else {'PENDING: BlockAccess must succeed and be verified before removal'})
        Preservation=$preservation
        AdministratorReview='Acknowledged during planning; execution confirmation still required'
    }
    [pscustomobject]@{PlanKind='Offboarding6C';Settings=@{LicenseSkuIds=@($selected | ForEach-Object Id)};NoOp=$false;Summary=($summary | ConvertTo-Json -Depth 8)}
    return
}
if ($exchangePlan -and -not $WhatIfPreference) {
    $null=Assert-M365Connection -Service ExchangeOnline -GraphScopes @('User.Read.All','LicenseAssignment.ReadWrite.All') -TaskName 'Check mailbox preservation before license removal'
    Assert-WFExchangeLicenseRemoval -Target (Get-WFMailboxTarget $user['id'] $tenant)
}
Write-Host 'Removing licenses can disable services and affect data retention, OneDrive, archives and compliance features. This release does NOT automatically prove all data is preserved. Review preservation and licensing obligations first. Group-inherited licenses remain.' -ForegroundColor DarkYellow
$selected | Select-Object Product,Assignment | Format-Table | Out-Host
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $user -Action 'RemoveLicenses' -Bound $PSBoundParameters
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action 'Remove listed DIRECT license assignments; I have independently reviewed data preservation, retention, and licensing requirements' -Target @($selected | ForEach-Object { $user['userPrincipalName']+' : '+$_.Product }) -Impact High)) { Complete-UT19Step 'License removal' $user['userPrincipalName'] Cancelled -PassThru:$PassThru; return }
$results=@(); $backedUp=$false
foreach ($item in $selected) {
    if (-not $PSCmdlet.ShouldProcess($user['userPrincipalName'],('Remove direct license '+$item.Product))) { continue }
    if (-not $backedUp) { $null=Save-UMJson -Value $state -Label 'LicenseRemoval-Before'; $backedUp=$true }
    # Re-read assignment sources to avoid acting on an outdated plan.
    $current=Invoke-UMGraph -Path $statePath
    $direct=@($current['licenseAssignmentStates'] | Where-Object { [string]$_['skuId'] -ieq $item.Id -and -not $_['assignedByGroup'] })
    if (-not $direct.Count) { throw 'Assignment changed since preview; stop and review before retrying.' }
    $null=Invoke-UMGraph -Method POST -Path ('/users/'+$user['id']+'/assignLicense') -Body @{addLicenses=@();removeLicenses=@($item.Id)}
    $verified=$false; $after=$null
    for ($attempt=0; $attempt -lt 4; $attempt++) {
        $after=Invoke-UMGraph -Path $statePath
        $remainingDirect=@($after['licenseAssignmentStates'] | Where-Object { [string]$_['skuId'] -ieq $item.Id -and -not $_['assignedByGroup'] })
        if (-not $remainingDirect.Count) { $verified=$true; break }
        Start-Sleep -Seconds 3
    }
    $effective=@($after['assignedLicenses'] | Where-Object { [string]$_['skuId'] -ieq $item.Id }).Count -gt 0
    $result=if ($verified) { 'Success' } else { 'Unverified' }
    $detail=if (-not $verified) {'Removal requested; direct assignment still visible'} elseif ($effective) {'Direct assignment removed; effective license remains (for example through a group)'} else {'Direct assignment removed; license no longer present'}
    $results+=[pscustomobject]@{Product=$item.Product;SkuId=$item.Id;Result=$result;Detail=$detail}
    Write-M365Log -Message ($user['userPrincipalName']+' : '+$item.Product+' : '+$detail) -Level Info
    if (-not $verified) { Write-UT19Results -Results $results -Label 'LicenseRemoval'; throw 'License removal not yet verified. Further removals stopped.' }
}
if ($results.Count) { Write-UT19Results -Results $results -Label 'LicenseRemoval' }
$status=if ($WhatIfPreference) {'Planned'} else {'Success'}
Complete-UT19Step 'License removal' $user['userPrincipalName'] $status -PassThru:$PassThru
