@{
 Id='exchange.copy-mailboxpermissions'
 Name='Copy Mailbox Permissions'
 Description='Copy Mailbox Permissions: selected direct permissions; preview before changes'
 Script='Copy-MailboxPermissions.ps1'
 Order=10
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@()
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
