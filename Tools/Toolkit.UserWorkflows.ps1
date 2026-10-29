# Definitions only. Shared by onboarding, offboarding and standalone tasks.
function Get-WFProductName {
    param([string]$PartNumber)
    $names=@{
        O365_BUSINESS_ESSENTIALS='Microsoft 365 Business Basic';O365_BUSINESS_PREMIUM='Microsoft 365 Business Standard'
        SPB='Microsoft 365 Business Premium';SMB_BUSINESS='Microsoft 365 Apps for business'
        OFFICESUBSCRIPTION='Microsoft 365 Apps for enterprise';SPE_E3='Microsoft 365 E3';SPE_E5='Microsoft 365 E5'
        ENTERPRISEPACK='Office 365 E3';ENTERPRISEPREMIUM='Office 365 E5';STANDARDPACK='Office 365 E1'
        EXCHANGESTANDARD='Exchange Online Plan 1';EXCHANGEENTERPRISE='Exchange Online Plan 2'
        POWER_BI_PRO='Power BI Pro';POWER_BI_STANDARD='Power BI Free';PROJECTPROFESSIONAL='Project Plan 3'
        VISIOCLIENT='Visio Plan 2';TEAMS_EXPLORATORY='Microsoft Teams Exploratory'
    }
    if ($names.ContainsKey($PartNumber)) { return ($names[$PartNumber]+' ['+$PartNumber+']') }
    return $PartNumber
}
function Read-WFSelection {
    param([object[]]$Rows,[string]$Prompt='Select numbers separated by commas (Enter skips)',[switch]$AllowAll)
    if (-not $Rows.Count) { return }
    $answer=([string](Read-Host $Prompt)).Trim()
    if (-not $answer) { return }
    if ($AllowAll -and $answer -ieq 'ALL') { return @($Rows | Where-Object Eligible) }
    $tokens=@(ConvertTo-UMList $answer)
    $selected=@()
    foreach ($token in $tokens) {
        if ($token -notmatch '^\d{1,6}$') { throw "Not a selection number: $token" }
        $match=@($Rows | Where-Object Number -eq ([int]$token))
        if ($match.Count -ne 1 -or -not $match[0].Eligible) { throw "Unavailable selection: $token" }
        $selected+=,$match[0]
    }
    return $selected
}
function Get-WFLicenseRows {
    param([object[]]$Skus)
    $number=0
    foreach ($sku in @($Skus | Sort-Object { $_['skuPartNumber'] })) {
        $number++
        $enabled=[int]$sku['prepaidUnits']['enabled']; $used=[int]$sku['consumedUnits']
        $available=[math]::Max(0,$enabled-$used)
        $eligible=($sku['capabilityStatus'] -eq 'Enabled' -and $sku['appliesTo'] -eq 'User' -and $available -gt 0)
        [pscustomobject]@{Number=$number;Product=(Get-WFProductName $sku['skuPartNumber']);Enabled=$enabled;Assigned=$used;Available=$available;State=$sku['capabilityStatus'];Eligible=$eligible;Id=$sku['skuId']}
    }
}
function Select-WFLicenses {
    $null=Assert-M365Connection -GraphScopes @('User.ReadWrite.All','LicenseAssignment.Read.All') -TaskName 'List tenant license inventory for user creation'
    $rows=@(Get-WFLicenseRows -Skus @(Get-UMCollection '/subscribedSkus'))
    $rows | Select-Object Number,Product,Enabled,Assigned,Available,State,Eligible | Format-Table -AutoSize | Out-Host
    Write-Host 'Available = enabled seats minus assigned seats (minimum zero). Counts are a snapshot; SKU/service restrictions can still prevent assignment.' -ForegroundColor DarkYellow
    @(Read-WFSelection -Rows $rows | ForEach-Object Id)
}
function Select-WFGroups {
    param([object[]]$Groups)
    $rows=@(); $n=0
    foreach ($g in @($Groups | Sort-Object { $_['displayName'] })) {
        $n++; $reason=Get-UMGroupReason $g
        $rows+=[pscustomobject]@{Number=$n;Name=$g['displayName'];Type=$(if (@($g['groupTypes']) -contains 'Unified') {'Microsoft 365'} else {'Security/other'});Status=$(if ($reason) {$reason} else {'Eligible'});Eligible=(-not $reason);Id=$g['id']}
    }
    $rows | Select-Object Number,Name,Type,Status | Format-Table -Wrap | Out-Host
    if (-not @($rows | Where-Object Eligible).Count) {
        Write-Host 'No eligible groups in these results. Group selection skipped; no group memberships will be added.' -ForegroundColor Yellow
        return
    }
    # Only group-picker validation is retried here. Graph/tenant/API errors are
    # not swallowed, and the license picker/general retry behavior is unchanged.
    while ($true) {
        try {
            $selected=@(Read-WFSelection -Rows $rows -AllowAll -Prompt 'Group numbers, ALL for eligible groups, or Enter to skip')
            return @($selected | ForEach-Object Id)
        }
        catch {
            $message=$_.Exception.Message
            if ($message -notlike 'Unavailable selection:*' -and $message -notlike 'Not a selection number:*') { throw }
            Write-Host ($message+' Choose an Eligible row, ALL, or press Enter to skip.') -ForegroundColor Yellow
        }
    }
}
function Select-WFNewUserGroups {
    param([object]$Tenant)
    Write-Host '[1] Pick tenant groups  [2] Copy from existing user  [3] Both  [0] Skip'
    $mode=([string](Read-Host 'Group assignment [0]')).Trim()
    if (-not $mode -or $mode -eq '0') { return }
    if ($mode -notin @('1','2','3')) { throw 'Choose 0, 1, 2 or 3.' }
    $null=Assert-M365Connection -GraphScopes @('User.ReadWrite.All','Group.Read.All','GroupMember.ReadWrite.All') -TaskName 'Select onboarding group memberships'
    $selected=@()
    if ($mode -in @('1','3')) {
        # Fetch all pages, then filter locally. Do not silently truncate tenant groups.
        $groups=@(Get-UMCollection '/groups?$select=id,displayName,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,isAssignableToRole')
        while ($true) {
            $term=([string](Read-Host 'Group name search (Enter lists all)')).Trim()
            $filtered=@($groups | Where-Object { -not $term -or ([string]$_['displayName']).IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
            if ($filtered.Count -gt 100) { Write-Host 'More than 100 matches; enter a narrower search.' -ForegroundColor DarkYellow; continue }
            $selected+=@(Select-WFGroups -Groups $filtered); break
        }
    }
    if ($mode -in @('2','3')) {
        $upn=([string](Read-Host 'Source user UPN (Enter skips copying)')).Trim()
        if ($upn) {
            $source=Get-UMUser $upn
            Assert-UMCloudMember -User $source -Tenant $Tenant -AllowSelf
            $members=@(Get-UMCollection ('/users/'+$source['id']+'/memberOf/microsoft.graph.group?$select=id'))
            $groups=@(foreach ($entry in $members) { Get-UMGroup $entry['id'] })
            Write-Host ('Copy source: '+$source['userPrincipalName']+'. Direct memberships only; no directory roles, owners or mailbox permissions.') -ForegroundColor DarkYellow
            $selected+=@(Select-WFGroups -Groups $groups)
        }
    }
    @($selected | Select-Object -Unique)
}
function Initialize-WFTask {
    param([string]$TaskId,[string]$TaskName,[string[]]$Scopes=@('User.Read.All'),[switch]$Exchange)
    $root=Split-Path -Parent $PSScriptRoot
    if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
    Assert-M365TaskAccess -AccessMode Changes -TaskId $TaskId
    $services=@('Graph'); if ($Exchange) { $services+='ExchangeOnline' }
    Assert-M365Connection -Service $services -GraphScopes $Scopes -TaskName $TaskName -TaskId $TaskId
}
function Get-WFMailboxTarget {
    param([string]$Identity,[object]$Tenant)
    $user=Get-UMUser $Identity
    Assert-UMCloudMember -User $user -Tenant $Tenant
    $mailbox=Get-Mailbox -Identity $user['userPrincipalName'] -ErrorAction Stop
    if ([string]$mailbox.ExternalDirectoryObjectId -ine [string]$user['id']) { throw 'Mailbox does not match the selected directory user.' }
    if ([string]$mailbox.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox')) { throw 'Only cloud user/shared mailboxes are supported.' }
    [pscustomobject]@{User=$user;Mailbox=$mailbox;Identity=[string]$mailbox.PrimarySmtpAddress}
}
function Complete-WFStep {
    param([string]$Action,[string]$Target,[string]$Status='Success',[switch]$PassThru,[string]$Detail='')
    $level=if ($Status -eq 'Success') {'Change'} else {'Info'}
    Write-M365Log -Message ($Action+': '+$Target+' - '+$Status+' '+$Detail) -Level $level
    if ($PassThru) { [pscustomobject]@{Action=$Action;Target=$Target;Status=$Status;Detail=$Detail} }
}

function Test-WFDelegateRight {
    param([string]$Mailbox,[object]$Delegate,[ValidateSet('FullAccess','SendAs','SendOnBehalf')][string]$Right)
    switch ($Right) {
        'FullAccess' {
            $entries=@(Get-MailboxPermission -Identity $Mailbox -User $Delegate.PrimarySmtpAddress -ErrorAction Stop)
            if (@($entries | Where-Object { $_.Deny -and @($_.AccessRights) -contains 'FullAccess' }).Count) { throw 'An existing FullAccess deny entry requires manual review.' }
            return (@($entries | Where-Object { -not $_.Deny -and -not $_.IsInherited -and @($_.AccessRights) -contains 'FullAccess' }).Count -gt 0)
        }
        'SendAs' {
            $entries=@(Get-RecipientPermission -Identity $Mailbox -Trustee $Delegate.PrimarySmtpAddress -ErrorAction Stop)
            if (@($entries | Where-Object { [string]$_.AccessControlType -eq 'Deny' -and @($_.AccessRights) -contains 'SendAs' }).Count) { throw 'An existing SendAs deny entry requires manual review.' }
            return (@($entries | Where-Object { [string]$_.AccessControlType -eq 'Allow' -and -not $_.IsInherited -and @($_.AccessRights) -contains 'SendAs' }).Count -gt 0)
        }
        'SendOnBehalf' {
            $m=Get-Mailbox -Identity $Mailbox -ErrorAction Stop
            foreach ($id in @($m.GrantSendOnBehalfTo)) {
                $r=Get-Recipient -Identity $id -ErrorAction Stop
                if ([string]$r.ExternalDirectoryObjectId -ieq [string]$Delegate.ExternalDirectoryObjectId) { return $true }
            }
            return $false
        }
    }
}
function Get-WFLicenseAssignmentRows {
    param([System.Collections.IDictionary]$User,[object[]]$Skus)
    $n=0
    foreach ($license in @($User['assignedLicenses'])) {
        $n++; $id=[string]$license['skuId']
        $sku=@($Skus | Where-Object { [string]$_['skuId'] -ieq $id })
        $states=@($User['licenseAssignmentStates'] | Where-Object { [string]$_['skuId'] -ieq $id })
        $direct=@($states | Where-Object { -not $_['assignedByGroup'] }).Count -gt 0
        $inherited=@($states | Where-Object { $_['assignedByGroup'] }).Count -gt 0
        $name=if ($sku.Count -eq 1) { Get-WFProductName $sku[0]['skuPartNumber'] } else { $id }
        $origin=if ($direct -and $inherited) {'Direct + group'} elseif ($direct) {'Direct'} elseif ($inherited) {'Group only'} else {'Unknown'}
        [pscustomobject]@{Number=$n;Product=$name;Assignment=$origin;Eligible=($direct -and $sku.Count -eq 1);Id=$id;Inherited=$inherited;Sku=$(if ($sku.Count -eq 1) {$sku[0]} else {$null})}
    }
}
function Assert-WFExchangeLicenseRemoval {
    param([object]$Target)
    $mailbox=$Target.Mailbox
    if ([string]$mailbox.RecipientTypeDetails -ne 'SharedMailbox') { throw 'Exchange-bearing license removal is blocked until mailbox conversion to shared is verified.' }
    foreach ($name in @('LitigationHoldEnabled','ComplianceTagHoldApplied','DelayHoldApplied','DelayReleaseHoldApplied','RetentionHoldEnabled')) {
        if (-not $mailbox.PSObject.Properties[$name] -or $null -eq $mailbox.$name -or [bool]$mailbox.$name) { throw "Mailbox hold status requires manual review: $name" }
    }
    if ([string]$mailbox.ArchiveStatus -ne 'None' -or @($mailbox.InPlaceHolds).Count) { throw 'Archive or mailbox hold requires continued licensing/manual review.' }
    $org=Get-OrganizationConfig -ErrorAction Stop
    if (-not $org.PSObject.Properties['InPlaceHolds'] -or @($org.InPlaceHolds).Count) { throw 'Organization hold status requires manual review; no license removal.' }
    $stats=Get-MailboxStatistics -Identity $Target.Identity -ErrorAction Stop
    $text=[string]$stats.TotalItemSize; $bytes=$null
    if ($text -match '\(([0-9, ]+) bytes\)') { $bytes=[long](($Matches[1]) -replace '[, ]','') }
    if ($null -eq $bytes -or $bytes -ge 50GB) { throw 'Could not verify mailbox is below the 50 GB unlicensed limit. No removal.' }
}
