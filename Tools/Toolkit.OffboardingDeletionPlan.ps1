# Eligibility and optional deletion planning, activated by phase 7B.
function Get-WF7ADeletionDecision {
 [CmdletBinding()]
 param([string[]]$Actions,[hashtable]$MailboxPlans=@{},
       [ValidateSet('None','UserMailbox','SharedMailbox','Unknown','Unsupported')][string]$MailboxState='Unknown',
       [bool]$HasForwarding=$false)
 $eligible=$false; $reason='Mailbox state could not be verified; account retained'
 if ('ConvertShared' -in $Actions) { $reason='Account retained for shared mailbox conversion; block sign-in and revoke sessions included' }
 elseif ($MailboxState -eq 'SharedMailbox') { $reason='Account retained for existing shared mailbox' }
 elseif ($MailboxPlans.ContainsKey('Forwarding') -and $MailboxPlans['Forwarding'].Settings.Operation -eq 'Set') { $reason='Account retained for planned mailbox forwarding' }
 elseif ($HasForwarding) { $reason='Account retained for existing mailbox forwarding; no deletion override in this phase' }
 elseif ($MailboxState -in @('None','UserMailbox')) { $eligible=$true; $reason='No shared-mailbox or forwarding exclusion found at planning time; not authorization or proof of preservation' }
 elseif ($MailboxState -eq 'Unsupported') { $reason='Unsupported Exchange recipient type; account retained pending manual review' }
 [pscustomobject]@{EligibleForPrompt=$eligible;Reason=$reason;Requested=$false;Executable=$false;Phase='7A'}
}
function Read-WF7ADeletionIntent {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object]$Decision)
 if (-not $Decision.EligibleForPrompt) { return $Decision }
 Write-Host 'Optional account deletion: Yes adds a REAL deletion step to the final approval plan. Review data preservation independently. No permanent-purge option.' -ForegroundColor Yellow
 while ($true) {
  $answer=([string](Read-Host 'Delete this user after successful offboarding? [y/N]; C cancels workflow')).Trim()
  if (-not $answer -or $answer -imatch '^n(o)?$') { $Decision.Requested=$false; return $Decision }
  if ($answer -imatch '^y(es)?$') { $Decision.Requested=$true; return $Decision }
  if ($answer -imatch '^c(ancel)?$') { throw 'Offboarding cancelled during deletion planning. No workflow steps executed.' }
  Write-Host 'Enter Y, N, or C.' -ForegroundColor Yellow
 }
}
function Get-WF7AMailboxSnapshot {
 [CmdletBinding()]
 param([Parameter(Mandatory)][System.Collections.IDictionary]$User,[Parameter(Mandatory)][object]$Tenant)
 if (-not $Tenant.TenantId) { throw 'Verified tenant required.' }
 Assert-UMCloudMember -User $User -Tenant $Tenant
 $id=[guid]::Empty
 if (-not [guid]::TryParse([string]$User['id'],[ref]$id)) { throw 'Invalid target object ID.' }
 $null=Assert-M365Connection -Service @('Graph','ExchangeOnline') -GraphScopes @('User.Read.All') -TaskName 'Read mailbox retention exclusions for offboarding plan' -TaskId 'users.disable-user'
 # A successful zero-result lookup is distinct from a lookup exception.
 $recipients=@(Get-Recipient -Filter ("ExternalDirectoryObjectId -eq '"+$id.ToString()+"'") -ResultSize Unlimited -ErrorAction Stop)
 if ($recipients.Count -eq 0) { return [pscustomobject]@{State='None';HasForwarding=$false} }
 if ($recipients.Count -ne 1 -or [string]$recipients[0].ExternalDirectoryObjectId -ine [string]$User['id']) { throw 'Ambiguous or mismatched Exchange recipient.' }
 $type=[string]$recipients[0].RecipientTypeDetails
 if ($type -notin @('UserMailbox','SharedMailbox')) { return [pscustomobject]@{State='Unsupported';HasForwarding=$false} }
 $target=Get-WFMailboxTarget -Identity ([string]$User['id']) -Tenant $Tenant
 if ([string]$target.User['id'] -ine [string]$User['id']) { throw 'Mailbox snapshot identity mismatch.' }
 $mailbox=$target.Mailbox
 foreach ($property in @('ForwardingAddress','ForwardingSmtpAddress','RecipientTypeDetails')) {
  if (-not $mailbox.PSObject.Properties[$property]) { throw ('Incomplete mailbox metadata: '+$property) }
 }
 if ([string]$mailbox.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox')) { throw 'Mailbox type changed during lookup.' }
 [pscustomobject]@{State=[string]$mailbox.RecipientTypeDetails;HasForwarding=[bool]($mailbox.ForwardingAddress -or $mailbox.ForwardingSmtpAddress)}
}
