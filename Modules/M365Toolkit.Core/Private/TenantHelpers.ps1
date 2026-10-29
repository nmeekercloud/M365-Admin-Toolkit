function Test-TenantIdentifier {
    <#
    .SYNOPSIS
        Returns $true when the value looks like a tenant GUID or a DNS domain
        (for example contoso.onmicrosoft.com or contoso.com).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }

    $guid = [guid]::Empty
    if ([guid]::TryParse($Value, [ref]$guid)) { return $true }

    $domainPattern = '^(?=.{4,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$'
    return [bool]($Value -match $domainPattern)
}

function Test-IsGuid {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)

    $guid = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$guid)
}

function ConvertTo-ToolkitSharePointAdminUrl {
    <#
    .SYNOPSIS
        Builds the SharePoint admin center URL.
        From a tenant root URL:  https://contoso.sharepoint.com      -> https://contoso-admin.sharepoint.com
        From an initial domain:  contoso.onmicrosoft.com             -> https://contoso-admin.sharepoint.com
    #>
    [CmdletBinding(DefaultParameterSetName = 'Root')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Root')] [string] $TenantRootUrl,
        [Parameter(Mandatory, ParameterSetName = 'Domain')] [string] $InitialDomain
    )

    if ($PSCmdlet.ParameterSetName -eq 'Domain') {
        if ($InitialDomain -notmatch '^([a-zA-Z0-9-]+)\.onmicrosoft\.com$') { return $null }
        return "https://$($Matches[1].ToLowerInvariant())-admin.sharepoint.com"
    }

    $uri   = [Uri]$TenantRootUrl
    $parts = $uri.Host -split '\.', 2
    return "$($uri.Scheme)://$($parts[0])-admin.$($parts[1])"
}

function Get-ToolkitSessionLabel {
    <#
    .SYNOPSIS
        Short, safe label for the current tenant used in log file names and output folders.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:M365Session -and $script:M365Session.InitialDomain) {
        return ($script:M365Session.InitialDomain -replace '[^a-zA-Z0-9.-]', '_').ToLowerInvariant()
    }
    return 'no-tenant'
}

function Import-ToolkitModule {
    <#
    .SYNOPSIS
        Imports a dependency module at or above the minimum version defined in settings.
        Throws a friendly error that points the user to the dependency check when missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $dependency = @(Get-ToolkitSetting -Path 'Dependencies' -Default @()) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $minimum    = if ($dependency) { [version]$dependency.MinimumVersion } else { [version]'0.0' }

    $pinned=$null
    if ($IsWindows) {
        $profile=Get-ToolkitCompatibilityProfile
        if ($profile.Contains($Name)) {
            Initialize-ToolkitDependencyCompatibility
            $pinned=[version]$profile[$Name]
            if ((ConvertTo-ToolkitComparableVersion $minimum) -gt (ConvertTo-ToolkitComparableVersion $pinned)) {
                throw "$Name minimum $minimum exceeds tested compatibility pin $pinned. Review the profile; no silent version substitution is allowed."
            }
        }
        elseif ($Name -like 'Microsoft.Graph.*') {
            Initialize-ToolkitDependencyCompatibility
        }
    }

    $loaded = Get-Module -Name $Name | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($loaded) {
        if ($pinned -and (ConvertTo-ToolkitComparableVersion $loaded.Version) -ne (ConvertTo-ToolkitComparableVersion $pinned)) { throw "$Name version changed outside the compatibility profile. Start a fresh PowerShell process." }
        if ((ConvertTo-ToolkitComparableVersion $loaded.Version) -lt (ConvertTo-ToolkitComparableVersion $minimum)) {
            throw "$Name $($loaded.Version) is loaded but $minimum or later is required. Close PowerShell, run the dependency check from the launcher ([D]), then start again."
        }
        return
    }

    $available = Get-Module -Name $Name -ListAvailable |
        Where-Object { (ConvertTo-ToolkitComparableVersion $_.Version) -ge (ConvertTo-ToolkitComparableVersion $minimum) -and (-not $pinned -or (ConvertTo-ToolkitComparableVersion $_.Version) -eq (ConvertTo-ToolkitComparableVersion $pinned)) } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if (-not $available) {
        if ($pinned) { throw "Required compatibility version $Name $pinned is not installed. Install that exact version in a separate session, then restart PowerShell." }
        throw "Required module $Name ($minimum or later) is not installed. Run the dependency check from the launcher ([D]) or: Install-M365Dependencies"
    }

    # -Global: make the module's cmdlets visible to the launcher and every toolkit
    # script, not only inside M365Toolkit.Core.
    Import-Module -Name $available.Path -Global -ErrorAction Stop -Verbose:$false -WarningAction SilentlyContinue | Out-Null
}
