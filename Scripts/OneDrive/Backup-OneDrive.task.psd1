@{
 Id='onedrive.backup-onedrive'
 Name='Move OneDrive to SharePoint Archive'
 Description='Server-side move; destination verification and temporary admin cleanup'
 Script='Backup-OneDrive.ps1'
 Order=10
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('User.Read.All','Sites.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
