@{
 Id='sharepoint.copy-sitepermissions'
 Name='Copy User SharePoint Group Memberships'
 Description='Add selected direct SharePoint group memberships; not a full permission clone'
 Script='Copy-SitePermissions.ps1'
 Order=20
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All','User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
