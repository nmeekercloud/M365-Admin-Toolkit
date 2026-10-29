@{
 Id='sharepoint.get-sharepointstoragereport'
 Name='Site Storage Report'
 Description='Selected/all sites; service-reported usage, quota, utilization and CSV with explicit metric gaps'
 Script='Get-SharePointStorageReport.ps1'
 Order=70
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
