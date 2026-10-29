function Test-M365Dependencies {
    <#
    .SYNOPSIS
        Checks PowerShell and every module listed in Config\Toolkit.Settings.psd1.

    .DESCRIPTION
        Read-only. Reports, for each dependency, the installed version and whether it
        meets the minimum. Also flags Microsoft Graph sub-modules installed at mixed
        versions (a common cause of "method not found" errors).

    .PARAMETER IncludeOptional
        Include optional modules (for example PnP.PowerShell) in the results.

    .OUTPUTS
        Objects with: Name, Required, MinimumVersion, InstalledVersion, Status, Service, Purpose
        Status is one of: OK, Missing, Outdated, VersionMismatch

    .EXAMPLE
        Test-M365Dependencies | Format-Table Name, Status, InstalledVersion, MinimumVersion
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()] [switch] $IncludeOptional
    )

    # --- PowerShell itself -----------------------------------------------
    $minPs = [version](Get-ToolkitSetting -Path 'MinimumPowerShellVersion' -Default '7.6.0')
    $curPs = [version]('{0}.{1}.{2}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor, $PSVersionTable.PSVersion.Patch)
    [pscustomobject]@{
        PSTypeName       = 'M365Toolkit.Dependency'
        Name             = 'PowerShell'
        Required         = $true
        MinimumVersion   = $minPs
        InstalledVersion = $curPs
        Status           = if ($curPs -ge $minPs) { 'OK' } else { 'Outdated' }
        Service          = 'All'
        Purpose          = 'PowerShell 7 runtime'
    }

    $dependencies = @(Get-ToolkitSetting -Path 'Dependencies' -Default @())
    if (-not $IncludeOptional) { $dependencies = @($dependencies | Where-Object { $_.Required }) }
    if ($dependencies.Count -eq 0) { return }

    $installed = @(Get-Module -ListAvailable -Name $dependencies.Name -ErrorAction SilentlyContinue)

    $results = foreach ($dep in $dependencies) {
        $minimum = [version]$dep.MinimumVersion
        $best    = $installed | Where-Object { $_.Name -eq $dep.Name } | Sort-Object -Property Version -Descending | Select-Object -First 1
        $status  = if (-not $best) { 'Missing' } elseif ($best.Version -lt $minimum) { 'Outdated' } else { 'OK' }

        [pscustomobject]@{
            PSTypeName       = 'M365Toolkit.Dependency'
            Name             = $dep.Name
            Required         = [bool]$dep.Required
            MinimumVersion   = $minimum
            InstalledVersion = if ($best) { $best.Version } else { $null }
            Status           = $status
            Service          = $dep.Service
            Purpose          = $dep.Purpose
        }
    }

    # --- Graph sub-modules must share one version -------------------------
    $graph = @($results | Where-Object { $_.Name -like 'Microsoft.Graph*' -and $_.InstalledVersion })
    $graphVersions = @()
    if ($graph.Count -gt 0) { $graphVersions = @($graph | ForEach-Object { $_.InstalledVersion } | Sort-Object -Unique) }
    if ($graphVersions.Count -gt 1) {
        $target = $graphVersions | Sort-Object -Descending | Select-Object -First 1
        foreach ($r in $graph) {
            if ($r.Status -eq 'OK' -and $r.InstalledVersion -ne $target) { $r.Status = 'VersionMismatch' }
        }
    }

    $results
}
