@{
 Id='tenant.get-tenantdomains'
 Name='List Tenant Domains'
 Description='List verified and unverified tenant domains, default/initial flags, and optional CSV export.'
 Script='Get-TenantDomains.ps1'
 Order=20
 Status='Ready'
 AccessMode='ReadOnly'
 PermissionReview='Reviewed'
 Services=@('Graph')
 GraphScopes=@('Domain.Read.All')
}
