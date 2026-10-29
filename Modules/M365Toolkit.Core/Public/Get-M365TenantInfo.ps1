function Get-M365TenantInfo {
    <#
    .SYNOPSIS
        Returns information about the verified tenant the toolkit is connected to.

    .PARAMETER Refresh
        Re-read the organization from Microsoft Graph (adds country and creation date).

    .OUTPUTS
        M365Toolkit.TenantInfo, or $null when not connected.

    .EXAMPLE
        Get-M365TenantInfo

    .EXAMPLE
        (Get-M365TenantInfo).InitialDomain
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()] [switch] $Refresh
    )

    if (-not $script:M365Session) { return $null }
    $s = $script:M365Session

    $country = $null
    $created = $null
    if ($Refresh -and (Get-ToolkitGraphContext)) {
        try {
            $org = @((Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,countryLetterCode,createdDateTime' -OutputType PSObject -ErrorAction Stop).value) | Select-Object -First 1
            if ($org) {
                $country = [string]$org.countryLetterCode
                $created = $org.createdDateTime
            }
        }
        catch {
            Write-M365Log -Message "Could not refresh organization details: $($_.Exception.Message)" -Level Warning
        }
    }

    $services = @(Get-M365ConnectionStatus | Where-Object { $_.Connected } | ForEach-Object { $_.Service })

    [pscustomobject]@{
        PSTypeName         = 'M365Toolkit.TenantInfo'
        TenantName         = $s.TenantName
        TenantId           = $s.TenantId
        InitialDomain      = $s.InitialDomain
        DefaultDomain      = $s.DefaultDomain
        VerifiedDomains    = $s.VerifiedDomains
        Account            = $s.Account
        AccountType        = $s.UserType
        SharePointAdminUrl = $s.SharePointAdminUrl
        ConnectedServices  = $services
        ConnectedAt        = $s.ConnectedAt
        Country            = $country
        TenantCreated      = $created
    }
}
