<#
    SharePoint (PnP.PowerShell) connection provider.

    Since September 9, 2024 PnP.PowerShell requires a tenant-specific Entra ID app
    registration. This provider is adapted from the "OneDrive to SharePoint Archive"
    script and works the same way in every tenant:

      1. Try the client ID previously saved on this computer for the tenant
         (Get-PnPManagedAppId) and test it.
      2. Otherwise search Entra ID for existing PnP / SharePoint apps (localhost
         redirect URI, or a name containing 'PnP' or 'SharePoint') and let the
         admin pick one. The selected app is tested before it is used.
      3. Otherwise offer to create one with Register-PnPEntraIDAppForInteractiveLogin
         (requires confirmation; it is a change in the customer tenant).

    No client IDs are stored in the repository.
#>

function Get-ToolkitSharePointRoot {
    <#
    .SYNOPSIS
        Returns the tenant SharePoint root URL (for example https://contoso.sharepoint.com) via Graph.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root?$select=webUrl' -OutputType PSObject -ErrorAction Stop
    return ([Uri]$root.webUrl).GetLeftPart([UriPartial]::Authority)
}

function Get-ToolkitEntraApplication {
    <#
    .SYNOPSIS
        Returns app registrations from the tenant (all pages), optionally filtered by display name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string] $DisplayName
    )

    $select = '$select=id,appId,displayName,publicClient,createdDateTime'
    $uri    = if ($DisplayName) {
        $filter = [Uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
        "https://graph.microsoft.com/v1.0/applications?`$filter=$filter&$select"
    }
    else {
        "https://graph.microsoft.com/v1.0/applications?$select&`$top=999"
    }

    $apps = [System.Collections.Generic.List[object]]::new()
    while ($uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        foreach ($app in @($page.value)) { $apps.Add($app) }
        $uri = if ($page.PSObject.Properties['@odata.nextLink']) { $page.'@odata.nextLink' } else { $null }
    }
    return $apps
}

function Get-ToolkitPnPAppCandidate {
    <#
    .SYNOPSIS
        Lists app registrations that look usable for PnP interactive sign-in.
        Apps with a localhost redirect URI (required for -Interactive) are listed first.
    #>
    [CmdletBinding()]
    param()

    $appName    = Get-ToolkitSetting -Path 'SharePoint.PnPApplicationName' -Default 'M365 Admin Toolkit (PnP)'
    $candidates = foreach ($app in (Get-ToolkitEntraApplication)) {
        $redirects = @()
        if ($app.PSObject.Properties['publicClient'] -and $app.publicClient -and $app.publicClient.PSObject.Properties['redirectUris']) {
            $redirects = @($app.publicClient.redirectUris)
        }
        $interactive  = [bool](@($redirects | Where-Object { $_ -match '^https?://localhost' }).Count)
        $relevantName = ($app.displayName -ieq $appName) -or ($app.displayName -match '(?i)pnp|sharepoint')

        if ($interactive -or $relevantName) {
            [pscustomobject]@{
                DisplayName = [string]$app.displayName
                AppId       = [string]$app.appId
                Interactive = $interactive
            }
        }
    }

    return @($candidates | Sort-Object -Property @{ Expression = 'Interactive'; Descending = $true }, DisplayName)
}

function Connect-ToolkitPnPSite {
    <#
    .SYNOPSIS
        Connects PnP to a SharePoint URL with the given client ID and returns the connection object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $ClientId
    )

    $params = @{
        Url              = $Url
        Interactive      = $true
        ClientId         = $ClientId
        Tenant           = $script:M365Session.TenantId
        ReturnConnection = $true
        ErrorAction      = 'Stop'
    }
    if ([bool](Get-ToolkitSetting -Path 'SharePoint.PersistLogin' -Default $false)) {
        $params['PersistLogin'] = $true
    }
    return Connect-PnPOnline @params
}

function Test-ToolkitPnPApplication {
    <#
    .SYNOPSIS
        Verifies an app can sign in to the SharePoint admin center and read the root site.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AppId,
        [Parameter(Mandatory)] [string] $AdminUrl,
        [Parameter(Mandatory)] [string] $RootUrl
    )

    try {
        $connection = Connect-ToolkitPnPSite -Url $AdminUrl -ClientId $AppId
        $null = Get-PnPTenantSite -Identity $RootUrl -Connection $connection -ErrorAction Stop
        return [pscustomobject]@{ Success = $true; Connection = $connection; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Connection = $null; Error = $_.Exception.Message }
    }
}

function Save-ToolkitPnPClientId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $AppId
    )

    if (-not [bool](Get-ToolkitSetting -Path 'SharePoint.SaveClientIdLocally' -Default $true)) { return }
    if (-not (Get-Command -Name 'Set-PnPManagedAppId' -ErrorAction SilentlyContinue)) { return }
    try {
        Set-PnPManagedAppId -Url $Url -AppId $AppId -Overwrite -ErrorAction Stop | Out-Null
    }
    catch {
        Write-M365Log -Message "Could not save the PnP client ID for $Url : $($_.Exception.Message)" -Level Warning
    }
}

function Get-ToolkitPnPApplication {
    <#
    .SYNOPSIS
        Finds a usable PnP app (saved -> existing -> create new) and returns
        @{ AppId; AdminConnection }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RootUrl,
        [Parameter(Mandatory)] [string] $AdminUrl
    )

    $appName = Get-ToolkitSetting -Path 'SharePoint.PnPApplicationName' -Default 'M365 Admin Toolkit (PnP)'

    # --- 1. Saved client ID ----------------------------------------------
    if (Get-Command -Name 'Get-PnPManagedAppId' -ErrorAction SilentlyContinue) {
        $saved = $null
        try { $saved = Get-PnPManagedAppId -Url $RootUrl -ErrorAction Stop } catch { $saved = $null }
        if ($saved) {
            Write-Host 'Testing saved PnP application for this tenant...' -ForegroundColor Cyan
            $test = Test-ToolkitPnPApplication -AppId ([string]$saved) -AdminUrl $AdminUrl -RootUrl $RootUrl
            if ($test.Success) {
                Write-M365Log -Message "Using saved PnP application $saved." -Level Success
                return [pscustomobject]@{ AppId = [string]$saved; AdminConnection = $test.Connection }
            }
            Write-M365Log -Message "Saved PnP application $saved could not be used: $($test.Error)" -Level Warning
        }
    }

    # --- 2. Existing app registrations -----------------------------------
    Write-Host ''
    Write-Host 'Searching Entra ID for existing PnP / SharePoint applications...' -ForegroundColor Cyan
    $candidates = @(Get-ToolkitPnPAppCandidate)

    if ($candidates.Count -gt 0) {
        while ($true) {
            Write-Host ''
            for ($i = 0; $i -lt $candidates.Count; $i++) {
                $tag = if ($candidates[$i].Interactive) { '' } else { '  (no localhost redirect URI)' }
                Write-Host ("[{0}] {1}{2}" -f ($i + 1), $candidates[$i].DisplayName, $tag)
                Write-Host ("    Client ID: {0}" -f $candidates[$i].AppId) -ForegroundColor DarkGray
            }
            Write-Host ''
            Write-Host "[C] Create '$appName'"
            Write-Host '[Q] Cancel'

            $choice = Read-Host 'Select an application'
            if ($choice -match '^(?i)(C|CREATE)$') { break }
            if ($choice -match '^(?i)(Q|QUIT)$') { throw 'SharePoint connection cancelled.' }

            $number = 0
            if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $candidates.Count) {
                $selected = $candidates[$number - 1]
                $test     = Test-ToolkitPnPApplication -AppId $selected.AppId -AdminUrl $AdminUrl -RootUrl $RootUrl
                if ($test.Success) {
                    Write-M365Log -Message "Using existing PnP application '$($selected.DisplayName)' ($($selected.AppId))." -Level Success
                    return [pscustomobject]@{ AppId = $selected.AppId; AdminConnection = $test.Connection }
                }
                Write-Host ''
                Write-Host 'That application cannot be used:' -ForegroundColor Red
                Write-Host $test.Error -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host 'No existing PnP / SharePoint applications were found.' -ForegroundColor Yellow
    }

    if ($script:M365TaskPolicy -eq 'Reporting') {
        throw 'Reporting mode will not create an app registration. Use an existing usable PnP app or arrange setup separately in Administration mode.'
    }
    # --- 3. Create a new app registration --------------------------------
    if (-not (Get-Command -Name 'Register-PnPEntraIDAppForInteractiveLogin' -ErrorAction SilentlyContinue)) {
        throw 'This PnP.PowerShell version does not include Register-PnPEntraIDAppForInteractiveLogin. Update PnP.PowerShell and try again.'
    }

    $graphPerms = @(Get-ToolkitSetting -Path 'SharePoint.GraphDelegatePermissions' -Default @('User.Read'))
    $spPerms    = @(Get-ToolkitSetting -Path 'SharePoint.SharePointDelegatePermissions' -Default @('AllSites.FullControl'))

    $approved = Confirm-M365Action -Action "Create Entra ID app registration '$appName'" `
        -Target @("Graph (delegated): $($graphPerms -join ', ')", "SharePoint (delegated): $($spPerms -join ', ')") `
        -Impact Medium
    if (-not $approved) { throw 'A usable PnP application is required for SharePoint administration.' }

    Write-Host ''
    Write-Host "Creating '$appName'... (a sign-in and consent window will open)" -ForegroundColor Cyan
    Register-PnPEntraIDAppForInteractiveLogin -ApplicationName $appName -Tenant $script:M365Session.InitialDomain `
        -GraphDelegatePermissions $graphPerms -SharePointDelegatePermissions $spPerms -ErrorAction Stop | Out-Null
    Write-M365Log -Message "Created PnP app registration '$appName'." -Level Change

    Write-Host 'Waiting for Entra ID replication...' -ForegroundColor Cyan
    $created = $null
    for ($i = 1; $i -le 24 -and -not $created; $i++) {
        Start-Sleep -Seconds 5
        $created = @(Get-ToolkitEntraApplication -DisplayName $appName) |
            Sort-Object -Property createdDateTime -Descending |
            Select-Object -First 1
    }
    if (-not $created) { throw 'The app registration was created but could not be found afterwards. Try connecting again in a minute.' }

    $test = Test-ToolkitPnPApplication -AppId ([string]$created.appId) -AdminUrl $AdminUrl -RootUrl $RootUrl
    if (-not $test.Success) { throw "The new application could not be used: $($test.Error)" }

    return [pscustomobject]@{ AppId = [string]$created.appId; AdminConnection = $test.Connection }
}

function Connect-ToolkitSharePoint {
    <#
    .SYNOPSIS
        Connects PnP.PowerShell to the verified tenant's SharePoint admin center.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:M365Session) { throw 'Connect to Microsoft Graph first (tenant identity is established by Graph).' }

    Import-ToolkitModule -Name 'PnP.PowerShell'

    $rootUrl  = Get-ToolkitSharePointRoot
    $adminUrl = ConvertTo-ToolkitSharePointAdminUrl -TenantRootUrl $rootUrl
    Write-M365Log -Message "SharePoint root: $rootUrl | Admin: $adminUrl" -Level Info

    $app = Get-ToolkitPnPApplication -RootUrl $rootUrl -AdminUrl $adminUrl

    Save-ToolkitPnPClientId -Url $rootUrl -AppId $app.AppId
    Save-ToolkitPnPClientId -Url $adminUrl -AppId $app.AppId

    $script:M365Session.SharePointAdminUrl     = $adminUrl
    $script:M365Session.SharePoint.Connected   = $true
    $script:M365Session.SharePoint.ClientId    = $app.AppId
    $script:M365Session.SharePoint.RootUrl     = $rootUrl
    $script:M365Session.SharePoint.AdminUrl    = $adminUrl
    $script:M365Session.SharePoint.Connection  = $app.AdminConnection
    $script:M365Session.SharePoint.ConnectedAt = Get-Date
}
