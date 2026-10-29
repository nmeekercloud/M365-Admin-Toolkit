#Requires -Version 7.4
<#
.SYNOPSIS
CSV-driven profile updates, enabling, or disabling of existing cloud member accounts.
.DESCRIPTION
Columns: Action,UserPrincipalName,DisplayName,Department,JobTitle,OfficeLocation.
Action is Update, Enable or Disable. Blank profile cells mean leave unchanged, not clear.
Disable includes revocation. Entire CSV preflight must pass before any writes.
No bulk create/delete/license removal or password reset in this testing release.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$CsvPath,[ValidateRange(1,500)][int]$MaxRows=100,[string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt,[switch]$NoInteractive)
$ErrorActionPreference='Stop'
if ($NoInteractive) { $NoOutputPrompt=$true }
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
$toolkitRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $toolkitRoot 'Tools/Toolkit.BulkCsvTemplates.ps1')
$CsvPath=Read-ToolkitBulkCsvPath -ToolkitRoot $toolkitRoot -Kind Users -CsvPath $CsvPath -NoInteractive:$NoInteractive
if (-not $CsvPath) { return }
$rows=@(Import-Csv -LiteralPath $CsvPath)
if (-not $rows.Count -or $rows.Count -gt $MaxRows) { throw "CSV must contain 1 through $MaxRows rows." }
$allowed=@('Action','UserPrincipalName','DisplayName','Department','JobTitle','OfficeLocation')
$columns=@($rows[0].PSObject.Properties.Name)
foreach ($key in @('Action','UserPrincipalName')) { if ($key -notin $columns) { throw "CSV column required: $key" } }
foreach ($key in $columns) { if ($key -notin $allowed) { throw "Unsupported CSV column: $key" } }
$seen=@{}
foreach ($row in $rows) {
    $upn=([string]$row.UserPrincipalName).Trim()
    if ($upn -notmatch '^[^\s@]+@[^\s@]+$') { throw "Invalid UPN: $upn" }
    if ($seen.ContainsKey($upn)) { throw "Duplicate user in CSV: $upn" }; $seen[$upn]=$true
    $row.UserPrincipalName=$upn
    $row.Action=([string]$row.Action).Trim()
    if ($row.Action -notin @('Update','Enable','Disable')) { throw "Unsupported action: $($row.Action)" }
    $profile=New-UMProfileBody $row
    if ($row.Action -eq 'Update' -and $profile.Count -eq 0) { throw "No nonblank update fields for $upn" }
    if ($row.Action -ne 'Update' -and $profile.Count) { throw "Profile fields must be blank for Enable/Disable: $upn" }
}
$scopes=@('User.Read.All')
if (@($rows | Where-Object Action -eq 'Update').Count) { $scopes+='User.ReadWrite.All' }
if (@($rows | Where-Object Action -in @('Enable','Disable')).Count) { $scopes+='User.EnableDisableAccount.All' }
if (@($rows | Where-Object Action -eq 'Disable').Count) { $scopes+='User.RevokeSessions.All' }
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'users.invoke-bulkusermanagement' -TaskName 'Bulk User Management (validated CSV actions)' -Scopes $scopes
$plan=@(); $failures=@()
foreach ($row in $rows) {
    try {
        $user=Get-UMUser $row.UserPrincipalName
        Assert-UMCloudMember -User $user -Tenant $tenant
        $body=New-UMProfileBody $row
        if ($row.Action -eq 'Enable') { $body=@{accountEnabled=$true} }
        if ($row.Action -eq 'Disable') { $body=@{accountEnabled=$false} }
        $plan += [pscustomobject]@{User=$user;Action=$row.Action;Body=$body}
    } catch { $failures += [pscustomobject]@{User=$row.UserPrincipalName;Error=$_.Exception.Message} }
}
if ($failures.Count) { $failures | Format-Table -Wrap | Out-Host; throw 'CSV preflight failed. No tenant data was changed.' }
$plan | ForEach-Object { [pscustomobject]@{User=$_.User['userPrincipalName'];Action=$_.Action;Changes=($_.Body | ConvertTo-Json -Compress)} } | Format-Table -Wrap | Out-Host
Write-Host 'Enable allows sign-in again. Disable blocks sign-in and requests revocation. No automatic rollback; review partial failures.' -ForegroundColor Yellow
if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action 'Apply all previewed CSV user changes' -Target @($plan | ForEach-Object { $_.User['userPrincipalName']+' : '+$_.Action }) -Impact High)) { return }
$results=@(); $backedUp=$false
foreach ($item in $plan) {
    $upn=$item.User['userPrincipalName']
    if (-not $PSCmdlet.ShouldProcess($upn,($item.Action+' from CSV'))) { continue }
    if (-not $backedUp) { $null=Save-UMJson -Value $plan -Label 'BulkUsers-Before'; $backedUp=$true }
    try {
        $null=Invoke-UMGraph -Method PATCH -Path ('/users/'+$item.User['id']) -Body $item.Body
        Write-M365Log -Message ($item.Action+': '+$upn) -Level Change
        $results += [pscustomobject]@{Target=$upn;Action=$item.Action;Result='Success';Error=''}
    } catch {
        $results += [pscustomobject]@{Target=$upn;Action=$item.Action;Result='Failed';Error=$_.Exception.Message}
        continue
    }
    if ($item.Action -eq 'Disable') {
        try {
            $response=Invoke-UMGraph -Method POST -Path ('/users/'+$item.User['id']+'/revokeSignInSessions') -Body @{}
            if ($response['value'] -ne $true) { throw 'Graph did not confirm the revocation request.' }
            $results += [pscustomobject]@{Target=$upn;Action='Revoke sessions';Result='Success';Error=''}
        } catch { $results += [pscustomobject]@{Target=$upn;Action='Revoke sessions';Result='Failed';Error=$_.Exception.Message} }
    }
}
if ($results.Count) { Write-UT19Results -Results $results -Label 'BulkUsers' }
