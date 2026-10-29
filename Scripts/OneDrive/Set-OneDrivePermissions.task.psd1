@{
 Id='onedrive.set-onedrivepermissions'
 Name='Manage OneDrive Permissions / Site Administrators'
 Description='Explicit secondary site-administrator add/remove; not file/folder sharing'
 Script='Set-OneDrivePermissions.ps1'
 Order=20
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('User.Read.All','Sites.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
