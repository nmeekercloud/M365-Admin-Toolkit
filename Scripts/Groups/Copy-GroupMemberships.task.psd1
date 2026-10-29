@{
 Id='groups.copy-groupmemberships'
 Name='Copy Group Memberships'
 Description='Add selected supported direct memberships from source user to target'
 Script='Copy-GroupMemberships.ps1'
 Order=30
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
