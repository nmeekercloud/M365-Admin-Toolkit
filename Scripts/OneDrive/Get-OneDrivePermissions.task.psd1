@{
 Id='onedrive.get-onedrivepermissions'
 Name='View OneDrive Access / Permissions'
 Description='Existing personal site; administrators and root-web access; explicit exclusions'
 Script='Get-OneDrivePermissions.ps1'
 Order=50
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('User.Read.All','Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
