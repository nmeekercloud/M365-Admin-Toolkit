#Requires -Version 7.4
<#
.SYNOPSIS
List/view/create/convert shared mailboxes and manage direct delegates.
.DESCRIPTION
No mailbox deletion, license removal, sign-in changes, or conversion back to regular.
.EXAMPLE
.\Invoke-SharedMailboxManagement.ps1 -Operation Create -Name Accounts -Alias accounts -PrimarySmtpAddress accounts@contoso.com -WhatIf
.NOTES
Services: ExchangeOnline. Scopes: none. Impact: High for changes.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param(
    [ValidateSet('List','View','Create','Convert','AddDelegate','RemoveDelegate')][string]$Operation,
    [string]$Identity,[string]$Name,[string]$Alias,[string]$PrimarySmtpAddress,[string]$DelegateIdentity,
    [ValidateSet('FullAccess','SendAs','SendOnBehalf')][string[]]$Rights,
    [bool]$AutoMapping=$true,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru
)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and (-not $Operation -or ($Operation -eq 'Create' -and (-not $Name -or -not $Alias -or -not $PrimarySmtpAddress)) -or ($Operation -notin @('List','Create') -and -not $Identity) -or ($Operation -in @('AddDelegate','RemoveDelegate') -and (-not $DelegateIdentity -or -not $Rights)))) { throw 'NoInteractive requires Operation and all applicable identity/create/delegate settings.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.Exchange12.ps1')
Initialize-E12
if (-not $Operation) {
    $choice=Read-E12Required '' '[1] List [2] View [3] Create [4] Convert user to shared [5] Add delegate [6] Remove delegate'
    $Operation=switch ($choice) {'1' {'List'} '2' {'View'} '3' {'Create'} '4' {'Convert'} '5' {'AddDelegate'} '6' {'RemoveDelegate'} default {throw 'Invalid operation.'}}
}
if ($Operation -eq 'List') {
    $rows=@(Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop | Select-Object DisplayName,PrimarySmtpAddress,Alias,IsDirSynced)
    Show-EX17Output -Rows $rows -Columns @('DisplayName','PrimarySmtpAddress','Alias','IsDirSynced') -Label 'Shared mailboxes' -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
    if ($PassThru) { $rows }; return
}
if ($Operation -eq 'Create') {
    $Name=Read-E12Required $Name 'Display name (blank cancels)'
    $Alias=Read-E12Required $Alias 'Alias (blank cancels)'
    $PrimarySmtpAddress=Read-E12Required $PrimarySmtpAddress 'Primary SMTP (blank cancels)'
    try { $address=[System.Net.Mail.MailAddress]::new($PrimarySmtpAddress) } catch { throw 'Invalid SMTP address.' }
    if ($address.Address -ine $PrimarySmtpAddress) { throw 'Enter only an SMTP address, without display name.' }
    if ($Alias -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Alias: 1-64 characters; letters/digits/dot/underscore/hyphen.' }
    $domain=$PrimarySmtpAddress.Split('@')[-1]
    $accepted=@(Get-AcceptedDomain -ErrorAction Stop | ForEach-Object { [string]$_.DomainName })
    if ($domain -notin $accepted) { throw 'SMTP domain must be an exact accepted domain in this tenant.' }
    $smtpFilter=$PrimarySmtpAddress.Replace("'","''"); $aliasFilter=$Alias.Replace("'","''")
    $existing=@(Get-Recipient -Filter "(EmailAddresses -eq 'smtp:$smtpFilter') -or (Alias -eq '$aliasFilter')" -ResultSize Unlimited -ErrorAction Stop)
    if ($existing.Count) { throw 'An active recipient already uses that address or alias.' }
    $action="Create shared mailbox '$Name', alias '$Alias', primary SMTP '$PrimarySmtpAddress'"
    Write-Host $action
    if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action $action -Target $PrimarySmtpAddress -Impact High)) { return }
    $result='Declined'; $errorText=''; $mutationApplied=$false
    if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress,$action)) {
        $null=Save-E12Backup @{Operation='Create';Name=$Name;Alias=$Alias;PrimarySmtpAddress=$PrimarySmtpAddress;Note='Creation intent; not a mailbox content backup'} 'SharedMailbox-CreateIntent'
        try {
            $null=New-Mailbox -Shared -Name $Name -DisplayName $Name -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress -ErrorAction Stop
            $mutationApplied=$true; $result='AppliedUnverified'
            for ($attempt=0; $attempt -lt 3; $attempt++) {
                if ($attempt) { Start-Sleep -Seconds 2 }
                try {
                    $created=Get-Mailbox -Identity $PrimarySmtpAddress -ErrorAction Stop
                    if ($created.RecipientTypeDetails -eq 'SharedMailbox') { $result='Verified'; break }
                } catch { $errorText=$_.Exception.Message }
            }
            if ($result -eq 'Verified') { $errorText='' }
            Write-M365Log -Message "$result`: $action" -Level Change
        } catch { $result=if ($mutationApplied) {'AppliedUnverified'} else {'Failed'}; $errorText=$_.Exception.Message; Write-M365Log -Message $errorText -Level Error }
    } elseif ($WhatIfPreference) { $result='WhatIf' }
    Write-EX17Results @([pscustomobject]@{Mailbox=$PrimarySmtpAddress;Delegate='';Right='Create';Result=$result;Error=$errorText}) 'SharedMailbox' -PassThru:$PassThru
    return
}
$Identity=Read-E12Required $Identity 'Mailbox SMTP (blank cancels)'
$mailbox=Get-E12Mailbox $Identity -Writable:($Operation -ne 'View')
$smtp=[string]$mailbox.PrimarySmtpAddress
if ($Operation -eq 'Convert') {
    if ($mailbox.RecipientTypeDetails -eq 'SharedMailbox') { Write-Host 'Already shared; no change.'; return }
    Write-Warning 'Conversion does not block sign-in or remove licenses. Review archive/holds/size/licensing separately. Do not delete the associated account.'
    $action='Convert user mailbox to shared; leave licenses and account sign-in unchanged'
    if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action $action -Target $smtp -Impact High)) { return }
    $result='Declined'; $errorText=''; $mutationApplied=$false
    if ($PSCmdlet.ShouldProcess($smtp,$action)) {
        $null=Save-E12Backup (Get-E12Snapshot $mailbox) 'SharedMailbox-Convert-Before'
        try {
            Set-Mailbox -Identity $smtp -Type Shared -Confirm:$false -ErrorAction Stop
            $mutationApplied=$true; $result='AppliedUnverified'
            for ($attempt=0; $attempt -lt 3; $attempt++) {
                if ($attempt) { Start-Sleep -Seconds 2 }
                $current=Get-Mailbox -Identity $smtp -ErrorAction Stop
                if ($current.RecipientTypeDetails -eq 'SharedMailbox') { $result='Verified'; break }
            }
            Write-M365Log -Message "$result`: convert $smtp to shared" -Level Change
        } catch { $result=if ($mutationApplied) {'AppliedUnverified'} else {'Failed'}; $errorText=$_.Exception.Message; Write-M365Log -Message $errorText -Level Error }
    } elseif ($WhatIfPreference) { $result='WhatIf' }
    Write-EX17Results @([pscustomobject]@{Mailbox=$smtp;Delegate='';Right='Convert';Result=$result;Error=$errorText}) 'SharedMailbox' -PassThru:$PassThru
    return
}
if ($mailbox.RecipientTypeDetails -ne 'SharedMailbox') { throw 'Choose a shared mailbox, or convert first.' }
$snapshot=Get-E12Snapshot $mailbox
if ($Operation -eq 'View') {
    $mailbox | Select-Object DisplayName,PrimarySmtpAddress,RecipientTypeDetails,IsDirSynced | Format-List | Out-Host
    Show-EX17Output -Rows @($snapshot.Rows) -Columns @('Delegate','Right','Denied') -Label 'Shared mailbox delegation' -Metadata @{Mailbox=$smtp;Scope='Direct delegation only; not effective/group-derived or folder access'} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
    Write-Host 'Direct delegation only; not effective/group-derived or folder access.'
    if ($PassThru) { $snapshot }; return
}
$DelegateIdentity=Read-E12Required $DelegateIdentity 'Delegate SMTP (blank cancels)'
$delegate=Get-E12Recipient $DelegateIdentity
if ((Get-E12Key $delegate) -eq (Get-E12Key $mailbox)) { throw 'A mailbox cannot delegate to itself.' }
if (-not $Rights) {
    $choice=Read-E12Required '' 'Rights: FullAccess, SendAs, SendOnBehalf (comma-separated)'
    $Rights=@($choice -split ',' | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if (@($Rights | Where-Object { $_ -notin @('FullAccess','SendAs','SendOnBehalf') }).Count) { throw 'Invalid right.' }
}
$add=$Operation -eq 'AddDelegate'
$plan=@(foreach ($right in @($Rights | Select-Object -Unique)) {
    if (Test-E12Right $snapshot $delegate $right -Denied) { throw 'Explicit deny ACL present; review manually.' }
    $present=Test-E12Right $snapshot $delegate $right
    [pscustomobject]@{Right=$right;Existing=$present;Change=($present -ne $add)}
})
$plan | Format-Table -AutoSize | Out-Host
$changes=@($plan | Where-Object Change)
$action="$Operation for $($delegate.PrimarySmtpAddress): $($changes.Right -join ', '); AutoMapping for new FullAccess=$AutoMapping"
if ($changes.Count -and -not $WhatIfPreference -and -not (Confirm-M365Action -Action $action -Target $smtp -Impact High)) { return }
$backedUp=$false
$results=@(foreach ($item in $plan) {
    $status='NoChange'; $errorText=''; $mutationApplied=$false
    if ($item.Change) {
        if ($PSCmdlet.ShouldProcess($smtp,"$Operation $($item.Right) for $($delegate.PrimarySmtpAddress); AutoMapping=$AutoMapping")) {
            if (-not $backedUp) { $null=Save-E12Backup $snapshot 'SharedMailbox-Delegates-Before'; $backedUp=$true }
            try {
                $current=Get-E12Snapshot (Get-E12Mailbox $smtp -Writable)
                if (Test-E12Right $current $delegate $item.Right -Denied) { throw 'A deny entry is now present; refusing change.' }
                if ((Test-E12Right $current $delegate $item.Right) -eq $add) { $status='NoChange' }
                else {
                    $verb=if ($add) {'Add'} else {'Remove'}
                    Set-E12Right $smtp $delegate $item.Right $verb -AutoMapping $AutoMapping
                    $mutationApplied=$true
                    $status=if (Test-E12Verified $smtp $delegate $item.Right $add) {'Verified'} else {'AppliedUnverified'}
                    Write-M365Log -Message "$status`: $verb $($item.Right) for $($delegate.PrimarySmtpAddress) on $smtp" -Level Change
                }
            } catch { $status=if ($mutationApplied) {'AppliedUnverified'} else {'Failed'}; $errorText=$_.Exception.Message; Write-M365Log -Message $errorText -Level Error }
        } else { $status=if ($WhatIfPreference) {'WhatIf'} else {'Declined'} }
    }
    [pscustomobject]@{Mailbox=$smtp;Delegate=[string]$delegate.PrimarySmtpAddress;Right=$item.Right;Result=$status;Error=$errorText}
})
Write-EX17Results $results 'SharedMailbox-Delegates' -PassThru:$PassThru
