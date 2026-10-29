@{
 Id='users.remove-licenses'
 Name='Remove Selected User Licenses'
 Description='Direct assignments only; preservation review and Exchange safeguards'
 Script='Remove-UserLicenses.ps1'
 Order=60
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','LicenseAssignment.ReadWrite.All')
 AccessMode='Changes'
 PermissionReview='Unreviewed'
}
