@{
 Id='users.copy-useraccess'
 Name='Copy User Access'
 Description='Copy selected supported direct groups only (not all access)'
 Script='Copy-UserAccess.ps1'
 Order=30
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
