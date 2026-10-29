@{
 Id='reports.get-licensereport'
 Name='License Report'
 Description='Read-only license report; scoped CSV and coverage export'
 Script='Get-LicenseReport.ps1'
 Order=10
 Status='Ready'
 Services=@('Graph')
 GraphScopes=@('User.Read.All','LicenseAssignment.Read.All')
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
