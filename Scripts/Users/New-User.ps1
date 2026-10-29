#Requires -Version 7.4
<#
.SYNOPSIS
Create a cloud member with recoverable input, license and group steps.
.DESCRIPTION
Retry test 1: preserves inputs and created identity within THIS invocation. Each
optional assignment is independent. No whole-workflow replay or automatic rollback.
Unknown account-create outcomes are never adopted or blindly replayed. Password
generation/entry and first-login change are configurable. US location and recovery are retained.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$DisplayName,[string]$MailNickname,
      [string]$UsageLocation='US',[string[]]$LicenseSkuIds,[string[]]$GroupIds,
      [securestring]$TemporaryPassword,
      [switch]$GeneratePassword,
      [bool]$ForceChangePasswordNextSignIn=$true,
      [string]$ExportDirectory,[string]$ReportName,[switch]$NoOutputPrompt)
$ErrorActionPreference='Stop'
if ($NoOutputPrompt -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$UT19State=[pscustomobject]@{ResultsShown=$false}
. (Join-Path $PSScriptRoot 'UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.Retry.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.Passwords.ps1')
$passwordMode=''; $passwordMaterial=$null
if ($GeneratePassword -and $TemporaryPassword) { throw 'Use either -GeneratePassword or -TemporaryPassword, not both.' }
$tenant=Initialize-UMTask -Root $PSScriptRoot -TaskId 'users.new-user' -TaskName 'Create New User' -Scopes @('User.ReadWrite.All')
$state=@{UPN=$UserPrincipalName;DisplayName=$DisplayName;Alias=$MailNickname;Location=$UsageLocation;Licenses=@();Groups=@();Created=$null}
$results=[Collections.Generic.List[object]]::new()
$check={param($ctx) $null=Assert-M365Connection -NoPrompt -Service Graph -GraphScopes @('User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All') -TaskName 'Resume current create-user step'}
function Require-NewUserStep {
    param($Outcome)
    if ($Outcome.Status -eq 'Cancelled') { throw [OperationCanceledException]::new('Remaining work cancelled. Completed changes are retained.') }
    return $Outcome
}
try {
    while ($true) {
        $state.UPN=Read-ToolkitValidatedValue -Prompt 'New user UPN (Enter cancels)' -InitialValue $state.UPN -UseInitial:([bool]$state.UPN) -EmptyCancels -Validate {
            param($value)
            if ($value -notmatch '^[^\s@]+@[^\s@]+$') { return 'Enter a valid UPN.' }
            if (@($tenant.VerifiedDomains) -inotcontains $value.Split('@')[1]) { return 'UPN suffix is not a verified domain of this tenant.' }
            return ''
        }
        $lookup=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Check UPN availability' -Context $state -Check $check -Action {
            param($ctx)
            $filter=[uri]::EscapeDataString("userPrincipalName eq '$($ctx.UPN.Replace("'","''"))'")
            return @(Get-UMCollection -Path ('/users?$filter='+$filter+'&$select=id,userPrincipalName'))
        })
        if (@($lookup.Value | Where-Object { $_ }).Count -eq 0) { break }
        Write-Host 'That UPN already exists. Choose another UPN; nothing has been created by this run.' -ForegroundColor Yellow
        $state.UPN=''
    }
    $state.DisplayName=Read-ToolkitValidatedValue -Prompt 'Display name' -InitialValue $state.DisplayName -UseInitial:([bool]$state.DisplayName) -Validate {param($v) if ([string]::IsNullOrWhiteSpace($v)) {return 'Display name is required.'}; return ''}
    if (-not $state.Alias) { $state.Alias=($state.UPN.Split('@')[0] -replace '[^a-zA-Z0-9._-]','') }
    $state.Alias=Read-ToolkitValidatedValue -Prompt 'Mail nickname' -InitialValue $state.Alias -UseInitial -Validate {param($v) if ($v -notmatch '^[a-zA-Z0-9._-]+$') {return 'Use letters, numbers, dots, underscores or hyphens.'}; return ''}
    # Default silently to US; an explicit -UsageLocation value overrides it.
    $state.Location=([string]$state.Location).Trim()
    if (-not $state.Location) { $state.Location='US' }
    $state.Location=Read-ToolkitValidatedValue -Prompt 'Usage location: two-letter country code (default US)' -InitialValue $state.Location -UseInitial -Validate {param($v) if ($v -notmatch '^[A-Za-z]{2}$') {return 'UsageLocation must be a two-letter country code.'}; return ''}
    $state.Location=$state.Location.ToUpperInvariant()
    Write-Host ('Usage location: '+$state.Location) -ForegroundColor DarkGray
    if ($PSBoundParameters.ContainsKey('LicenseSkuIds')) { $state.Licenses=@($LicenseSkuIds | Where-Object { $_ } | Select-Object -Unique) }
    else {
        $pick=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Select licenses' -Context $state -Check $check -Optional -RetryValidation -Action {param($ctx) Select-WFLicenses})
        if ($pick.Status -eq 'Success') { $state.Licenses=@($pick.Value | Where-Object { $_ } | Select-Object -Unique) }
    }
    if ($PSBoundParameters.ContainsKey('GroupIds')) { $state.Groups=@($GroupIds | Where-Object { $_ } | Select-Object -Unique) }
    else {
        $pick=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Select groups' -Context $state -Check $check -Optional -RetryValidation -Action {param($ctx) Select-WFNewUserGroups -Tenant $tenant})
        if ($pick.Status -eq 'Success') { $state.Groups=@($pick.Value | Where-Object { $_ } | Select-Object -Unique) }
    }
    if ($state.Licenses.Count -and -not $state.Location) {
        $state.Location=(Read-ToolkitValidatedValue -Prompt 'Usage location is required for licensing' -Validate {param($v) if ($v -notmatch '^[A-Za-z]{2}$') {return 'Enter a two-letter country code.'}; return ''}).ToUpperInvariant()
    }
    # Validate optional targets before creation. Edit only the failing selection.
    $validatedGroups=[Collections.Generic.List[object]]::new()
    foreach ($id in $state.Groups) {
        $context=@{Id=$id}
        $validated=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name ('Validate group '+$id) -Context $context -Check $check -Optional -Action {
            param($ctx)
            $g=Get-UMGroup $ctx.Id; $reason=Get-UMGroupReason $g
            if ($reason) { throw $reason }
            return $g
        } -Edit {
            param($ctx)
            $choices=@(Select-WFNewUserGroups -Tenant $tenant)
            if ($choices.Count -ne 1) { Write-Host 'Choose exactly ONE replacement group, or skip this step.' -ForegroundColor Yellow; return $false }
            $ctx.Id=$choices[0]; return $true
        })
        if ($validated.Status -eq 'Success') { $validatedGroups.Add($validated.Value) }
    }
    $validatedSkus=[Collections.Generic.List[object]]::new()
    foreach ($id in $state.Licenses) {
        $context=@{Id=$id}
        $validated=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name ('Validate license '+$id) -Context $context -Check $check -Optional -Action {
            param($ctx)
            $guid=[guid]::Empty
            if (-not [guid]::TryParse($ctx.Id,[ref]$guid)) { throw 'SKU ID must be a GUID.' }
            $skus=@(Get-UMCollection '/subscribedSkus')
            $sku=@($skus | Where-Object { [string]$_['skuId'] -ieq $ctx.Id })
            if ($sku.Count -ne 1 -or $sku[0]['capabilityStatus'] -ne 'Enabled' -or $sku[0]['appliesTo'] -ne 'User') { throw 'The selected SKU is unavailable or not a user SKU.' }
            if ([int]$sku[0]['prepaidUnits']['enabled'] -le [int]$sku[0]['consumedUnits']) { throw 'No available seats for the selected SKU.' }
            return $sku[0]
        } -Edit {
            param($ctx)
            $choices=@(Select-WFLicenses)
            if ($choices.Count -ne 1) { Write-Host 'Choose exactly ONE replacement license, or skip this step.' -ForegroundColor Yellow; return $false }
            $ctx.Id=$choices[0]; return $true
        })
        if ($validated.Status -eq 'Success') { $validatedSkus.Add($validated.Value) }
    }
    $groups=@($validatedGroups.ToArray() | Sort-Object -Property {$_['id']} -Unique)
    $skus=@($validatedSkus.ToArray() | Sort-Object -Property {$_['skuId']} -Unique)
    $passwordMode=Select-ToolkitPasswordMode -SuppliedPassword $TemporaryPassword -GeneratePassword:$GeneratePassword
    if (-not $PSBoundParameters.ContainsKey('ForceChangePasswordNextSignIn')) { $ForceChangePasswordNextSignIn=Read-ToolkitPasswordChangeChoice }
    $plan=[pscustomobject]@{UserPrincipalName=$state.UPN;DisplayName=$state.DisplayName;MailNickname=$state.Alias;UsageLocation=$state.Location;Enabled=$true;LicenseSkuIds=@($skus | ForEach-Object {$_['skuId']});GroupIds=@($groups | ForEach-Object {$_['id']});PasswordMode=$passwordMode;ForceChangePasswordNextSignIn=$ForceChangePasswordNextSignIn}
    $plan | Format-List | Out-Host
    foreach ($g in $groups) { Write-Host ('Group: '+$g['displayName']) }
    foreach ($sku in $skus) { Write-Host ('License: '+(Get-WFProductName $sku['skuPartNumber'])) }
    if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action 'Create cloud user and listed optional assignments' -Target $state.UPN -Impact High)) { return }
    if (-not $PSCmdlet.ShouldProcess($state.UPN,'Create user and listed optional assignments')) { return }
    # No password is generated/read until the approved operation passes ShouldProcess.
    $passwordMaterial=New-ToolkitPasswordMaterial -Mode $passwordMode -SuppliedPassword $TemporaryPassword
    $TemporaryPassword=$passwordMaterial.Password
    $null=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Save approved plan' -Action {param($ctx) $null=Save-UMJson -Value $plan -Label 'NewUser-ApprovedPlan'})
    # Creation is not put inside an automatic replay wrapper. After any uncertain
    # response, an existing UPN causes a safe stop, never silent adoption/recreation.
    $attempted=$false
    while (-not $state.Created) {
        & $check $state
        if ($attempted) {
            $absent=$false
            try { $existing=Get-UMUser $state.UPN }
            catch {
                if ((Get-ToolkitHttpStatus $_) -eq 404) { $absent=$true; $existing=$null }
                else { $existing=$null }
            }
            if ($existing) { throw 'An account now exists for this UPN after an uncertain create response. Inspect Entra before continuing. No duplicate create or automatic adoption was attempted.' }
            if (-not $absent) {
                Write-Host 'Cannot verify that this UPN is absent. No additional create request will be sent.' -ForegroundColor Yellow
                $choice=Read-ToolkitRecoveryChoice -Step 'Recheck account creation outcome'
                if ($choice -eq 'Cancel') { throw [OperationCanceledException]::new('Creation outcome unverified; inspect Entra before another run.') }
                continue
            }
        }
        $ptr=[IntPtr]::Zero; $plain=$null; $body=$null; $created=$null
        try {
            $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($TemporaryPassword)
            $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            $body=@{accountEnabled=$true;displayName=$state.DisplayName;mailNickname=$state.Alias;userPrincipalName=$state.UPN;passwordProfile=@{password=$plain;forceChangePasswordNextSignIn=$ForceChangePasswordNextSignIn}}
            if ($state.Location) { $body['usageLocation']=$state.Location }
            try { $created=Invoke-UMGraph -Method POST -Path '/users' -Body $body }
            catch { $created=$null }
        }
        finally {
            if ($body) { $body.Remove('passwordProfile') }
            $plain=$null
            if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        }
        if ($created -and $created['id']) { $state.Created=$created; break }
        $attempted=$true
        Write-Host 'Creation failed or did not return an ID. Sensitive request details are suppressed. Retry first checks whether the account exists.' -ForegroundColor Yellow
        $choice=Read-ToolkitRecoveryChoice -Step 'Create account' -CanEdit
        if ($choice -eq 'Cancel') { throw [OperationCanceledException]::new('Inspect Entra for this UPN before starting another run.') }
        if ($choice -eq 'Edit') {
            if ($passwordMaterial -and $passwordMaterial.Owned) { $passwordMaterial.Password.Dispose() }
            $TemporaryPassword=$null; $passwordMaterial=$null
            $passwordMode=Select-ToolkitPasswordMode
            $passwordMaterial=New-ToolkitPasswordMaterial -Mode $passwordMode
            $TemporaryPassword=$passwordMaterial.Password
            $plan.PasswordMode=$passwordMode
            $null=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Save password-mode plan amendment' -Action {param($ctx) $null=Save-UMJson -Value @{UserPrincipalName=$state.UPN;PasswordMode=$passwordMode;ForceChangePasswordNextSignIn=$ForceChangePasswordNextSignIn} -Label 'NewUser-PasswordModeAmendment'})
        }
    }
    $createdId=[string]$state.Created['id']
    Write-Host ('Created account retained: '+$state.UPN+' ['+$createdId+']') -ForegroundColor Green
    $results.Add([pscustomobject]@{Target=$state.UPN;Action='Create user';Result='Success';Error=''})
    # This call site is outside creation/assignment retry loops and runs only
    # after a confirmed create response includes the new account ID.
    if ($passwordMaterial.Generated) {
        Show-ToolkitGeneratedPassword -Password $TemporaryPassword -UserPrincipalName $state.UPN -UserId $createdId -AccountCreated
    }
    try { Write-M365Log -Message ('Created user '+$state.UPN+' ('+$createdId+').') -Level Change } catch { Write-Warning 'Could not write the creation log; the account was created.' }
    $null=Require-NewUserStep (Invoke-ToolkitRecoverableStep -Name 'Save created identity checkpoint' -Action {param($ctx) $null=Save-UMJson -Value @{Id=$createdId;UserPrincipalName=$state.UPN;Plan=$plan} -Label 'NewUser-CreatedIdentity'})
    $stopped=$false
    # One SKU per recovery step: a failed SKU never replays already completed SKUs.
    foreach ($sku in $skus) {
        $ctx=@{Id=[string]$sku['skuId'];Name=(Get-WFProductName $sku['skuPartNumber']);UserId=$createdId}
        $outcome=Invoke-ToolkitRecoverableStep -Name ('Assign license '+$ctx.Name) -Context $ctx -Check $check -Optional -Probe {
            param($c)
            $current=Invoke-UMGraph -Path ('/users/'+$c.UserId+'?$select=id,licenseAssignmentStates')
            if (-not $current.Contains('licenseAssignmentStates')) { throw 'License assignment metadata is incomplete; no write will be replayed until state can be checked.' }
            $direct=@($current['licenseAssignmentStates'] | Where-Object {[string]$_['skuId'] -ieq $c.Id -and -not $_['assignedByGroup']})
            if (-not $direct.Count) { return $false }
            if (@($direct | Where-Object {$_['state'] -ne 'Active'}).Count) { throw 'The direct assignment exists but is not Active. Review Entra; retry checks its state without replaying the write.' }
            return $true
        } -Action {
            param($c)
            $inventory=@(Get-UMCollection '/subscribedSkus' | Where-Object {[string]$_['skuId'] -ieq $c.Id})
            if ($inventory.Count -ne 1 -or $inventory[0]['capabilityStatus'] -ne 'Enabled' -or [int]$inventory[0]['prepaidUnits']['enabled'] -le [int]$inventory[0]['consumedUnits']) { throw 'License unavailable or no free seats. Retry after correcting availability, edit, skip, or cancel.' }
            $null=Invoke-UMGraph -Method POST -Path ('/users/'+$c.UserId+'/assignLicense') -Body @{addLicenses=@(@{skuId=$c.Id;disabledPlans=@()});removeLicenses=@()}
        } -Edit {
            param($c)
            $choices=@(Select-WFLicenses)
            if ($choices.Count -ne 1) { Write-Host 'Choose exactly ONE replacement license.'; return $false }
            if ($choices[0] -ieq $c.Id) { return $true }
            $replacement=@(Get-UMCollection '/subscribedSkus' | Where-Object {[string]$_['skuId'] -ieq $choices[0]})
            if ($replacement.Count -ne 1) { throw 'Replacement SKU not found.' }
            $name=Get-WFProductName $replacement[0]['skuPartNumber']
            if (-not (Confirm-M365Action -Action ('Assign replacement license '+$name) -Target ($state.UPN+' ['+$createdId+']') -Impact High)) { return $false }
            $null=Save-UMJson -Value @{UserId=$createdId;OldSkuId=$c.Id;NewSkuId=$choices[0]} -Label 'NewUser-LicensePlanAmendment'
            $c.Id=$choices[0]; $c.Name=$name; return $true
        }
        $results.Add([pscustomobject]@{Target=$ctx.Name;Action='Assign license';Result=$outcome.Status;Error=$(if ($outcome.Status -eq 'Success') {''} else {$outcome.Detail})})
        if ($outcome.Status -eq 'Cancelled') { $stopped=$true; break }
    }
    if (-not $stopped) {
        foreach ($g in $groups) {
            $ctx=@{Id=[string]$g['id'];Name=[string]$g['displayName'];UserId=$createdId}
            $outcome=Invoke-ToolkitRecoverableStep -Name ('Add group '+$ctx.Name) -Context $ctx -Check $check -Optional -Probe {
                param($c)
                $fresh=Get-UMGroup $c.Id; $reason=Get-UMGroupReason $fresh
                if ($reason) { throw ('Group eligibility changed: '+$reason) }
                $memberships=@(Get-UMCollection ('/users/'+$c.UserId+'/memberOf/microsoft.graph.group?$select=id'))
                return (@($memberships | Where-Object {[string]$_['id'] -ieq $c.Id}).Count -gt 0)
            } -Action {
                param($c)
                $fresh=Get-UMGroup $c.Id; $reason=Get-UMGroupReason $fresh
                if ($reason) { throw ('Group eligibility changed: '+$reason) }
                $null=Invoke-UMGraph -Method POST -Path ('/groups/'+$c.Id+'/members/$ref') -Body @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$c.UserId)}
            } -Edit {
                param($c)
                $choices=@(Select-WFNewUserGroups -Tenant $tenant)
                if ($choices.Count -ne 1) { Write-Host 'Choose exactly ONE replacement group.'; return $false }
                $replacement=Get-UMGroup $choices[0]; $reason=Get-UMGroupReason $replacement
                if ($reason) { throw $reason }
                if ($choices[0] -ieq $c.Id) { return $true }
                if (-not (Confirm-M365Action -Action ('Add to replacement group '+$replacement['displayName']) -Target ($state.UPN+' ['+$createdId+']') -Impact High)) { return $false }
                $null=Save-UMJson -Value @{UserId=$createdId;OldGroupId=$c.Id;NewGroupId=$choices[0]} -Label 'NewUser-GroupPlanAmendment'
                $c.Id=$choices[0]; $c.Name=[string]$replacement['displayName']; return $true
            }
            $results.Add([pscustomobject]@{Target=$ctx.Name;Action='Add membership';Result=$outcome.Status;Error=$(if ($outcome.Status -eq 'Success') {''} else {$outcome.Detail})})
            if ($outcome.Status -eq 'Cancelled') { $stopped=$true; break }
        }
    }
    if ($stopped) { Write-Host 'Remaining assignments cancelled. The account and completed assignments are retained.' -ForegroundColor Yellow }
}
catch [OperationCanceledException] { Write-Host $_.Exception.Message -ForegroundColor Yellow }
finally {
    if ($passwordMaterial -and $passwordMaterial.Owned) {
        $passwordMaterial.Password.Dispose()
        $TemporaryPassword=$null
    }
    if ($results.Count) {
        try { Write-UT19Results -Results $results.ToArray() -Label 'NewUser' }
        catch { $results.ToArray() | Format-Table -AutoSize | Out-Host; Write-Warning 'Could not save results. Review the created account and the displayed partial results.' }
        Write-Host 'No automatic rollback or account recreation was performed. Completed changes are retained.' -ForegroundColor Yellow
    }
}
