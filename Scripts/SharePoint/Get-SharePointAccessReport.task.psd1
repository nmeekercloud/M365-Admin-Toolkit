@{
 Id='sharepoint.get-sharepointaccessreport'
 Name='All Access and Sharing Report'
 Description='Internal/external grant paths and discovered links; explicit scope, caps and gaps'
 Script='Get-SharePointAccessReport.ps1'
 Order=60
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All','User.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
