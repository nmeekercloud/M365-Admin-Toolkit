@{
    # Generic connection presets only. No tenant identifiers or credentials.
    # Broad coverage for intended toolkit areas, NOT every Microsoft API.
    Administration = @{
        Services = @('Graph','ExchangeOnline','SharePoint')
        GraphScopes = @(
            'User.Read'
            'User.ReadWrite.All'
            'Group.ReadWrite.All'
            'GroupMember.ReadWrite.All'
            'Organization.Read.All'
            'Domain.Read.All'
            'Directory.Read.All'
            'LicenseAssignment.ReadWrite.All'
            'Sites.FullControl.All'
            'Files.ReadWrite.All'
            'Application.Read.All'
            'AuditLog.Read.All'
            'Reports.Read.All'
            'DeviceManagementManagedDevices.ReadWrite.All'
            'DeviceManagementManagedDevices.PrivilegedOperations.All'
            'DeviceManagementApps.ReadWrite.All'
            'DeviceManagementConfiguration.ReadWrite.All'
            'DeviceManagementServiceConfig.ReadWrite.All'
        )
    }
    Reporting = @{
        Services = @('Graph','ExchangeOnline','SharePoint')
        GraphScopes = @(
            'User.Read'
            'User.Read.All'
            'Group.Read.All'
            'GroupMember.Read.All'
            'Organization.Read.All'
            'Domain.Read.All'
            'Directory.Read.All'
            'LicenseAssignment.Read.All'
            'Sites.Read.All'
            'Files.Read.All'
            'Application.Read.All'
            'AuditLog.Read.All'
            'Reports.Read.All'
            'DeviceManagementManagedDevices.Read.All'
            'DeviceManagementApps.Read.All'
            'DeviceManagementConfiguration.Read.All'
            'DeviceManagementServiceConfig.Read.All'
        )
    }
}
