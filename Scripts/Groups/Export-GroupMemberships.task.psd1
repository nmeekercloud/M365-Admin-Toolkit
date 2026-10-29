@{
 Id='groups.export-groupmemberships'
 Name='Export Group Memberships'
 Description='Export groups and direct members with explicit coverage/status reports'
 Script='Export-GroupMemberships.ps1'
 Order=50
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('Group.Read.All','User.ReadBasic.All')
 AccessMode='ReadOnly'
 PermissionReview='Reviewed'
}
