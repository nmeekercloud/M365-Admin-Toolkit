@{
 Id='users.block-access'
 Name='Block sign-in and revoke sessions'
 Description='Block new sign-ins and request session revocation for a cloud member'
 Script='Block-UserAccess.ps1'
 Order=50
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','User.EnableDisableAccount.All','User.RevokeSessions.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
