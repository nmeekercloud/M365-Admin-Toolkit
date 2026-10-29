@{
 Id='users.new-user'
 Name='Create New User'
 Description='Create cloud user; optional licenses and supported groups'
 Script='New-User.ps1'
 Order=10
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
