#Requires -Version 7.4
# Shared helpers; dot-sourcing does not connect or change tenant data.
function Initialize-E12 {
    if (-not (Get-Module M365Toolkit.Core)) {
        Import-Module (Join-Path $PSScriptRoot '../Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
    }
    $null=Assert-M365Connection -Service ExchangeOnline
}
function Read-E12Required {
    param([string]$Value,[string]$Prompt)
    if (-not $Value) { $Value=([string](Read-Host $Prompt)).Trim() }
    if (-not $Value) { throw 'Cancelled: required input was blank.' }
    return $Value.Trim()
}
function Get-E12Key {
    param([Parameter(Mandatory)]$Recipient)
    foreach ($property in @('ExternalDirectoryObjectId','Guid','DistinguishedName','PrimarySmtpAddress')) {
        $value=[string]$Recipient.$property
        if ($value -and $value -ne ([guid]::Empty.ToString())) { return $value.ToLowerInvariant() }
    }
    throw 'Recipient has no stable identity.'
}
function Get-E12Recipient {
    param([Parameter(Mandatory)][string]$Identity)
    $r=Get-Recipient -Identity $Identity -ErrorAction Stop
    if ([string]$r.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox','MailUser','MailUniversalSecurityGroup')) { throw "Unsupported delegate type: $($r.RecipientTypeDetails)." }
    if (-not [string]$r.PrimarySmtpAddress) { throw 'Delegate has no primary SMTP address.' }
    return $r
}
function Get-E12Mailbox {
    param([Parameter(Mandatory)][string]$Identity,[switch]$Writable)
    $m=Get-Mailbox -Identity $Identity -ErrorAction Stop
    if ([string]$m.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox')) { throw 'Only user/shared mailboxes are supported.' }
    if ($Writable -and $m.IsDirSynced) { throw 'Synchronized mailbox: use your authoritative hybrid management process.' }
    return $m
}
function Get-E12Snapshot {
    param([Parameter(Mandatory)]$Mailbox)
    $identity=[string]$Mailbox.PrimarySmtpAddress
    $full=@(Get-MailboxPermission -Identity $identity -ErrorAction Stop)
    $send=@(Get-RecipientPermission -Identity $identity -ErrorAction Stop)
    $rows=[System.Collections.Generic.List[object]]::new()
    $entries=@(
        foreach ($p in $full) {
            if (-not $p.IsInherited -and @($p.AccessRights) -contains 'FullAccess') {
                [pscustomobject]@{Principal=[string]$p.User;Right='FullAccess';Denied=[bool]$p.Deny}
            }
        }
        foreach ($p in $send) {
            if (-not $p.IsInherited -and @($p.AccessRights) -contains 'SendAs') {
                [pscustomobject]@{Principal=[string]$p.Trustee;Right='SendAs';Denied=([string]$p.AccessControlType -eq 'Deny')}
            }
        }
        foreach ($p in @($Mailbox.GrantSendOnBehalfTo)) {
            [pscustomobject]@{Principal=[string]$p;Right='SendOnBehalf';Denied=$false}
        }
    )
    foreach ($e in $entries) {
        if ($e.Principal -match '^(NT AUTHORITY\\SELF|S-1-5-10)$') { continue }
        try { $r=Get-Recipient -Identity $e.Principal -ErrorAction Stop }
        catch { throw "Cannot resolve $($e.Right) principal '$($e.Principal)' on $identity. Review manually before retrying. $($_.Exception.Message)" }
        $rows.Add([pscustomobject]@{Key=Get-E12Key $r;Delegate=[string]$r.PrimarySmtpAddress;Recipient=$r;Right=$e.Right;Denied=$e.Denied})
    }
    [pscustomobject]@{Mailbox=$identity;MailboxObject=$Mailbox;FullAccess=$full;SendAs=$send;Rows=@($rows.ToArray())}
}
function Test-E12Right {
    param($Snapshot,$Delegate,[string]$Right,[switch]$Denied)
    $key=Get-E12Key $Delegate
    return @($Snapshot.Rows | Where-Object { $_.Key -eq $key -and $_.Right -eq $Right -and $_.Denied -eq [bool]$Denied }).Count -gt 0
}
function Save-E12Backup {
    param($Value,[string]$Label)
    $path=Get-M365OutputPath -Type Backups -FileName ($Label+'-'+[guid]::NewGuid().ToString('N')+'.json')
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
    Write-M365Log -Message "Pre-change snapshot: $path" -Level Info
    return $path
}
function Set-E12Right {
    param([string]$Mailbox,$Delegate,[ValidateSet('FullAccess','SendAs','SendOnBehalf')][string]$Right,
          [ValidateSet('Add','Remove')][string]$Operation,[bool]$AutoMapping=$true)
    $smtp=[string]$Delegate.PrimarySmtpAddress
    switch ($Right) {
        'FullAccess' {
            if ($Operation -eq 'Add') { $null=Add-MailboxPermission -Identity $Mailbox -User $smtp -AccessRights FullAccess -InheritanceType All -AutoMapping $AutoMapping -Confirm:$false -ErrorAction Stop }
            else { $null=Remove-MailboxPermission -Identity $Mailbox -User $smtp -AccessRights FullAccess -InheritanceType All -Confirm:$false -ErrorAction Stop }
        }
        'SendAs' {
            if ($Operation -eq 'Add') { $null=Add-RecipientPermission -Identity $Mailbox -Trustee $smtp -AccessRights SendAs -Confirm:$false -ErrorAction Stop }
            else { $null=Remove-RecipientPermission -Identity $Mailbox -Trustee $smtp -AccessRights SendAs -Confirm:$false -ErrorAction Stop }
        }
        'SendOnBehalf' {
            $delta=if ($Operation -eq 'Add') { @{Add=$smtp} } else { @{Remove=$smtp} }
            Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo $delta -Confirm:$false -ErrorAction Stop
        }
    }
}
function Test-E12Verified {
    param([string]$Mailbox,$Delegate,[string]$Right,[bool]$Expected)
    for ($attempt=0; $attempt -lt 3; $attempt++) {
        if ($attempt) { Start-Sleep -Seconds 2 }
        $snapshot=Get-E12Snapshot (Get-E12Mailbox $Mailbox)
        if ((Test-E12Right $snapshot $Delegate $Right) -eq $Expected) { return $true }
    }
    return $false
}
function Write-E12Results {
    param([object[]]$Results,[string]$Label,[switch]$PassThru)
    if (@($Results).Count) {
        $Results | Format-Table Mailbox,Delegate,Right,Result,Error -AutoSize -Wrap | Out-Host
        $path=Get-M365OutputPath -Type Reports -FileName ($Label+'-'+[guid]::NewGuid().ToString('N')+'.csv')
        $Results | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8
        Write-M365Log -Message "Results: $path" -Level Info
        if ($PassThru) { $Results }
    } else { Write-Host 'No matching permissions / no changes needed.' }
}
