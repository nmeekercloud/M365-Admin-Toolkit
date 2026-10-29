function Assert-M365Connection {
    <#
    .SYNOPSIS
        Guarantees the required services are connected to the verified tenant.
        Every toolkit script calls this first, so scripts also work standalone.

    .DESCRIPTION
        - Not connected: prompts for a tenant and connects (unless -NoPrompt).
        - Connected but a required Graph scope is missing: requests it (incremental consent).
        - A required service is not connected: connects it to the SAME tenant.
        - A service is connected to a different tenant than Graph: throws.

        Returns the session (Get-M365TenantInfo output) so scripts can display or log it.

    .PARAMETER Service
        Graph, ExchangeOnline, SharePoint. Graph is always included.

    .PARAMETER GraphScopes
        Delegated Graph scopes the script needs (for example 'User.ReadWrite.All').

    .PARAMETER NoPrompt
        Throw instead of prompting when not connected (for unattended use).

    .EXAMPLE
        $tenant = Assert-M365Connection -Service Graph -GraphScopes 'User.ReadWrite.All', 'Group.ReadWrite.All'

    .EXAMPLE
        Assert-M365Connection -Service ExchangeOnline
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Graph', 'ExchangeOnline', 'SharePoint')]
        [string[]] $Service = @('Graph'),

        [Parameter()]
        [string[]] $GraphScopes = @(),

        [Parameter()]
        [string] $TenantDomain,

        [Parameter()]
        [string] $TaskName = 'Selected task or standalone script',

        [Parameter()]
        [string] $TaskId,

        [Parameter()]
        [switch] $NoPrompt
    )

    # Resolve all optional branches before asking for any connection.
    if ($TaskId) {
        $requirements=Get-ToolkitTaskAuthenticationRequirements -TaskId $TaskId
        $Service=@($Service)+@($requirements.Services)
        $GraphScopes=@($GraphScopes)+@($requirements.GraphScopes)
    }
    $Service = @('Graph') + @($Service | Where-Object { $_ -ne 'Graph' }) | Select-Object -Unique
    if ($script:ToolkitActiveTaskAuthentication) {
        $active=$script:ToolkitActiveTaskAuthentication
        $missingScopes=@($GraphScopes | Where-Object { $_ -notin @($active.GraphScopes) })
        $missingServices=@($Service | Where-Object { $_ -notin @($active.Services) })
        if ($missingScopes.Count -or $missingServices.Count) {
            throw ("Task '$($active.TaskId)' requested undeclared access during execution. Missing scopes: $($missingScopes -join ', '); services: $($missingServices -join ', '). Update its upfront authentication requirements. No sign-in was started.")
        }
        $NoPrompt=$true
    }

    # Include provider prerequisites before checking whether an existing session is sufficient.
    $GraphScopes=@($GraphScopes)+@(Get-ToolkitSetting -Path 'Graph.BaseScopes' -Default @('User.Read'))
    if ($Service -contains 'SharePoint') { $GraphScopes+=@(Get-ToolkitSetting -Path 'SharePoint.GraphScopes' -Default @()) }
    $GraphScopes=@($GraphScopes | Where-Object { $_ } | Sort-Object -Unique)
    $context = Get-ToolkitGraphContext
    if (-not $script:M365Session -or -not $context) {
        if ($NoPrompt) { throw 'Not connected to Microsoft 365. Run Connect-M365 first.' }
        Write-Host ''
        Write-Host 'This task needs a Microsoft 365 connection.' -ForegroundColor Yellow
        Connect-M365 -TenantDomain $TenantDomain -Service $Service -GraphScopes $GraphScopes -TaskName $TaskName
        return Get-M365TenantInfo
    }

    if ($context.TenantId -ne $script:M365Session.TenantId) {
        throw "Microsoft Graph is connected to tenant $($context.TenantId), not the verified tenant $($script:M365Session.TenantId). Use Switch-M365Tenant."
    }

    if ([string]$context.Account -ine [string]$script:M365Session.Account) {
        throw 'Graph account changed outside the toolkit. Disconnect before continuing.'
    }
    if ($TenantDomain -and $TenantDomain -ine $script:M365Session.TenantId -and
        @($script:M365Session.VerifiedDomains) -inotcontains $TenantDomain) {
        throw 'The selected tenant differs from the current session. Use Switch Tenant.'
    }

    $needsConnect = $false
    if ($GraphScopes.Count -gt 0 -and -not (Test-ToolkitScopesPresent -Granted @($context.Scopes) -Required $GraphScopes)) {
        Write-M365Log -Message "Requesting additional Graph permissions: $($GraphScopes -join ', ')" -Level Info
        $needsConnect = $true
    }

    if ($Service -contains 'ExchangeOnline') {
        $exo = Get-ToolkitExchangeConnection
        if (-not $exo) {
            $needsConnect = $true
        }
        elseif ([string]$exo.TenantID -ne $script:M365Session.TenantId) {
            throw "Exchange Online is connected to tenant $($exo.TenantID), not the verified tenant $($script:M365Session.TenantId). Use Switch-M365Tenant."
        }
    }

    if ($Service -contains 'ExchangeOnline' -and $exo -and [string]$exo.UserPrincipalName -ine [string]$script:M365Session.Account) {
        throw 'Exchange is connected as a different account. Disconnect before continuing.'
    }

    if ($Service -contains 'SharePoint' -and -not $script:M365Session.SharePoint.Connected) {
        $needsConnect = $true
    }

    if ($needsConnect) {
        if ($NoPrompt) { throw "Required access is no longer available. Re-select the task to authenticate at startup. Services: $($Service -join ', '); scopes: $($GraphScopes -join ', '). No mid-task sign-in was started." }
        Connect-M365 -TenantDomain $TenantDomain -Service $Service -GraphScopes $GraphScopes -TaskName $TaskName
    }

    return Get-M365TenantInfo
}
