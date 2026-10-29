@{
 Id='exchange.set-mailboxdelegates'
 Name='View / Manage Mailbox Delegates (User or Shared)'
 Description='View/add/remove Full Access, Send As, and Send on Behalf'
 Script='Set-MailboxDelegates.ps1'
 Order=50
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
