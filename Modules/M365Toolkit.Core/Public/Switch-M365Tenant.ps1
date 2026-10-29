function Switch-M365Tenant {
    <#
    .SYNOPSIS
        Safely moves from the current tenant to a different customer tenant.

    .DESCRIPTION
        1. Shows the current tenant and asks for confirmation.
        2. Disconnects every service (SharePoint, Exchange Online, Graph).
        3. Verifies nothing is still connected. If anything is, it stops and tells
           you to restart PowerShell rather than risk working in the wrong tenant.
        4. Connects to the new tenant with full tenant verification.

    .PARAMETER TenantDomain
        New tenant domain or ID. Prompted for when omitted.

    .PARAMETER Service
        Services to connect in the new tenant. Defaults to the services that were
        connected in the previous tenant.

    .EXAMPLE
        Switch-M365Tenant -TenantDomain fabrikam.onmicrosoft.com
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $TenantDomain,

        [Parameter()]
        [ValidateSet('Graph', 'ExchangeOnline', 'SharePoint')]
        [string[]] $Service,

        [Parameter()]
        [switch] $Force
    )

    if ($script:M365Session) {
        $current = $script:M365Session
        if (-not $Service) {
            $Service = @('Graph')
            if ($current.Exchange.Connected)   { $Service += 'ExchangeOnline' }
            if ($current.SharePoint.Connected) { $Service += 'SharePoint' }
        }

        $approved = Confirm-M365Action -Action 'Disconnect from the current tenant' `
            -Target @("$($current.TenantName) ($($current.InitialDomain))") -Impact Low -Force:$Force
        if (-not $approved) { return }

        Disconnect-M365 -Service All
    }
    elseif (-not $Service) {
        $Service = @('Graph')
    }

    # --- Verify the old session is really gone ---------------------------
    $leftovers = @(Get-M365ConnectionStatus | Where-Object { $_.Connected })
    if ($leftovers.Count -gt 0) {
        $names = ($leftovers.Service -join ', ')
        Write-M365Log -Message "Switch aborted: still connected to $names after disconnect." -Level Error
        throw "Could not fully disconnect ($names). Close this PowerShell window and start the toolkit again before connecting to another tenant."
    }

    Write-M365Log -Message 'All services disconnected. Ready for a new tenant.' -Level Success
    Connect-M365 -TenantDomain $TenantDomain -Service $Service
}
