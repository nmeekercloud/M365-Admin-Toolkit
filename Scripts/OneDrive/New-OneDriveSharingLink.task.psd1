@{
 Id='onedrive.new-onedrivesharinglink'
 Name='Create OneDrive File / Folder Sharing Link'
 Description='Existing item; Organization/Anyone View/Edit links with expiry; preview and confirm'
 Script='New-OneDriveSharingLink.ps1'
 Order=30
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('User.Read.All','Sites.Read.All','Files.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
