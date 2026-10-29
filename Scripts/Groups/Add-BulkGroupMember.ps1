#Requires -Version 7.4
<#
.SYNOPSIS
Bulk add cloud users to supported static groups from a strict two-column CSV.
.DESCRIPTION
Whole-batch preflight before writes; additive only. One approval, backup,
per-pair revalidation, verification, fail-stop and results CSV. No removals.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$CsvPath,[ValidateRange(1,10000)][int]$MaxRows=1000,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.BulkGroupMembers.Helpers.ps1')
$toolkitRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $toolkitRoot 'Tools/Toolkit.BulkCsvTemplates.ps1')
$CsvPath=Read-ToolkitBulkCsvPath -ToolkitRoot $toolkitRoot -Kind GroupMembers -CsvPath $CsvPath -NoInteractive:$NoInteractive
if (-not $CsvPath) { return }
# Parse all records first, before sign-in or tenant writes. Returned objects are the execution snapshot.
$inputRows=@(Import-BGMCsv -LiteralPath $CsvPath -MaxRows $MaxRows)
$scopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'groups.add-bulkgroupmember' -TaskName 'Bulk add group members from CSV' -Scopes $scopes
if ([string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Only the global Graph endpoint is supported in this task version.' }
$groupCache=@{}; $userCache=@{}; $membershipCache=@{}
$pairs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan=@()
foreach ($inputRow in $inputRows) {
    $row=[pscustomobject]@{Record=$inputRow.Record;Group='';GroupId=$inputRow.GroupId;UserPrincipalName=$inputRow.UserPrincipalName;UserId='';Status='Invalid';Detail=''}
    try {
        if (-not $groupCache.ContainsKey($inputRow.GroupId)) { $groupCache[$inputRow.GroupId]=Get-UMGroup $inputRow.GroupId }
        $group=$groupCache[$inputRow.GroupId]
        if ([string]$group['id'] -ine $inputRow.GroupId) { throw 'Group resolution ID mismatch.' }
        $row.Group=[string]$group['displayName']
        if (-not $userCache.ContainsKey($inputRow.UserPrincipalName)) { $userCache[$inputRow.UserPrincipalName]=Get-UMUser $inputRow.UserPrincipalName }
        $user=$userCache[$inputRow.UserPrincipalName]
        $userId=[guid]::Empty
        if (-not [guid]::TryParse([string]$user['id'],[ref]$userId)) { throw 'User resolution missing object ID.' }
        if ([string]$user['userPrincipalName'] -ine $inputRow.UserPrincipalName) { throw 'CSV must use the resolved canonical UserPrincipalName, not an alias.' }
        Assert-UMCloudMember -User $user -Tenant $tenant
        $row.UserId=$userId.ToString('D'); $row.UserPrincipalName=[string]$user['userPrincipalName']
        $reason=Get-UMGroupReason $group
        if ($reason) { $row.Status='Unsupported'; $row.Detail=$reason }
        elseif (-not $pairs.Add(($row.GroupId+'|'+$row.UserId))) { $row.Status='Duplicate'; $row.Detail='Resolved group/user pair appears earlier in CSV' }
        else {
            if (-not $membershipCache.ContainsKey($row.UserId)) { $membershipCache[$row.UserId]=@(Get-BGMDirectGroups -UserId $row.UserId) }
            if ($row.GroupId -in $membershipCache[$row.UserId]) { $row.Status='AlreadyMember'; $row.Detail='Already a direct member' }
            else { $row.Status='Eligible'; $row.Detail='Missing supported direct membership' }
        }
    } catch { $row.Status='Invalid'; $row.Detail=$_.Exception.Message }
    $plan+=,$row
}
Write-Host ('CSV records: '+$plan.Count+' | Tenant: '+$tenant.TenantId) -ForegroundColor Cyan
$plan | Format-Table Record,Group,UserPrincipalName,Status,Detail -AutoSize -Wrap | Out-Host
if (@($plan | Where-Object Status -eq 'Invalid').Count) {
    Write-Host 'Batch blocked: fix all Invalid records before rerunning. No membership writes were sent.' -ForegroundColor Red
    if ($PassThru) { $plan }
    throw 'Bulk membership preflight failed. No membership writes were sent.'
}
$eligible=@($plan | Where-Object Status -eq 'Eligible')
if (-not $eligible.Count) { Write-Host 'No eligible missing memberships.'; if ($PassThru) { $plan }; return }
Write-Host 'Only Eligible rows will be added. Unsupported, Duplicate and AlreadyMember rows are skipped.' -ForegroundColor Yellow
Write-Host 'Membership may grant data/application access and group licenses. No removals, ownership or role assignments.' -ForegroundColor Yellow
if (-not $WhatIfPreference) {
    $targets=@($eligible | ForEach-Object { $_.UserPrincipalName+' ['+$_.UserId+'] -> '+$_.Group+' ['+$_.GroupId+']' })
    if (-not (Confirm-M365Action -Action 'Add the displayed eligible CSV membership pairs' -Target $targets -Impact High)) { return }
    $ConfirmPreference='None'
}
$results=@(); $stopped=$false; $backedUp=$false
foreach ($row in $plan) {
    $result=[pscustomobject]@{Record=$row.Record;Group=$row.Group;GroupId=$row.GroupId;UserPrincipalName=$row.UserPrincipalName;UserId=$row.UserId;Result=$row.Status;Detail=$row.Detail}
    if ($row.Status -ne 'Eligible') { $results+=,$result; continue }
    if ($stopped) { $result.Result='NotRun'; $result.Detail='Earlier failure/uncertain addition stopped the batch'; $results+=,$result; continue }
    if (-not $PSCmdlet.ShouldProcess(($row.UserPrincipalName+' -> '+$row.Group),'Add direct group membership')) {
        $result.Result='Planned'; $result.Detail='No write requested'; $results+=,$result; continue
    }
    $postStarted=$false
    try {
        $null=Assert-M365Connection -Service Graph -GraphScopes $scopes -TaskId 'groups.add-bulkgroupmember' -TaskName 'Verify bulk membership access' -NoPrompt
        $freshGroup=Get-UMGroup $row.GroupId
        $reason=Get-UMGroupReason $freshGroup
        if ($reason) { throw ('Group eligibility changed: '+$reason) }
        if ([string]$freshGroup['id'] -ine $row.GroupId -or [string]$freshGroup['displayName'] -cne $row.Group) { throw 'Group identity/name changed; rebuild plan.' }
        $freshUser=Get-UMUser $row.UserId
        Assert-UMCloudMember -User $freshUser -Tenant $tenant
        if ([string]$freshUser['id'] -ine $row.UserId -or [string]$freshUser['userPrincipalName'] -ine $row.UserPrincipalName) { throw 'User identity changed; rebuild plan.' }
        if ($row.GroupId -in @(Get-BGMDirectGroups -UserId $row.UserId)) {
            $result.Result='AlreadyMember'; $result.Detail='Membership appeared after preview; no write sent'; $results+=,$result; continue
        }
        if (-not $backedUp) {
            $null=Save-UMJson -Value @{TenantId=$tenant.TenantId;Plan=$plan;OriginalDirectGroupsByUser=$membershipCache} -Label 'BulkGroupMembers-Before'
            $backedUp=$true
        }
        $postStarted=$true
        $null=Invoke-UMGraph -Method POST -Path ('/groups/'+$row.GroupId+'/members/$ref') -Body @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$row.UserId)}
        $verified=$false
        for ($attempt=0;$attempt -lt 4;$attempt++) {
            if ($row.GroupId -in @(Get-BGMDirectGroups -UserId $row.UserId)) { $verified=$true; break }
            if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
        }
        if (-not $verified) { throw 'Addition returned but direct membership is not yet visible. Inspect before rerunning.' }
        $result.Result='Success'; $result.Detail='Direct membership verified'
        Write-M365Log -Message ('Verified bulk membership addition: user '+$row.UserId+' to group '+$row.GroupId) -Level Change
    } catch {
        $result.Result=if ($postStarted) {'Unverified'} else {'Failed'}
        $result.Detail=$_.Exception.Message
        if ($postStarted) { $result.Detail+=' No task-level POST retry; inspect actual membership.' }
        $stopped=$true
        Write-M365Log -Message ('Bulk membership stopped: '+$result.Detail) -Level Error
    }
    $results+=,$result
}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.BulkGroupMembers.Output.ps1')
$exportResult=Show-ToolkitBulkGroupMemberResult -Results @($results) -TenantId $tenant.TenantId -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
Write-Host ('Result export: '+$exportResult.Status)
if ($PassThru) { $results }
