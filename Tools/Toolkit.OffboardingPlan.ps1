# Definitions only. Phase 6A does not execute or approve tenant changes.
function New-WFOffboardingFoundationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$User,
        [Parameter(Mandatory)][object]$Tenant,
        [Parameter(Mandatory)][string[]]$Actions
    )
    if (-not $Tenant.TenantId) { throw 'A verified tenant is required for planning.' }
    if (-not $User['id'] -or -not $User['userPrincipalName']) { throw 'Incomplete target identity.' }
    Assert-UMCloudMember -User $User -Tenant $Tenant
    $selected=@($Actions | Select-Object -Unique)
    $rows=@()
    if ('BlockAccess' -in $selected) {
        $state=if ($User['accountEnabled'] -eq $true) {'Allowed'} elseif ($User['accountEnabled'] -eq $false) {'Blocked'} else {'Unknown'}
        $rows+=[pscustomobject]@{Action='BlockAccess';Target=[string]$User['userPrincipalName'];Current=$state;Planned='Block sign-in and request session revocation, including when already blocked';Prerequisite='Child task revalidates target and verifies block/revocation result'}
    }
    if ('ConvertShared' -in $selected) {
        $null=Assert-M365TaskAccess -AccessMode Changes -TaskId 'exchange.convert-shared'
        $null=Assert-M365Connection -Service @('Graph','ExchangeOnline') -GraphScopes @('User.Read.All') -TaskName 'Read offboarding mailbox preflight' -TaskId 'exchange.convert-shared'
        $target=Get-WFMailboxTarget -Identity ([string]$User['id']) -Tenant $Tenant
        if ([string]$target.User['id'] -ine [string]$User['id']) { throw 'Preflight target identity changed.' }
        # Match the existing child task: even an already-shared mailbox requires blocked sign-in.
        if ($target.User['accountEnabled'] -ne $false -and 'BlockAccess' -notin $selected) {
            throw 'Shared conversion requires verified blocked sign-in or BlockAccess in this plan. No workflow steps have run.'
        }
        $alreadyShared=([string]$target.Mailbox.RecipientTypeDetails -eq 'SharedMailbox')
        if (-not $alreadyShared -and -not @($target.User['assignedLicenses']).Count) {
            throw 'The user must still be licensed before conversion. No workflow steps have run.'
        }
        $planned=if ($alreadyShared) {'Already shared; child task rechecks before reporting no conversion needed'} else {'Convert mailbox to shared; retain user account and all licenses'}
        $dependency=if ('BlockAccess' -in $selected) {'BlockAccess must succeed and be verified first; conversion task rechecks'} else {'Sign-in currently blocked; conversion task rechecks'}
        $rows+=[pscustomobject]@{Action='ConvertShared';Target=[string]$target.Identity;Current=[string]$target.Mailbox.RecipientTypeDetails;Planned=$planned;Prerequisite=$dependency}
    }
    [pscustomobject]@{
        SchemaVersion=1;Phase='6A';ApprovalGranted=$false
        TenantId=[string]$Tenant.TenantId;UserId=[string]$User['id'];UserPrincipalName=[string]$User['userPrincipalName']
        Steps=@($rows);DeferredActions=@($selected | Where-Object { $_ -notin @('BlockAccess','ConvertShared') })
    }
}
function Show-WFOffboardingFoundationPlan {
    param([Parameter(Mandatory)][object]$Plan)
    Write-Host 'OFFBOARDING PREFLIGHT - PHASE 6A (not an execution approval)' -ForegroundColor Cyan
    Write-Host ('Tenant: '+$Plan.TenantId+' | User: '+$Plan.UserPrincipalName+' | ID: '+$Plan.UserId)
    $Plan.Steps | Format-List Action,Target,Current,Planned,Prerequisite | Out-Host
    if ($Plan.DeferredActions.Count) {
        Write-Host ('Not preflighted by 6A: '+($Plan.DeferredActions -join ', ')+'. These tasks still collect their settings and confirm later.') -ForegroundColor Yellow
    }
    Write-Host 'This preliminary snapshot does not authorize changes. A final consolidated plan follows; execution-time checks remain.' -ForegroundColor Yellow
}
