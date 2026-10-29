#Requires -Version 7.4
<#
.SYNOPSIS
Add selected eligible direct group memberships from one cloud user to another.
.DESCRIPTION
Additive only. Static cloud Microsoft 365/security groups. Excludes dynamic,
synced, role-assignable and Exchange-managed groups. Does not copy ownership,
directory roles, PIM assignments, mailbox or direct SharePoint permissions.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$SourceUserPrincipalName,[string]$TargetUserPrincipalName,
      [string[]]$GroupIds,[switch]$AllEligible,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.CopyGroupMemberships.Helpers.ps1')
$scopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'groups.copy-groupmemberships' -TaskName 'Copy selected direct group memberships' -Scopes $scopes
if ([string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'This task version supports the global Graph endpoint only.' }
if ($AllEligible -and $PSBoundParameters.ContainsKey('GroupIds')) { throw 'Choose GroupIds or AllEligible, not both.' }
if (-not $SourceUserPrincipalName) {
    if ($NoInteractive) { throw 'SourceUserPrincipalName is required.' }
    $SourceUserPrincipalName=([string](Read-Host 'Source user UPN (Enter cancels)')).Trim()
}
if (-not $SourceUserPrincipalName) { return }
if (-not $TargetUserPrincipalName) {
    if ($NoInteractive) { throw 'TargetUserPrincipalName is required.' }
    $TargetUserPrincipalName=([string](Read-Host 'Target user UPN (Enter cancels)')).Trim()
}
if (-not $TargetUserPrincipalName) { return }
$source=Get-UMUser $SourceUserPrincipalName
$target=Get-UMUser $TargetUserPrincipalName
Assert-UMCloudMember -User $source -Tenant $tenant -AllowSelf
Assert-UMCloudMember -User $target -Tenant $tenant
if ([string]$source['id'] -ieq [string]$target['id']) { throw 'Source and target must be different users.' }
$sourceIds=@(Get-CGDirectGroups -UserId $source['id'])
$targetIds=@(Get-CGDirectGroups -UserId $target['id'])
$groups=@(foreach ($id in $sourceIds) { Get-UMGroup $id })
$groups=@($groups | Sort-Object { [string]$_['displayName'] },{ [string]$_['id'] })
$plan=@(); $number=0
foreach ($group in $groups) {
    $reason=Get-UMGroupReason $group
    if ([string]$group['id'] -in $targetIds) { $reason='Already a direct member' }
    $number++
    $plan+=[pscustomobject]@{Number=$number;Group=[string]$group['displayName'];Id=[string]$group['id'];Status=$(if ($reason) {$reason} else {'Eligible'})}
}
Write-Host ('Source: '+$source['displayName']+' <'+$source['userPrincipalName']+'>') -ForegroundColor Cyan
Write-Host ('Target: '+$target['displayName']+' <'+$target['userPrincipalName']+'>') -ForegroundColor Cyan
if ($plan.Count) { $plan | Format-Table Number,Group,Status -AutoSize -Wrap | Out-Host }
Write-Host 'Adds direct membership only. No ownership, roles, PIM or mailbox/site permissions are copied.' -ForegroundColor Yellow
Write-Host 'Group membership can grant application/data access and group-based licenses.' -ForegroundColor Yellow
$eligible=@($plan | Where-Object Status -eq 'Eligible')
if (-not $eligible.Count) { Write-Host 'No eligible missing direct memberships.'; return }
if ($AllEligible) { $GroupIds=@($eligible.Id) }
elseif (-not $PSBoundParameters.ContainsKey('GroupIds')) {
    if ($NoInteractive) { throw 'Specify GroupIds or AllEligible when using NoInteractive.' }
    while ($true) {
        $answer=([string](Read-Host 'Group numbers separated by commas; ALL selects eligible groups; Enter cancels')).Trim()
        if (-not $answer) { return }
        try { $GroupIds=@(Select-CGPlanIds -Plan $plan -Selection $answer); break }
        catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}
$normalized=@(foreach ($value in @($GroupIds)) {
    $id=[guid]::Empty
    if (-not [guid]::TryParse($value,[ref]$id)) { throw ('Invalid selected group ID: '+$value) }
    $id.ToString('D')
})
$GroupIds=@($normalized | Select-Object -Unique)
foreach ($id in $GroupIds) { if ($id -notin @($eligible.Id)) { throw ('Selected group is not an eligible missing source membership: '+$id) } }
$selected=@($eligible | Where-Object Id -in $GroupIds)
if (-not $selected.Count) { return }
Write-Host ''
Write-Host 'Planned additions:' -ForegroundColor Cyan
$selected | Select-Object Group,Id | Format-Table -AutoSize -Wrap | Out-Host
if (-not $WhatIfPreference) {
    if (-not (Confirm-M365Action -Action ('Add selected direct group memberships to '+$target['userPrincipalName']) -Target @($selected | ForEach-Object { $_.Group+' ['+$_.Id+']' }) -Impact High)) { return }
    $ConfirmPreference='None'
}
$results=@(); $backedUp=$false; $stopped=$false
foreach ($entry in $selected) {
    if ($stopped) { $results+=[pscustomobject]@{Group=$entry.Group;GroupId=$entry.Id;Target=$target['userPrincipalName'];Result='Not run';Detail='Earlier addition failed or could not be verified'}; continue }
    if (-not $PSCmdlet.ShouldProcess($target['userPrincipalName'],('Add direct membership: '+$entry.Group))) {
        $results+=[pscustomobject]@{Group=$entry.Group;GroupId=$entry.Id;Target=$target['userPrincipalName'];Result='Planned';Detail='No membership write requested'}
        continue
    }
    $postStarted=$false
    try {
        $null=Assert-M365Connection -Service Graph -GraphScopes $scopes -TaskName 'Verify copy membership access' -TaskId 'groups.copy-groupmemberships' -NoPrompt
        $freshSource=Get-UMUser $source['id']; $freshTarget=Get-UMUser $target['id']
        Assert-UMCloudMember -User $freshSource -Tenant $tenant -AllowSelf
        Assert-UMCloudMember -User $freshTarget -Tenant $tenant
        if ([string]$freshSource['id'] -ine [string]$source['id'] -or [string]$freshTarget['id'] -ine [string]$target['id'] -or [string]$freshSource['userPrincipalName'] -ine [string]$source['userPrincipalName'] -or [string]$freshTarget['userPrincipalName'] -ine [string]$target['userPrincipalName']) { throw 'User identity changed; rebuild plan.' }
        $freshGroup=Get-UMGroup $entry.Id
        $reason=Get-UMGroupReason $freshGroup
        if ($reason) { throw ('Group eligibility changed: '+$reason) }
        if ([string]$freshGroup['displayName'] -cne $entry.Group) { throw 'Selected group name changed; rebuild plan.' }
        if ($entry.Id -notin @(Get-CGDirectGroups -UserId $source['id'])) { throw 'Source no longer has this direct membership; rebuild plan.' }
        if ($entry.Id -in @(Get-CGDirectGroups -UserId $target['id'])) {
            $results+=[pscustomobject]@{Group=$entry.Group;GroupId=$entry.Id;Target=$target['userPrincipalName'];Result='AlreadyMember';Detail='Direct membership appeared after preview; no write sent'}
            continue
        }
        if (-not $backedUp) {
            $null=Save-UMJson -Value @{SourceId=$source['id'];SourceUPN=$source['userPrincipalName'];TargetId=$target['id'];TargetUPN=$target['userPrincipalName'];TargetDirectGroups=$targetIds;Selected=$selected} -Label 'CopyGroupMemberships-Before'
            $backedUp=$true
        }
        $postStarted=$true
        $null=Invoke-UMGraph -Method POST -Path ('/groups/'+$entry.Id+'/members/$ref') -Body @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$target['id'])}
        $verified=$false
        for ($attempt=0;$attempt -lt 4;$attempt++) {
            if ($entry.Id -in @(Get-CGDirectGroups -UserId $target['id'])) { $verified=$true; break }
            if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
        }
        if (-not $verified) { throw 'Addition returned but direct membership is not yet visible. Inspect before retrying.' }
        $results+=[pscustomobject]@{Group=$entry.Group;GroupId=$entry.Id;Target=$target['userPrincipalName'];Result='Success';Detail='Direct membership verified'}
        Write-M365Log -Message ('Verified direct membership addition to group '+$entry.Id) -Level Change
    } catch {
        $state=if ($postStarted) {'Unverified'} else {'Failed'}
        $detail=$_.Exception.Message
        if ($postStarted) { $detail+=' No task-level retry; inspect membership before rerunning.' }
        $results+=[pscustomobject]@{Group=$entry.Group;GroupId=$entry.Id;Target=$target['userPrincipalName'];Result=$state;Detail=$detail}
        Write-M365Log -Message ('Copy membership stopped: '+$detail) -Level Error
        $stopped=$true
    }
}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.CopyGroupMemberships.Output.ps1')
$exportResult=Show-ToolkitCopyGroupMembershipResult -Results @($results) -TenantId $tenant.TenantId -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
Write-Host ('Result export: '+$exportResult.Status)
if ($PassThru) { $results }
