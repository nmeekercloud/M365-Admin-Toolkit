function ConvertTo-ToolkitSession {
    <#
    .SYNOPSIS
        Creates the verified tenant session object. Every property always exists
        (the module runs under Set-StrictMode, which throws on missing properties).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]   $TenantId,
        [Parameter(Mandatory)] [string]   $TenantName,
        [Parameter(Mandatory)] [string]   $InitialDomain,
        [Parameter()]          [string]   $DefaultDomain,
        [Parameter()]          [string[]] $VerifiedDomains = @(),
        [Parameter(Mandatory)] [string]   $Account,
        [Parameter()]          [string]   $UserType = 'Member',
        [Parameter()]          [string[]] $GraphScopes = @()
    )

    [pscustomobject]@{
        PSTypeName         = 'M365Toolkit.Session'
        TenantId           = $TenantId
        TenantName         = $TenantName
        InitialDomain      = $InitialDomain
        DefaultDomain      = $DefaultDomain
        VerifiedDomains    = $VerifiedDomains
        Account            = $Account
        UserType           = $UserType
        GraphScopes        = $GraphScopes
        ConnectedAt        = Get-Date
        SharePointAdminUrl = ConvertTo-ToolkitSharePointAdminUrl -InitialDomain $InitialDomain
        Exchange           = [pscustomobject]@{
            Connected   = $false
            Account     = $null
            ConnectedAt = $null
        }
        SharePoint         = [pscustomobject]@{
            Connected   = $false
            ClientId    = $null
            RootUrl     = $null
            AdminUrl    = $null
            Connection  = $null
            ConnectedAt = $null
        }
    }
}

function Test-ToolkitIsWindows10 {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows) { return $false }
    # Windows 11 starts at build 22000; Windows 10 reports major version 10 with a lower build.
    $version = [Environment]::OSVersion.Version
    return ($version.Major -eq 10 -and $version.Build -lt 22000)
}

function Get-ToolkitGraphContext {
    <#
    .SYNOPSIS
        Returns the current Microsoft Graph context, or $null if Graph is not loaded / connected.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-MgContext' -ListImported -ErrorAction SilentlyContinue)) { return $null }
    try {
        $context = Get-MgContext -ErrorAction Stop
        if ($context -and $context.Account) { return $context }
    }
    catch {
        Write-Verbose "Get-MgContext failed: $($_.Exception.Message)"
    }
    return $null
}

function Get-ToolkitExchangeConnection {
    <#
    .SYNOPSIS
        Returns the active Exchange Online (non-compliance) connection, or $null.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-ConnectionInformation' -ListImported -ErrorAction SilentlyContinue)) { return $null }
    try {
        $connections = @(Get-ConnectionInformation -ErrorAction Stop)
        return $connections |
            Where-Object { $_.State -eq 'Connected' -and -not $_.IsEopSession } |
            Select-Object -Last 1
    }
    catch {
        Write-Verbose "Get-ConnectionInformation failed: $($_.Exception.Message)"
    }
    return $null
}

function Connect-ToolkitGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string[]]$Scopes,
        [switch]$UseDeviceCode
    )
    Import-ToolkitModule -Name 'Microsoft.Graph.Authentication'
    $params = @{
        TenantId = $TenantId
        Scopes = $Scopes
        ContextScope = 'Process'
        NoWelcome = $true
        ErrorAction = 'Stop'
    }
    # Device code is opt-in only: an explicit switch or a deliberate local setting.
    $deviceRequested = $UseDeviceCode -or [bool](Get-ToolkitSetting -Path 'Authentication.UseDeviceCode' -Default $false)
    $flow = 'Interactive'
    if ($deviceRequested) {
        $params['UseDeviceAuthentication'] = $true
        $flow = 'DeviceCode'
        Write-Host 'Device-code sign-in was explicitly requested.' -ForegroundColor Yellow
    }
    $script:ToolkitGraphAuthAttempts++
    Write-M365Log -Message ("[AuthDiag] attempt={0}; flow={1}; stage=ConnectStart" -f $script:ToolkitGraphAuthAttempts, $flow) -Level Info
    # No device-code fallback. Failures propagate to the caller unchanged.
    Connect-MgGraph @params | Out-Host
    $context = Get-MgContext -ErrorAction Stop
    if (-not $context -or -not $context.Account) {
        throw 'Microsoft Graph sign-in did not return an authenticated account.'
    }
    Write-M365Log -Message ("[AuthDiag] attempt={0}; flow={1}; stage=ConnectReturned" -f $script:ToolkitGraphAuthAttempts, $flow) -Level Info
}

function Get-ToolkitVerifiedTenant {
    <#
    .SYNOPSIS
        Reads the organization and signed-in user from Graph and verifies that the
        connection landed in the tenant the administrator asked for.

    .OUTPUTS
        A new M365Toolkit.Session object. Throws (after disconnecting Graph) on mismatch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RequestedTenant
    )

    $context = Get-ToolkitGraphContext
    if (-not $context) { throw 'Microsoft Graph sign-in did not complete.' }

    Write-M365Log -Message '[AuthDiag] stage=VerifyOrganization' -Level Info
    $orgResponse = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains' -OutputType PSObject -ErrorAction Stop
    $org = @($orgResponse.value) | Select-Object -First 1
    if (-not $org) { throw 'Unable to read the organization from Microsoft Graph.' }

    Write-M365Log -Message '[AuthDiag] stage=VerifyUser' -Level Info
    $me = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,userType' -OutputType PSObject -ErrorAction Stop

    $domains       = @($org.verifiedDomains)
    $domainNames   = @($domains | ForEach-Object { [string]$_.name })
    $initialDomain = [string](@($domains | Where-Object { $_.isInitial }) | Select-Object -First 1).name
    $defaultDomain = [string](@($domains | Where-Object { $_.isDefault }) | Select-Object -First 1).name

    # --- Tenant match -----------------------------------------------------
    $matchesRequest = if (Test-IsGuid -Value $RequestedTenant) {
        $org.id -eq $RequestedTenant
    }
    else {
        $domainNames -contains $RequestedTenant
    }

    $problem = $null
    if ($context.TenantId -ne $org.id) {
        $problem = "Graph context tenant ($($context.TenantId)) does not match organization ($($org.id))."
    }
    elseif (-not $matchesRequest) {
        $problem = "Signed in to '$($org.displayName)' ($initialDomain), which does not own '$RequestedTenant'."
    }
    elseif ($me.userType -eq 'Guest' -and [bool](Get-ToolkitSetting -Path 'Authentication.BlockGuestAccounts' -Default $true)) {
        $problem = "Account '$($context.Account)' is a GUEST in '$($org.displayName)'. Sign in with the tenant's own admin account."
    }

    if ($problem) {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'Graph disconnect failed.' }
        Write-M365Log -Message "Tenant verification FAILED: $problem" -Level Error
        throw "Tenant verification failed. $problem Disconnected for safety."
    }

    ConvertTo-ToolkitSession -TenantId $org.id -TenantName $org.displayName -InitialDomain $initialDomain `
        -DefaultDomain $defaultDomain -VerifiedDomains $domainNames -Account $context.Account `
        -UserType ([string]$me.userType) -GraphScopes @($context.Scopes)
}

function Connect-ToolkitExchange {
    <#
    .SYNOPSIS
        Connects to Exchange Online with the same account as Graph, then verifies
        the Exchange tenant matches the verified Graph tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [switch] $UseDeviceCode,
        [Parameter()] [switch] $DisableWAM
    )

    if (-not $script:M365Session) { throw 'Connect to Microsoft Graph first (tenant identity is established by Graph).' }

    # Graph is always loaded before Exchange to avoid authentication assembly conflicts.
    Import-ToolkitModule -Name 'ExchangeOnlineManagement'

    $params = @{
        UserPrincipalName = $script:M365Session.Account
        ShowBanner        = $false
        ErrorAction       = 'Stop'
    }
    if ($UseDeviceCode -or [bool](Get-ToolkitSetting -Path 'Authentication.UseDeviceCode' -Default $false)) {
        $params['Device'] = $true
    }
    if ($DisableWAM -or [bool](Get-ToolkitSetting -Path 'Authentication.ExchangeDisableWAM' -Default $false)) {
        $params['DisableWAM'] = $true
    }

    Connect-ExchangeOnline @params | Out-Null

    $connection = Get-ToolkitExchangeConnection
    if (-not $connection) { throw 'Exchange Online sign-in did not complete.' }

    if ([string]$connection.TenantID -ne $script:M365Session.TenantId) {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'Exchange disconnect failed.' }
        $message = "Exchange Online connected to tenant $($connection.TenantID) but the verified tenant is $($script:M365Session.TenantId)."
        Write-M365Log -Message "Tenant verification FAILED: $message" -Level Error
        throw "Tenant verification failed. $message Disconnected for safety."
    }

    $script:M365Session.Exchange.Connected   = $true
    $script:M365Session.Exchange.Account     = [string]$connection.UserPrincipalName
    $script:M365Session.Exchange.ConnectedAt = Get-Date
}

function Test-ToolkitScopesPresent {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()] [string[]] $Granted = @(),
        [Parameter()] [string[]] $Required = @()
    )

    foreach ($scope in $Required) {
        if (-not ($Granted | Where-Object { $_ -ieq $scope })) { return $false }
    }
    return $true
}
