#Requires -Version 7.4
# Isolated tests: helper functions + in-process fakes; no SDKs, connection or disk writes.
[CmdletBinding()]
param([string]$ToolkitPath=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $ToolkitPath 'Tools/Toolkit.Exchange12.ps1')
$script:Checks=0
function Assert-E12Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:Checks++
}
$script:Delegate=[pscustomobject]@{ExternalDirectoryObjectId='ABC';PrimarySmtpAddress='delegate@contoso.com';RecipientTypeDetails='UserMailbox'}
$script:Mailbox=[pscustomobject]@{PrimarySmtpAddress='shared@contoso.com';GrantSendOnBehalfTo=@();RecipientTypeDetails='SharedMailbox';IsDirSynced=$false}
$script:Captured=$null
$script:Full=@(); $script:Send=@(); $script:Unresolved=$false
function Get-Recipient { [CmdletBinding()]param($Identity) if ($script:Unresolved) { throw 'not found' }; return $script:Delegate }
function Get-Mailbox { [CmdletBinding()]param($Identity) return $script:Mailbox }
function Get-MailboxPermission { [CmdletBinding()]param($Identity) return $script:Full }
function Get-RecipientPermission { [CmdletBinding()]param($Identity) return $script:Send }
function Set-Mailbox { [CmdletBinding(SupportsShouldProcess)]param($Identity,$GrantSendOnBehalfTo) $script:Captured=@{Kind='SetMailbox';Identity=$Identity;Delta=$GrantSendOnBehalfTo} }
function Add-MailboxPermission { [CmdletBinding(SupportsShouldProcess)]param($Identity,$User,$AccessRights,$InheritanceType,$AutoMapping) $script:Captured=@{Kind='AddFull';Identity=$Identity;User=$User;Right=$AccessRights;Inheritance=$InheritanceType;AutoMapping=$AutoMapping} }
function Remove-MailboxPermission { [CmdletBinding(SupportsShouldProcess)]param($Identity,$User,$AccessRights,$InheritanceType) $script:Captured=@{Kind='RemoveFull';User=$User;Right=$AccessRights} }
function Add-RecipientPermission { [CmdletBinding(SupportsShouldProcess)]param($Identity,$Trustee,$AccessRights) $script:Captured=@{Kind='AddSendAs';Trustee=$Trustee;Right=$AccessRights} }
function Remove-RecipientPermission { [CmdletBinding(SupportsShouldProcess)]param($Identity,$Trustee,$AccessRights) $script:Captured=@{Kind='RemoveSendAs';Trustee=$Trustee;Right=$AccessRights} }
Assert-E12Test ((Get-E12Key $Delegate) -ceq 'abc') 'case-normalized directory identity'
Assert-E12Test ((Get-E12Key ([pscustomobject]@{PrimarySmtpAddress='USER@contoso.com'})) -ceq 'user@contoso.com') 'SMTP identity fallback'
$threw=$false; try { $null=Get-E12Key ([pscustomobject]@{}) } catch { $threw=$true }
Assert-E12Test $threw 'empty identities rejected'
$snapshot=[pscustomobject]@{Rows=@([pscustomobject]@{Key='abc';Right='FullAccess';Denied=$true})}
Assert-E12Test (-not (Test-E12Right $snapshot $Delegate FullAccess)) 'deny not counted as allow'
Assert-E12Test (Test-E12Right $snapshot $Delegate FullAccess -Denied) 'deny detected separately'
Assert-E12Test (-not (Test-E12Right $snapshot $Delegate SendAs -Denied)) 'rights remain separate'
$script:Full=@(
    [pscustomobject]@{User='NT AUTHORITY\SELF';AccessRights=@('FullAccess');IsInherited=$false;Deny=$false}
    [pscustomobject]@{User='inherited';AccessRights=@('FullAccess');IsInherited=$true;Deny=$false}
    [pscustomobject]@{User='delegate@contoso.com';AccessRights=@('FullAccess');IsInherited=$false;Deny=$false}
)
$snapshot=Get-E12Snapshot $Mailbox
Assert-E12Test (@($snapshot.Rows).Count -eq 1) 'SELF and inherited grants excluded'
Assert-E12Test ($snapshot.Rows[0].Right -eq 'FullAccess') 'direct FullAccess retained'
$script:Unresolved=$true; $threw=$false
try { $null=Get-E12Snapshot $Mailbox } catch { $threw=$true }
Assert-E12Test $threw 'unresolvable principals fail closed'
$script:Unresolved=$false
Set-E12Right 'shared@contoso.com' $Delegate SendOnBehalf Add
Assert-E12Test ($Captured.Delta.Add -eq 'delegate@contoso.com' -and $Captured.Delta.Count -eq 1) 'SendOnBehalf add preserves other delegates'
Set-E12Right 'shared@contoso.com' $Delegate SendOnBehalf Remove
Assert-E12Test ($Captured.Delta.Remove -eq 'delegate@contoso.com' -and $Captured.Delta.Count -eq 1) 'SendOnBehalf remove is a delta'
Set-E12Right 'shared@contoso.com' $Delegate FullAccess Add -AutoMapping $false
Assert-E12Test ($Captured.Kind -eq 'AddFull' -and $Captured.AutoMapping -eq $false -and $Captured.Inheritance -eq 'All') 'FullAccess AutoMapping argument'
Set-E12Right 'shared@contoso.com' $Delegate FullAccess Remove
Assert-E12Test ($Captured.Kind -eq 'RemoveFull' -and $Captured.User -eq 'delegate@contoso.com') 'FullAccess removal target'
Set-E12Right 'shared@contoso.com' $Delegate SendAs Add
Assert-E12Test ($Captured.Kind -eq 'AddSendAs' -and $Captured.Right -eq 'SendAs') 'SendAs add routes separately'
Set-E12Right 'shared@contoso.com' $Delegate SendAs Remove
Assert-E12Test ($Captured.Kind -eq 'RemoveSendAs') 'SendAs removal route'
$script:Mailbox.IsDirSynced=$true; $threw=$false
try { $null=Get-E12Mailbox 'shared@contoso.com' -Writable } catch { $threw=$true }
Assert-E12Test $threw 'synchronized mutation targets rejected'
$script:Mailbox.IsDirSynced=$false
foreach ($stem in @('Copy-MailboxPermissions','Invoke-SharedMailboxManagement')) {
    $manifest=Import-PowerShellDataFile (Join-Path $ToolkitPath "Scripts/Exchange/$stem.task.psd1")
    Assert-E12Test ($manifest.Status -eq 'Ready' -and @($manifest.GraphScopes).Count -eq 0 -and @($manifest.Services).Count -eq 1 -and $manifest.Services[0] -eq 'ExchangeOnline') "task metadata: $stem"
}
Write-Host "Exchange 1-2 isolated helper checks passed: $script:Checks. Fakes only; no tenant calls."
