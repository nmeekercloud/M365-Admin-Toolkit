#Requires -Version 7.4
<#
.SYNOPSIS
Copy selected direct mailbox permissions, additively.
.DESCRIPTION
MailboxDelegates copies delegates ON one mailbox to another mailbox.
UserAccess copies rights HELD BY one user to another user on selected mailboxes.
No folder ACLs, inherited/group-derived permissions, deny ACLs, or source
AutoMapping state are copied. Existing destination grants remain unchanged.
.EXAMPLE
.\Copy-MailboxPermissions.ps1 -Mode MailboxDelegates -SourceIdentity old@contoso.com -DestinationIdentity new@contoso.com -Rights FullAccess,SendAs -WhatIf
.NOTES
Services: ExchangeOnline. Scopes: none. Impact: High for permission changes.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param(
    [ValidateSet('MailboxDelegates','UserAccess')][string]$Mode,
    [string]$SourceIdentity,[string]$DestinationIdentity,
    [ValidateSet('FullAccess','SendAs','SendOnBehalf')][string[]]$Rights,
    [string[]]$DelegateIdentity,[string[]]$MailboxIdentity,[switch]$AllMailboxes,
    [bool]$AutoMapping=$true,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru
)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
if ($NoInteractive -and (-not $Mode -or -not $SourceIdentity -or -not $DestinationIdentity -or -not $Rights -or ($Mode -eq 'UserAccess' -and -not $AllMailboxes -and -not $MailboxIdentity))) { throw 'NoInteractive requires Mode, source, destination, Rights and mailbox scope for UserAccess.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeOutput.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.Exchange12.ps1')
Initialize-E12
if (-not $Mode) {
    $choice=Read-E12Required '' '[1] Copy delegates ON a mailbox [2] Copy access HELD BY a user'
    $Mode=switch ($choice) {'1' {'MailboxDelegates'} '2' {'UserAccess'} default {throw 'Invalid copy mode.'}}
}
$SourceIdentity=Read-E12Required $SourceIdentity 'Source mailbox/user SMTP (blank cancels)'
$DestinationIdentity=Read-E12Required $DestinationIdentity 'Destination mailbox/user SMTP (blank cancels)'
if (-not $Rights) {
    $choice=Read-E12Required '' 'Rights: FullAccess, SendAs, SendOnBehalf (comma-separated)'
    $Rights=@($choice -split ',' | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if (@($Rights | Where-Object { $_ -notin @('FullAccess','SendAs','SendOnBehalf') }).Count) { throw 'Invalid right.' }
}
$plan=[System.Collections.Generic.List[object]]::new()
$backups=[System.Collections.Generic.List[object]]::new()
if ($Mode -eq 'MailboxDelegates') {
    if ($AllMailboxes -or $MailboxIdentity) { throw 'Mailbox selection applies only to UserAccess mode.' }
    $source=Get-E12Mailbox $SourceIdentity
    $destination=Get-E12Mailbox $DestinationIdentity -Writable
    if ((Get-E12Key $source) -eq (Get-E12Key $destination)) { throw 'Source and destination must differ.' }
    $sourceSnapshot=Get-E12Snapshot $source
    $targetSnapshot=Get-E12Snapshot $destination
    $backups.Add($sourceSnapshot); $backups.Add($targetSnapshot)
    $selectedKeys=@(foreach ($id in $DelegateIdentity) { Get-E12Key (Get-E12Recipient $id) })
    foreach ($row in @($sourceSnapshot.Rows | Where-Object { -not $_.Denied -and $_.Right -in $Rights })) {
        if ($selectedKeys.Count -and $row.Key -notin $selectedKeys) { continue }
        $delegate=Get-E12Recipient $row.Delegate
        if ((Get-E12Key $delegate) -eq (Get-E12Key $destination)) { continue }
        if ((Test-E12Right $sourceSnapshot $delegate $row.Right -Denied) -or (Test-E12Right $targetSnapshot $delegate $row.Right -Denied)) { throw 'Conflicting deny ACL: review manually.' }
        $plan.Add([pscustomobject]@{Mailbox=[string]$destination.PrimarySmtpAddress;Delegate=$row.Delegate;Recipient=$delegate;Right=$row.Right;Existing=(Test-E12Right $targetSnapshot $delegate $row.Right)})
    }
} else {
    if ($DelegateIdentity) { throw 'DelegateIdentity applies only to MailboxDelegates mode.' }
    if ($AllMailboxes -and $MailboxIdentity) { throw 'Use MailboxIdentity or AllMailboxes, not both.' }
    $source=Get-E12Recipient $SourceIdentity
    $destination=Get-E12Recipient $DestinationIdentity
    if ($source.RecipientTypeDetails -ne 'UserMailbox' -or $destination.RecipientTypeDetails -ne 'UserMailbox') { throw 'UserAccess requires two user mailboxes.' }
    if ((Get-E12Key $source) -eq (Get-E12Key $destination)) { throw 'Source and destination must differ.' }
    if (-not $AllMailboxes -and -not $MailboxIdentity) {
        $choice=Read-E12Required '' 'Mailbox SMTP addresses, comma-separated, or ALL for tenant-wide scan'
        if ($choice -ceq 'ALL') { $AllMailboxes=$true } else { $MailboxIdentity=@($choice -split ',' | ForEach-Object { $_.Trim() }) }
    }
    $mailboxes=if ($AllMailboxes) {
        Write-Host 'Scanning direct permissions on all user/shared mailboxes; this may take time.'
        @(Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited -ErrorAction Stop)
    } else { @(foreach ($id in $MailboxIdentity) { Get-E12Mailbox $id }) }
    foreach ($mailbox in @($mailboxes | Sort-Object PrimarySmtpAddress -Unique)) {
        $snapshot=Get-E12Snapshot $mailbox
        $backups.Add($snapshot)
        foreach ($right in @($Rights | Select-Object -Unique)) {
            if (-not (Test-E12Right $snapshot $source $right)) { continue }
            if ((Get-E12Key $mailbox) -eq (Get-E12Key $destination)) { continue }
            if ($mailbox.IsDirSynced) { throw "Synchronized target $($mailbox.PrimarySmtpAddress): use hybrid management." }
            if ((Test-E12Right $snapshot $source $right -Denied) -or (Test-E12Right $snapshot $destination $right -Denied)) { throw 'Conflicting deny ACL: review manually.' }
            $plan.Add([pscustomobject]@{Mailbox=[string]$mailbox.PrimarySmtpAddress;Delegate=[string]$destination.PrimarySmtpAddress;Recipient=$destination;Right=$right;Existing=(Test-E12Right $snapshot $destination $right)})
        }
    }
}
$items=@($plan.ToArray() | Sort-Object Mailbox,Delegate,Right -Unique)
$items | Select-Object Mailbox,Delegate,Right,Existing | Format-Table -AutoSize | Out-Host
Write-Host "Mode=$Mode; additive only. AutoMapping for NEW FullAccess grants=$AutoMapping. Source grants are never removed."
$changes=@($items | Where-Object { -not $_.Existing })
$approved=$true
if ($changes.Count -and -not $WhatIfPreference) {
    $approved=Confirm-M365Action -Action "Copy selected direct permissions ($Mode); AutoMapping=$AutoMapping" -Target @($changes | ForEach-Object { "$($_.Mailbox): $($_.Delegate) [$($_.Right)]" }) -Impact High
}
$backedUp=$false
$results=@(foreach ($item in $items) {
    $status='AlreadyPresent'; $errorText=''; $mutationApplied=$false
    if (-not $item.Existing) {
        if (-not $approved) { $status='Cancelled' }
        elseif ($PSCmdlet.ShouldProcess($item.Mailbox,"Add $($item.Right) for $($item.Delegate); AutoMapping=$AutoMapping")) {
            if (-not $backedUp) { $null=Save-E12Backup @($backups.ToArray()) 'CopyMailboxPermissions-Before'; $backedUp=$true }
            try {
                $current=Get-E12Snapshot (Get-E12Mailbox $item.Mailbox -Writable)
                if (Test-E12Right $current $item.Recipient $item.Right -Denied) { throw 'A deny entry is now present; refusing grant.' }
                if (Test-E12Right $current $item.Recipient $item.Right) { $status='AlreadyPresent' }
                else {
                    Set-E12Right $item.Mailbox $item.Recipient $item.Right Add -AutoMapping $AutoMapping
                    $mutationApplied=$true
                    $status=if (Test-E12Verified $item.Mailbox $item.Recipient $item.Right $true) {'Verified'} else {'AppliedUnverified'}
                    Write-M365Log -Message "$status`: add $($item.Right) for $($item.Delegate) on $($item.Mailbox)" -Level Change
                }
            } catch { $status=if ($mutationApplied) {'AppliedUnverified'} else {'Failed'}; $errorText=$_.Exception.Message; Write-M365Log -Message $errorText -Level Error }
        } else { $status=if ($WhatIfPreference) {'WhatIf'} else {'Declined'} }
    }
    [pscustomobject]@{Mailbox=$item.Mailbox;Delegate=$item.Delegate;Right=$item.Right;Result=$status;Error=$errorText}
})
Write-EX17Results $results 'CopyMailboxPermissions' -PassThru:$PassThru
