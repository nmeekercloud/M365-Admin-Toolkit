# Warning collection for approved Microsoft 365 account deletion.
function Get-WFAccountDeletionWarnings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$User,
          [Parameter(Mandatory)][object]$Tenant)
    Assert-UMCloudMember -User $User -Tenant $Tenant
    $codes=@(); $messages=@()
    try {
        $snapshot=Get-WF7AMailboxSnapshot -User $User -Tenant $Tenant
        switch ($snapshot.State) {
            'SharedMailbox' {
                $codes+='SharedMailbox'
                $messages+='This account anchors a shared mailbox. Deleting the account affects that mailbox; do not expect it to remain available.'
            }
            'Unknown' {
                $codes+='MailboxUnknown'
                $messages+='Mailbox impact could not be verified. Deletion will proceed only with explicit acceptance of this uncertainty.'
            }
            'Unsupported' {
                $codes+='RecipientOther'
                $messages+='Another Exchange recipient type is associated with this account. Its deletion impact has not been validated.'
            }
        }
        if ($snapshot.HasForwarding) {
            $codes+='Forwarding'
            $messages+='Mailbox forwarding is configured. Do not expect account-based forwarding to continue after deletion.'
        }
    }
    catch {
        $codes+='MailboxUnknown'
        $messages+=('Mailbox inspection failed: '+$_.Exception.Message+'. Exchange metadata is unavailable; this does not prove that no mailbox exists.')
    }
    try {
        $state=Invoke-UMGraph -Path ('/users/'+$User['id']+'?$select=id,assignedLicenses')
        $ids=@($state['assignedLicenses'] | ForEach-Object { [string]$_['skuId'] } | Sort-Object -Unique)
        if ($ids.Count) {
            $codes+='AssignedLicenses'
            $messages+=('Assigned license SKU IDs: '+($ids -join ', ')+'. Removing licenses separately is not a deletion prerequisite. Purchased subscription quantities are not changed by this task.')
        }
    }
    catch {
        $codes+='LicensesUnknown'
        $messages+=('Assigned licenses could not be inspected: '+$_.Exception.Message)
    }
    $messages+='Deleting the Microsoft Entra user affects Microsoft 365 access and associated services. This tool does not prove OneDrive, mailbox, archive, retention or compliance preservation. No permanent purge or automatic rollback is requested.'
    [pscustomobject]@{Codes=@($codes | Sort-Object -Unique);Messages=@($messages)}
}
