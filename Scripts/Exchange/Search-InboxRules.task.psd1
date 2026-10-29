@{
 Id='exchange.search-inboxrules'
 Name='Search Inbox Rules'
 Description='Read-only search inbox rules; CSV export and explicit coverage'
 Script='Search-InboxRules.ps1'
 Order=30
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@()
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
