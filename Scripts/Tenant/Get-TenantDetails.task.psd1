@{
 Id='tenant.get-tenantdetails'
 Name='View Tenant Details / Tenant ID'
 Description='Show verified tenant identity and connection details. Console only.'
 Script='Get-TenantDetails.ps1'
 Order=10
 Status='Ready'
 AccessMode='ReadOnly'
 PermissionReview='Reviewed'
 Services=@('Graph')
 GraphScopes=@()
}
