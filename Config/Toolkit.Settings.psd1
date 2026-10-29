@{
    # -------------------------------------------------------------------------
    # M365-Admin-Toolkit settings
    #
    # This file contains NO tenant-specific information and must stay that way.
    # To override values on your own machine without committing them, copy this
    # file to Toolkit.Settings.local.psd1 (ignored by git) and change only the
    # keys you need. Local values are merged over these defaults.
    # -------------------------------------------------------------------------

    ToolkitName              = 'Microsoft 365 Admin Toolkit'

    # ExchangeOnlineManagement 3.10.x requires PowerShell 7.6.0 or later.
    MinimumPowerShellVersion = '7.6.0'

    Paths                    = @{
        # Leave empty to use %LOCALAPPDATA%\M365AdminToolkit.
        # Logs, reports, and backups are always stored OUTSIDE the repository
        # so customer data can never be committed by accident.
        DataRoot = ''
    }

    Logging                  = @{
        RetentionDays = 30
        # Debug | Info | Success | Change | Warning | Error
        MinimumLevel  = 'Info'
    }

    Authentication           = @{
        # Always use device code sign-in instead of the browser / WAM window.
        UseDeviceCode             = $false
        # Legacy setting: automatic Windows 10 device-code selection is disabled
        # Device-code sign-in must be explicitly requested.
        Windows10UseDeviceCode    = $false
        # No device-code fallback; interactive failures are reported to the user.
        FallbackToDeviceCode      = $false
        # Pass -DisableWAM to Connect-ExchangeOnline. Turn on if Exchange
        # sign-in fails after Graph is connected in the same session.
        ExchangeDisableWAM        = $false
        # Refuse to continue when the signed-in account is a guest in the
        # target tenant (usually means the wrong account was picked).
        BlockGuestAccounts        = $true
    }

    Graph                    = @{
        # Scopes requested at every connection. User.Read is enough to read
        # the organization object used for tenant verification. Individual
        # scripts request additional scopes only when they need them.
        BaseScopes = @('User.Read')
    }

    SharePoint               = @{
        # Name used when the toolkit creates a PnP app registration in a tenant.
        # Existing apps are detected first (localhost redirect URI, or a name
        # containing 'PnP' or 'SharePoint') and offered for reuse.
        PnPApplicationName           = 'M365 Admin Toolkit (PnP)'
        # Delegated permissions granted to a newly created PnP app.
        GraphDelegatePermissions     = @('User.Read')
        SharePointDelegatePermissions = @('AllSites.FullControl')
        # Extra Graph scopes needed to find the SharePoint root site and
        # existing app registrations.
        GraphScopes                  = @('Sites.Read.All', 'Application.Read.All')
        # Remember the selected client ID per SharePoint URL on this computer
        # (Set-PnPManagedAppId). Stored locally by PnP, never in the repo.
        SaveClientIdLocally          = $true
        # PnP -PersistLogin caches tokens on disk. Off by default so switching
        # tenants can never silently reuse a previous customer's sign-in.
        PersistLogin                 = $false
    }

    # Modules checked by Install-M365Dependencies.
    # Required = $true  -> launcher warns and offers to install when missing.
    # Required = $false -> optional, installed only when requested.
    Dependencies             = @(
        @{ Name = 'Microsoft.Graph.Authentication'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'Sign-in and tenant verification (Connect-MgGraph)' }
        @{ Name = 'Microsoft.Graph.Users'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'User management' }
        @{ Name = 'Microsoft.Graph.Users.Actions'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'License assignment and user actions' }
        @{ Name = 'Microsoft.Graph.Groups'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'Group management' }
        @{ Name = 'Microsoft.Graph.Identity.DirectoryManagement'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'Licenses, roles, and directory objects' }
        @{ Name = 'Microsoft.Graph.Sites'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'SharePoint site access via Graph' }
        @{ Name = 'Microsoft.Graph.Files'; MinimumVersion = '2.41.1'; Service = 'Graph'; Required = $true; Purpose = 'OneDrive and document library access' }
        @{ Name = 'ExchangeOnlineManagement'; MinimumVersion = '3.10.1'; Service = 'ExchangeOnline'; Required = $true; Purpose = 'Exchange Online administration' }
        @{ Name = 'PnP.PowerShell'; MinimumVersion = '3.0.0'; Service = 'SharePoint'; Required = $false; Purpose = 'SharePoint administration (uses a per-tenant app registration)' }
    )

    UI                       = @{
        ClearScreen = $false
        Width       = 45
    }
}
