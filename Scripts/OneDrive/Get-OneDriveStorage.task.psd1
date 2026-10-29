@{
 Id='onedrive.get-onedrivestorage'
 Name='View OneDrive Storage'
 Description='Existing user OneDrive: used space, quota, remaining, utilization and optional CSV'
 Script='Get-OneDriveStorage.ps1'
 Order=40
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('User.Read.All','Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
