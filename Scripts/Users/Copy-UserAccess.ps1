#Requires -Version 7.4
<#
.SYNOPSIS
Add selected supported direct group memberships from source to target.
.DESCRIPTION
Does NOT copy directory roles, PIM, application assignments, group ownership, mailbox
permissions, SharePoint direct permissions, or OneDrive access. Additive only.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$SourceUserPrincipalName,[string]$TargetUserPrincipalName,[string[]]$GroupIds,[string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt)
$ErrorActionPreference='Stop'
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'users.copy-useraccess' -TaskName 'Copy User Access (direct groups only)' -Scopes @('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
if (-not $SourceUserPrincipalName) { $SourceUserPrincipalName=([string](Read-Host 'Source UPN (blank cancels)')).Trim() }
if (-not $SourceUserPrincipalName) { return }
if (-not $TargetUserPrincipalName) { $TargetUserPrincipalName=([string](Read-Host 'Target UPN (blank cancels)')).Trim() }
if (-not $TargetUserPrincipalName) { return }
$source=Get-UMUser $SourceUserPrincipalName; $target=Get-UMUser $TargetUserPrincipalName
Assert-UMCloudMember -User $source -Tenant $tenant -AllowSelf
Assert-UMCloudMember -User $target -Tenant $tenant
if ($source['id'] -eq $target['id']) { throw 'Source and target must be different users.' }
$sourceGroups=@(Get-UMCollection ('/users/'+$source['id']+'/memberOf/microsoft.graph.group?$select=id'))
$targetGroups=@(Get-UMCollection ('/users/'+$target['id']+'/memberOf/microsoft.graph.group?$select=id'))
$existing=@($targetGroups | ForEach-Object { $_['id'] })
$plan=@(); $number=0
foreach ($entry in $sourceGroups) {
    $g=Get-UMGroup $entry['id']; $reason=Get-UMGroupReason $g
    if ($existing -contains $g['id']) { $reason='Already a direct member' }
    $number++
    $plan += [pscustomobject]@{Number=$number;Group=$g['displayName'];Id=$g['id'];Status=$(if ($reason) { $reason } else { 'Eligible' })}
}
$plan | Format-Table -AutoSize | Out-Host
Write-Host 'Scope: direct, static, cloud Microsoft 365/security group membership only. No roles, mailbox permissions or direct site permissions.' -ForegroundColor Yellow
$eligible=@($plan | Where-Object Status -eq 'Eligible')
if (-not $eligible.Count) { Write-Host 'No eligible missing memberships.'; return }
if (-not $PSBoundParameters.ContainsKey('GroupIds')) {
    $selection=([string](Read-Host 'Group numbers separated by commas, ALL for eligible groups, or Enter to cancel')).Trim()
    if (-not $selection) { return }
    if ($selection -ieq 'ALL') { $GroupIds=@($eligible.Id) }
    else {
        $numbers=@(ConvertTo-UMList $selection)
        foreach ($n in $numbers) { if ($n -notmatch '^\d+$' -or @($eligible | Where-Object Number -eq ([int]$n)).Count -ne 1) { throw "Not an eligible group number: $n" } }
        $GroupIds=@($eligible | Where-Object { [string]$_.Number -in $numbers } | ForEach-Object Id)
    }
}
$GroupIds=@($GroupIds | Select-Object -Unique)
foreach ($id in $GroupIds) { if ($id -notin @($eligible.Id)) { throw "Not an eligible source group: $id" } }
$selected=@($eligible | Where-Object Id -in $GroupIds)
if (-not $selected.Count) { return }
$selected | Format-Table -AutoSize | Out-Host
if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action ('Add selected memberships to '+$target['userPrincipalName']) -Target @($selected | ForEach-Object { $_.Group+' ['+$_.Id+']' }) -Impact High)) { return }
$results=@(); $backedUp=$false
foreach ($g in $selected) {
    if (-not $PSCmdlet.ShouldProcess($target['userPrincipalName'],('Add to '+$g.Group))) { continue }
    if (-not $backedUp) {
        $null=Save-UMJson -Value @{Source=$source['userPrincipalName'];Target=$target;TargetDirectGroups=$targetGroups;Selected=$selected} -Label 'CopyUserAccess-Before'
        $backedUp=$true
    }
    try {
        $fresh=Get-UMGroup $g.Id; $reason=Get-UMGroupReason $fresh
        if ($reason) { throw "Group eligibility changed: $reason" }
        $null=Invoke-UMGraph -Method POST -Path ('/groups/'+$g.Id+'/members/$ref') -Body @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$target['id'])}
        Write-M365Log -Message ('Added '+$target['userPrincipalName']+' to group '+$g.Id) -Level Change
        $results += [pscustomobject]@{Target=$g.Id;Group=$g.Group;Result='Success';Error=''}
    } catch { $results += [pscustomobject]@{Target=$g.Id;Group=$g.Group;Result='Failed';Error=$_.Exception.Message} }
}
if ($results.Count) { Write-UT19Results -Results $results -Label 'CopyUserAccess' }
