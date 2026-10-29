@{
 Id='sharepoint.hub-associated-sites'
 Name='Hub Navigation Site Discovery'
 Description='Discover sites from the main hub menus and linked hub menus; read-only with optional CSV export'
 Script='Get-HubAssociatedSites.ps1'
 Order=80
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
