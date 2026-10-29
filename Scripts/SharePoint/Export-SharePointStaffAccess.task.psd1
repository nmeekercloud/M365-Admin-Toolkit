@{
 Id='sharepoint.export-sharepointstaffaccess'
 Name='View / Export Site Access'
 Description='Site administrators and root-web grants; direct SharePoint group members; explicit exclusions'
 Script='Export-SharePointStaffAccess.ps1'
 Order=10
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
