@{
 Id='exchange.set-mailboxforwarding'
 Name='View / Manage Email Forwarding'
 Description='View/set/remove mailbox forwarding; distinguish inbox-rule forwarding'
 Script='Set-MailboxForwarding.ps1'
 Order=70
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
