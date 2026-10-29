function Connect-M365 {
    <#
    .SYNOPSIS
        Connects to a Microsoft 365 tenant and verifies the connection landed in that tenant.

    .DESCRIPTION
        Connection order is always: Microsoft Graph -> Exchange Online -> SharePoint (PnP).

        Microsoft Graph is always connected first because it establishes and verifies
        the tenant identity:
          - the sign-in is pinned to the tenant you enter (-TenantDomain),
          - the organization's verified domains must include what you entered,
          - guest accounts are refused (usually means the wrong account was picked),
          - tokens are kept in this PowerShell process only (no disk cache).

        Exchange Online and SharePoint are then verified against the same tenant ID.
        On any mismatch the toolkit disconnects and stops.

        If you are already connected to a tenant, Connect-M365 only adds services or
        scopes to that same tenant. To work in a different tenant use Switch-M365Tenant.

    .PARAMETER TenantDomain
        Any verified domain of the customer tenant (contoso.com, contoso.onmicrosoft.com)
        or the tenant ID (GUID). Prompted for when omitted.

    .PARAMETER Service
        Graph, ExchangeOnline, SharePoint. Graph is always included.

    .PARAMETER GraphScopes
        Additional delegated Graph scopes to request (incremental consent).

    .PARAMETER UseDeviceCode
        Use device code sign-in for this connection.

    .PARAMETER DisableWAM
        Pass -DisableWAM to Connect-ExchangeOnline.

    .EXAMPLE
        Connect-M365 -TenantDomain contoso.onmicrosoft.com

    .EXAMPLE
        Connect-M365 -TenantDomain contoso.com -Service Graph, ExchangeOnline

    .EXAMPLE
        Connect-M365 -Service SharePoint      # add SharePoint to the current tenant
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $TenantDomain,

        [Parameter()]
        [ValidateSet('Graph', 'ExchangeOnline', 'SharePoint')]
        [string[]] $Service = @('Graph'),

        [Parameter()]
        [string[]] $GraphScopes = @(),

        [Parameter()]
        [switch] $UseDeviceCode,

        [Parameter()]
        [switch] $DisableWAM,

        # Used by the launcher; standalone calls retain a meaningful default.
        [Parameter()]
        [string] $TaskName = 'Connect Microsoft 365',

        [Parameter()]
        [switch] $PassThru
    )

    # Explicit nested connects may only verify/reuse preflighted access.
    if ($script:ToolkitActiveTaskAuthentication) {
        $null=Assert-M365Connection -TenantDomain $TenantDomain -Service $Service -GraphScopes $GraphScopes -TaskName $TaskName -NoPrompt
        if ($PassThru) { return Get-M365TenantInfo }
        return
    }
    # --- Resolve target tenant -------------------------------------------
    if ($script:M365Session) {
        if ($TenantDomain) {
            $sameTenant = ($TenantDomain -ieq $script:M365Session.TenantId) -or
                          (@($script:M365Session.VerifiedDomains) -icontains $TenantDomain)
            if (-not $sameTenant) {
                throw "Already connected to '$($script:M365Session.TenantName)' ($($script:M365Session.InitialDomain)). Use Switch-M365Tenant or the Switch Tenant menu entry to change tenants."
            }
        }
        $TenantDomain = $script:M365Session.InitialDomain
    }
    else {
        while (-not (Test-TenantIdentifier -Value $TenantDomain)) {
            if ($TenantDomain) { Write-Host "'$TenantDomain' is not a valid domain or tenant ID." -ForegroundColor Yellow }
            $TenantDomain = Read-Host 'Enter the customer tenant domain (e.g. contoso.onmicrosoft.com)'
            if ($null -eq $TenantDomain) { throw 'No tenant domain entered.' }
            $TenantDomain = $TenantDomain.Trim()
            if ($TenantDomain -match '^(?i)(Q|QUIT|CANCEL)$') { throw 'Connection cancelled.' }
        }
    }

    $Service = @('Graph') + @($Service | Where-Object { $_ -ne 'Graph' }) | Select-Object -Unique

    # --- Build the scope list --------------------------------------------
    $scopes = @(Get-ToolkitSetting -Path 'Graph.BaseScopes' -Default @('User.Read'))
    $scopes += $GraphScopes
    if ($Service -contains 'SharePoint') {
        $scopes += @(Get-ToolkitSetting -Path 'SharePoint.GraphScopes' -Default @())
    }
    if ($script:M365Session) { $scopes += @($script:M365Session.GraphScopes) }
    $scopes = @($scopes | Where-Object { $_ } | Sort-Object -Unique)

    # --- 1. Microsoft Graph ----------------------------------------------
    $context      = Get-ToolkitGraphContext
    if (-not (Confirm-ToolkitConnectionExpansion -Services $Service -Scopes $scopes -GraphContext $context -TaskName $TaskName)) {
        throw 'Connection cancelled. No requested authentication was started.'
    }
    $graphIsReady = $script:M365Session -and $context -and
                    ($context.TenantId -eq $script:M365Session.TenantId) -and
                    (Test-ToolkitScopesPresent -Granted @($context.Scopes) -Required $scopes)

    if (-not $graphIsReady) {
        Write-M365Log -Message "Connecting to Microsoft Graph for '$TenantDomain'..." -Level Info
        try {
            Connect-ToolkitGraph -TenantId $TenantDomain -Scopes $scopes -UseDeviceCode:$UseDeviceCode
        }
        catch {
            Write-M365Log -Message "Microsoft Graph sign-in failed: $($_.Exception.Message)" -Level Error
            throw
        }

        $previous = $script:M365Session
        $verified = Get-ToolkitVerifiedTenant -RequestedTenant $TenantDomain
        if ($previous -and [string]$previous.Account -ine [string]$verified.Account) {
            try { Disconnect-M365 -Service All }
            finally { throw 'The Graph account changed during authentication. Sessions were disconnected; select the intended account and try again.' }
        }

        if ($previous -and $previous.TenantId -eq $verified.TenantId) {
            # Same tenant, new scopes: keep existing Exchange / SharePoint state.
            $previous.GraphScopes = $verified.GraphScopes
            $previous.Account     = $verified.Account
        }
        else {
            $script:M365Session = $verified
        }

        Write-M365Log -Message "Microsoft Graph connected: $($script:M365Session.TenantName) ($($script:M365Session.InitialDomain)) as $($script:M365Session.Account)" -Level Success
    }

    # --- 2. Exchange Online ----------------------------------------------
    if ($Service -contains 'ExchangeOnline') {
        $exo = Get-ToolkitExchangeConnection
        if ($exo -and [string]$exo.TenantID -eq $script:M365Session.TenantId) {
            $script:M365Session.Exchange.Connected = $true
            $script:M365Session.Exchange.Account   = [string]$exo.UserPrincipalName
        }
        else {
            Write-M365Log -Message 'Connecting to Exchange Online...' -Level Info
            try {
                Connect-ToolkitExchange -UseDeviceCode:$UseDeviceCode -DisableWAM:$DisableWAM
            }
            catch {
                Write-M365Log -Message "Exchange Online connection failed: $($_.Exception.Message)" -Level Error
                throw
            }
            Write-M365Log -Message "Exchange Online connected as $($script:M365Session.Exchange.Account)" -Level Success
        }
    }

    # --- 3. SharePoint (PnP) ---------------------------------------------
    if ($Service -contains 'SharePoint' -and -not $script:M365Session.SharePoint.Connected) {
        Write-M365Log -Message 'Connecting to SharePoint Online (PnP)...' -Level Info
        try {
            Connect-ToolkitSharePoint
        }
        catch {
            Write-M365Log -Message "SharePoint connection failed: $($_.Exception.Message)" -Level Error
            throw
        }
        Write-M365Log -Message "SharePoint connected: $($script:M365Session.SharePoint.AdminUrl) (client ID $($script:M365Session.SharePoint.ClientId))" -Level Success
    }

    if ($PassThru) { return Get-M365TenantInfo }
}
