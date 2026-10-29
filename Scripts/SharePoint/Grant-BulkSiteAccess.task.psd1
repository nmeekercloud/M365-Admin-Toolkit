@{
 Id='sharepoint.grant-bulksiteaccess'
 Name='Bulk Grant Site Access'
 Description='Validate CSV and add users to explicit existing SharePoint groups; no permission clone'
 Script='Grant-BulkSiteAccess.ps1'
 Order=30
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All','User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
