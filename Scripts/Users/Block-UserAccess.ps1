#Requires -Version 7.4
<# .SYNOPSIS
Block sign-in and revoke sessions for a cloud member. No other offboarding changes.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt,[switch]$PassThru,[object]$WorkflowApproval)
$ErrorActionPreference='Stop'
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'users.block-access' -TaskName 'Block sign-in and revoke sessions' -Scopes @('User.Read.All','User.EnableDisableAccount.All','User.RevokeSessions.All')
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'User UPN (blank cancels)')).Trim() }
if (-not $UserPrincipalName) { Complete-UT19Step 'Block sign-in and revoke sessions' '' Cancelled -PassThru:$PassThru; return }
$user=Get-UMUser $UserPrincipalName; Assert-UMCloudMember -User $user -Tenant $tenant
$user | Select-Object @{n='UPN';e={$_['userPrincipalName']}} | Format-List | Out-Host
$signInStatus=if ($user['accountEnabled'] -eq $true) { 'Allowed' } elseif ($user['accountEnabled'] -eq $false) { 'Blocked' } else { 'Unknown' }
Write-Host ('Current sign-in status: '+$signInStatus) -ForegroundColor DarkGray
Write-Host 'Blocked describes the current account state. This action also requests session revocation, even when sign-in is already blocked.' -ForegroundColor DarkYellow
$workflowApproved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $user -Action 'BlockAccess' -Bound $PSBoundParameters
if ($workflowApproved) { $ConfirmPreference='None' }
if (-not $WhatIfPreference -and -not $workflowApproved -and -not (Confirm-M365Action -Action 'Block sign-in and revoke sessions' -Target $user['userPrincipalName'] -Impact High)) { Complete-UT19Step 'Block sign-in and revoke sessions' $user['userPrincipalName'] Cancelled -PassThru:$PassThru; return }
if (-not $PSCmdlet.ShouldProcess($user['userPrincipalName'],'Block sign-in and revoke sessions')) { Complete-UT19Step 'Block sign-in and revoke sessions' $user['userPrincipalName'] Planned -PassThru:$PassThru; return }
$null=Save-UMJson -Value $user -Label 'BlockAccess-Before'
$null=Invoke-UMGraph -Method PATCH -Path ('/users/'+$user['id']) -Body @{accountEnabled=$false}
Write-M365Log -Message ('Blocked sign-in: '+$user['userPrincipalName']) -Level Change
$response=Invoke-UMGraph -Method POST -Path ('/users/'+$user['id']+'/revokeSignInSessions') -Body @{}
if ($response['value'] -ne $true) { throw 'Sign-in was blocked, but Graph did not confirm revocation. Review partial result.' }
$after=Get-UMUser $user['id']
if ($after['accountEnabled'] -ne $false) { throw 'Sign-in block not yet verified. Review Entra before retrying.' }
Write-Host 'Revocation requested. Active application sessions may not end immediately.' -ForegroundColor DarkYellow
Complete-UT19Step 'Block sign-in and revoke sessions' $user['userPrincipalName'] Success -PassThru:$PassThru
