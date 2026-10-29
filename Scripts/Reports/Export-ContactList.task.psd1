@{
 Id='reports.export-contactlist'
 Name='All Users Export'
 Description='Export all current directory users, including licensed/unlicensed, enabled/disabled, and guests; includes users without email'
 Script='Export-ContactList.ps1'
 Order=30
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
