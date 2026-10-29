function Get-M365SharePointConnection {
    <#
    .SYNOPSIS
        Returns the PnP connection for the verified tenant, or a new PnP connection
        to a specific site using the tenant's PnP app (client ID).

    .DESCRIPTION
        SharePoint scripts should pass this to PnP cmdlets with -Connection so every
        command is explicitly bound to the verified tenant.

    .PARAMETER Url
        Optional site URL. When given, a connection to that site is created with the
        same client ID. When omitted, the admin center connection is returned.

    .EXAMPLE
        $admin = Get-M365SharePointConnection
        Get-PnPTenantSite -Connection $admin

    .EXAMPLE
        $site = Get-M365SharePointConnection -Url 'https://contoso.sharepoint.com/sites/HR'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Url
    )

    if (-not $script:M365Session -or -not $script:M365Session.SharePoint.Connected) {
        throw 'SharePoint is not connected. Run: Assert-M365Connection -Service SharePoint'
    }
    if (-not $Url) { return $script:M365Session.SharePoint.Connection }

    $rootHost = ([Uri]$script:M365Session.SharePoint.RootUrl).Host -replace '\.sharepoint\.com$', ''
    $siteHost = ([Uri]$Url).Host
    if ($siteHost -notmatch "^$([regex]::Escape($rootHost))(-my|-admin)?\.sharepoint\.com$") {
        throw "'$Url' does not belong to the connected tenant ($($script:M365Session.SharePoint.RootUrl))."
    }

    return Connect-ToolkitPnPSite -Url $Url -ClientId $script:M365Session.SharePoint.ClientId
}
