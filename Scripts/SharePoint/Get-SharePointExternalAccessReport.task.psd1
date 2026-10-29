@{
 Id='sharepoint.get-sharepointexternalaccessreport'
 Name='External Access and Sharing Report'
 Description='Guest indicators, uncertain external candidates and discovered links; explicit scope/gaps'
 Script='Get-SharePointExternalAccessReport.ps1'
 Order=50
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All','User.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
