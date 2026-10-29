@{
 Users=@{
  Title='Bulk User Updates'
  Script='Scripts/Users/Invoke-BulkUserManagement.ps1'
  Template='Templates/CSV/Bulk-User-Edits-Template.csv'
  Columns=@('Action','UserPrincipalName','DisplayName','Department','JobTitle','OfficeLocation')
  Help=@('Action: Update, Enable, or Disable. Blank profile cells leave values unchanged.','Enable/Disable rows must leave all profile fields blank. No bulk create/delete/password changes.')
 }
 GroupMembers=@{
  Title='Bulk Add Group Members'
  Script='Scripts/Groups/Add-BulkGroupMember.ps1'
  Template='Templates/CSV/Bulk-Group-Members-Template.csv'
  Columns=@('GroupId','UserPrincipalName')
  Help=@('GroupId is the Entra group object GUID, not a name. Use the user canonical sign-in UPN.','One group/user pair per row. Only supported static groups and eligible tenant Member users are accepted.')
 }
 SharePointAccess=@{
  Title='Bulk Grant SharePoint Site Access'
  Script='Scripts/SharePoint/Grant-BulkSiteAccess.ps1'
  Template='Templates/CSV/Bulk-SharePoint-Access-Template.csv'
  Columns=@('SiteUrl','SharePointGroupId','UserPrincipalName')
  Help=@('SiteUrl is the site collection URL. SharePointGroupId is a positive SITE-LOCAL integer, not an Entra group GUID.','Use the user canonical sign-in UPN. Users must already resolve in the site. Owners are excluded; security-group principals are not supported.')
 }
}
