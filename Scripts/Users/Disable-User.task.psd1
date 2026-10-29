@{
 Id='users.disable-user'
 Name='Disable / Offboard / Delete User'
 Description='Guided questions for access, mailbox, licenses and optional account deletion'
 Script='Disable-User.ps1'
 Order=20
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
