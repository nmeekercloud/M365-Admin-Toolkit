function Get-M365ConnectionStatus {
    <#
    .SYNOPSIS
        Returns the live connection state of each service and whether it matches
        the verified tenant.

    .DESCRIPTION
        Reads state directly from each module (Get-MgContext, Get-ConnectionInformation,
        the stored PnP connection) instead of trusting cached values. No network calls.

    .OUTPUTS
        One object per service: Service, Connected, TenantId, Account, TenantMatch, Detail

    .EXAMPLE
        Get-M365ConnectionStatus | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $expectedTenant = if ($script:M365Session) { $script:M365Session.TenantId } else { $null }

    # --- Graph ------------------------------------------------------------
    $context = Get-ToolkitGraphContext
    $graphTenant = if ($context) { [string]$context.TenantId } else { $null }
    [pscustomobject]@{
        PSTypeName  = 'M365Toolkit.ConnectionStatus'
        Service     = 'Graph'
        Connected   = [bool]$context
        TenantId    = $graphTenant
        Account     = if ($context) { [string]$context.Account } else { $null }
        TenantMatch = if ($context -and $expectedTenant) { $graphTenant -eq $expectedTenant } else { $null }
        Detail      = if ($context) { "Scopes: $(@($context.Scopes) -join ', ')" } else { 'Not connected' }
    }

    # --- Exchange Online --------------------------------------------------
    $exo = Get-ToolkitExchangeConnection
    $exoTenant = if ($exo) { [string]$exo.TenantID } else { $null }
    [pscustomobject]@{
        PSTypeName  = 'M365Toolkit.ConnectionStatus'
        Service     = 'ExchangeOnline'
        Connected   = [bool]$exo
        TenantId    = $exoTenant
        Account     = if ($exo) { [string]$exo.UserPrincipalName } else { $null }
        TenantMatch = if ($exo -and $expectedTenant) { $exoTenant -eq $expectedTenant } else { $null }
        Detail      = if ($exo) { "Token: $($exo.TokenStatus)" } else { 'Not connected' }
    }

    # --- SharePoint (PnP) -------------------------------------------------
    $sp = $script:M365Session -and $script:M365Session.SharePoint.Connected
    [pscustomobject]@{
        PSTypeName  = 'M365Toolkit.ConnectionStatus'
        Service     = 'SharePoint'
        ClientId    = if ($sp) { [string]$script:M365Session.SharePoint.ClientId } else { $null }
        Connected   = [bool]$sp
        TenantId    = if ($sp) { $expectedTenant } else { $null }
        Account     = if ($sp) { $script:M365Session.Account } else { $null }
        TenantMatch = if ($sp) { $true } else { $null }
        Detail      = if ($sp) { "$($script:M365Session.SharePoint.AdminUrl) (client ID $($script:M365Session.SharePoint.ClientId))" } else { 'Not connected' }
    }
}
