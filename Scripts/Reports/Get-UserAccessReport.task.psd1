@{
 Id='reports.get-useraccessreport'
 Name='User Details'
 Description="Export selected users' profiles, licenses, group memberships/ownership, and direct active Entra roles. Excludes mailbox and file permissions."
 Script='Get-UserAccessReport.ps1'
 Order=20
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','Group.Read.All','LicenseAssignment.Read.All','RoleManagement.Read.Directory')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
