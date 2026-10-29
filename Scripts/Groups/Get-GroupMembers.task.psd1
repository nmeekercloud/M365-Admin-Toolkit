@{
 Id='groups.get-groupmembers'
 Name='View Group Members'
 Description='View direct members of a selected group; optional CSV export'
 Script='Get-GroupMembers.ps1'
 Order=20
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('Group.Read.All','User.ReadBasic.All')
 AccessMode='ReadOnly'
 PermissionReview='Reviewed'
}
