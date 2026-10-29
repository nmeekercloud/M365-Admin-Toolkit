@{
 Id='users.invoke-bulkusermanagement'
 Name='Bulk User Management'
 Description='CSV: update profile, enable or disable existing cloud users'
 Script='Invoke-BulkUserManagement.ps1'
 Order=40
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
