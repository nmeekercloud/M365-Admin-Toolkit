@{
 Id='sharepoint.get-sharepointexternalsharingconfig'
 Name='External Sharing Configuration Report'
 Description='Tenant/site sharing settings only; explicitly report unavailable fields and coverage'
 Script='Get-SharePointExternalSharingConfig.ps1'
 Order=40
 Status='Ready'
 Services=@('Graph','SharePoint')
 GraphScopes=@('Sites.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
