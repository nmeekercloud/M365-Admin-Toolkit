@{
 Id='exchange.convert-shared'
 Name='Convert Existing Mailbox to Shared'
 Description='Convert a blocked cloud user; no deletion or automatic license removal'
 Script='ConvertTo-SharedMailbox.ps1'
 Order=25
 Status='Ready'
 Services=@('Graph','ExchangeOnline')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
