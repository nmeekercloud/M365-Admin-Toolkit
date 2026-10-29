@{
 Id='groups.get-grouplist'
 Name='List Groups and Group Types'
 Description='Search/list groups, inspect type and membership, optional CSV export'
 Script='Get-GroupList.ps1'
 Order=10
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('Group.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Reviewed'
}
