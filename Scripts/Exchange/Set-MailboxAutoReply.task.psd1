@{
 Id='exchange.set-mailboxautoreply'
 Name='View / Manage Automatic Replies'
 Description='View, enable, disable, schedule, and edit automatic replies'
 Script='Set-MailboxAutoReply.ps1'
 Order=60
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
