@{
 Id='groups.add-bulkgroupmember'
 Name='Bulk Add Group Members'
 Description='Validate and add supported direct user memberships from CSV'
 Script='Add-BulkGroupMember.ps1'
 Order=40
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
