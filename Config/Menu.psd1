@{
    # Menu definitions only. A task is runnable only when its script exists.
    # Every implemented task must validate its own services/scopes.
    Categories = @(
        @{
            Key = '1'
            Name = 'User Management'
            Folder = 'Users'
            Items = @(
                @{ Name = 'Create New User'; Script = 'New-User.ps1'; Services = @('Graph'); Description = 'Create a user, assign licenses and groups' }
                @{ Name = 'Disable / Offboard User'; Script = 'Disable-User.ps1'; Services = @('Graph'); Description = 'Block sign-in, revoke sessions, and offboard' }
                @{ Name = 'Copy User Access'; Script = 'Copy-UserAccess.ps1'; Services = @('Graph'); Description = 'Copy selected groups and access' }
                @{ Name = 'Bulk User Management'; Script = 'Invoke-BulkUserManagement.ps1'; Services = @('Graph'); Description = 'CSV-driven user changes' }
            )
        }
        @{
            Key = '2'
            Name = 'Group Management'
            Folder = 'Groups'
            Items = @(
                @{ Name = 'List Groups and Group Types'; Script = 'Get-GroupList.ps1'; Services = @('Graph'); Description = 'List/search groups and show group type and membership mode' }
                @{ Name = 'View Group Members'; Script = 'Get-GroupMembers.ps1'; Services = @('Graph'); Description = 'Display direct members of a selected group; offer CSV export' }
                @{ Name = 'Copy Group Memberships'; Script = 'Copy-GroupMemberships.ps1'; Services = @('Graph'); Description = 'Copy memberships from one user to another' }
                @{ Name = 'Bulk Add Group Members'; Script = 'Add-BulkGroupMember.ps1'; Services = @('Graph'); Description = 'Add group members from CSV' }
                @{ Name = 'Export Group Memberships'; Script = 'Export-GroupMemberships.ps1'; Services = @('Graph'); Description = 'Export groups and their members' }
            )
        }
        @{
            Key = '3'
            Name = 'SharePoint Administration'
            Folder = 'SharePoint'
            Items = @(
                @{ Name = 'View / Export Site Access'; Script = 'Export-SharePointStaffAccess.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Report access to selected sites or all sites; state report scope' }
                @{ Name = 'Copy User SharePoint Group Memberships'; Script = 'Copy-SitePermissions.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Planned scope: add destination user to selected source-user SharePoint groups; preview first; not a full permission clone' }
                @{ Name = 'Bulk Grant Site Access'; Script = 'Grant-BulkSiteAccess.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Grant selected site access from CSV' }
                @{ Name = 'External Sharing Configuration Report'; Script = 'Get-SharePointExternalSharingConfig.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Selected sites or all sites; sharing settings, not proof of actual sharing' }
                @{ Name = 'External Access and Sharing Report'; Script = 'Get-SharePointExternalAccessReport.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Selected sites or all sites; discovered external access and links; flag coverage gaps' }
                @{ Name = 'All Access and Sharing Report'; Script = 'Get-SharePointAccessReport.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Internal and external access; selected sites or all sites; explicit scan scope' }
                @{ Name = 'Site Storage Report'; Script = 'Get-SharePointStorageReport.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Selected sites or all sites; storage used, quota, utilization, and CSV export' }
            )
        }
        @{
            Key = '4'
            Name = 'OneDrive Administration'
            Folder = 'OneDrive'
            Items = @(
                @{ Name = 'Archive / Back Up OneDrive'; Script = 'Backup-OneDrive.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Preserve a departing user''s OneDrive' }
                @{ Name = 'Manage OneDrive Permissions / Site Administrators'; Script = 'Set-OneDrivePermissions.ps1'; Services = @('Graph', 'SharePoint'); Description = 'View/add/remove selected access; distinguish site collection administrators' }
                @{ Name = 'Create OneDrive File / Folder Sharing Link'; Script = 'New-OneDriveSharingLink.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Select content and supported link settings; preview and confirm' }
                @{ Name = 'View OneDrive Storage'; Script = 'Get-OneDriveStorage.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Select a user; show used space, quota, and remaining space' }
                @{ Name = 'View OneDrive Access / Permissions'; Script = 'Get-OneDrivePermissions.ps1'; Services = @('Graph', 'SharePoint'); Description = 'Select a user; list administrators and access; identify report scope' }
            )
        }
        @{
            Key = '5'
            Name = 'Exchange Online'
            Folder = 'Exchange'
            Items = @(
                @{ Name = 'Copy Mailbox Permissions'; Script = 'Copy-MailboxPermissions.ps1'; Services = @('ExchangeOnline'); Description = 'Copy selected Full Access / Send As / Send on Behalf permissions' }
                @{ Name = 'Shared Mailbox Management'; Script = 'Invoke-SharedMailboxManagement.ps1'; Services = @('ExchangeOnline'); Description = 'Create/convert shared mailboxes and manage access' }
                @{ Name = 'Search Inbox Rules'; Script = 'Search-InboxRules.ps1'; Services = @('ExchangeOnline'); Description = 'Find forwarding and suspicious mailbox inbox rules' }
                @{ Name = 'Message Trace'; Script = 'Get-MessageTraceReport.ps1'; Services = @('ExchangeOnline'); Description = 'Trace message delivery' }
                @{ Name = 'View / Manage Mailbox Delegates (User or Shared)'; Script = 'Set-MailboxDelegates.ps1'; Services = @('ExchangeOnline'); Description = 'View/add/remove Full Access, Send As, and Send on Behalf' }
                @{ Name = 'View / Manage Automatic Replies'; Script = 'Set-MailboxAutoReply.ps1'; Services = @('ExchangeOnline'); Description = 'View, enable, disable, schedule, and edit automatic replies' }
                @{ Name = 'View / Manage Email Forwarding'; Script = 'Set-MailboxForwarding.ps1'; Services = @('ExchangeOnline'); Description = 'View/set/remove mailbox forwarding; distinguish inbox-rule forwarding' }
                @{ Name = 'List Mail Flow / Transport Rules'; Script = 'Get-MailFlowRules.ps1'; Services = @('ExchangeOnline'); Description = 'List tenant-wide Exchange admin rules and view details; not inbox rules' }
            )
        }
        @{
            Key = '6'
            Name = 'Reports & Auditing'
            Folder = 'Reports'
            Items = @(
                @{ Name = 'License Report'; Script = 'Get-LicenseReport.ps1'; Services = @('Graph'); Description = 'License inventory and assignments' }
                @{ Name = 'User Access Report'; Script = 'Get-UserAccessReport.ps1'; Services = @('Graph'); Description = 'Report discovered user access with scope clearly stated' }
                @{ Name = 'Contact Export'; Script = 'Export-ContactList.ps1'; Services = @('Graph'); Description = 'Export users with email as a contact list' }
            )
        }
        @{
            Key = 'T'
            Name = 'Tenant Options'
            Folder = 'Tenant'
            Items = @(
                @{ Name = 'View Tenant Details / Tenant ID'; Script = 'Get-TenantDetails.ps1'; Services = @('Graph'); Description = 'Display tenant name and tenant ID; offer CSV export' }
                @{ Name = 'List Tenant Domains'; Script = 'Get-TenantDomains.ps1'; Services = @('Graph'); Description = 'List verified domains; identify initial and default domains; offer CSV export' }
            )
        }
    )
}
