function Install-M365Dependencies {
    <#
    .SYNOPSIS
        Installs or updates the modules the toolkit needs, for the current user only.

    .DESCRIPTION
        - Checks first (Test-M365Dependencies) and only touches modules that are
          Missing, Outdated, or at a mismatched Microsoft Graph version.
        - Installs to the CurrentUser scope (no administrator rights needed).
        - Uses PSResourceGet (Install-PSResource, built into PowerShell 7.4+) and
          falls back to PowerShellGet (Install-Module) when needed.
        - Never runs silently: shows the plan and asks before installing
          (unless -Force). Supports -WhatIf.
        - PowerShell itself is not updated here; the launcher handles that.

    .PARAMETER IncludeOptional
        Also install optional modules (PnP.PowerShell for SharePoint).

    .PARAMETER CheckOnly
        Only display the dependency report.

    .PARAMETER Force
        Do not ask for confirmation.

    .EXAMPLE
        Install-M365Dependencies -CheckOnly

    .EXAMPLE
        Install-M365Dependencies -IncludeOptional
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()] [switch] $IncludeOptional,
        [Parameter()] [switch] $CheckOnly,
        [Parameter()] [switch] $Force
    )

    $report = @(Test-M365Dependencies -IncludeOptional:$IncludeOptional)

    Write-Host ''
    Write-Host ('{0,-46} {1,-16} {2,-12} {3}' -f 'Module', 'Status', 'Installed', 'Minimum') -ForegroundColor Cyan
    Write-Host ('-' * 86) -ForegroundColor DarkGray
    foreach ($r in $report) {
        $color = switch ($r.Status) { 'OK' { 'Green' } 'Missing' { if ($r.Required) { 'Red' } else { 'DarkGray' } } default { 'Yellow' } }
        $name  = if ($r.Required) { $r.Name } else { "$($r.Name) (optional)" }
        $inst  = if ($r.InstalledVersion) { [string]$r.InstalledVersion } else { '-' }
        Write-Host ('{0,-46} {1,-16} {2,-12} {3}' -f $name, $r.Status, $inst, $r.MinimumVersion) -ForegroundColor $color
    }
    Write-Host ''

    $psRow = $report | Where-Object { $_.Name -eq 'PowerShell' }
    if ($psRow.Status -ne 'OK') {
        Write-M365Log -Message "PowerShell $($psRow.InstalledVersion) is below the required $($psRow.MinimumVersion). Start the toolkit with Start-M365Toolkit.ps1 to update it." -Level Warning
    }

    $todo = @($report | Where-Object { $_.Name -ne 'PowerShell' -and $_.Status -ne 'OK' })
    if ($todo.Count -eq 0) {
        Write-M365Log -Message 'All checked modules are installed and up to date.' -Level Success
        return $report
    }
    if ($CheckOnly) { return $report }

    $loaded = @($todo | Where-Object { Get-Module -Name $_.Name })
    if ($loaded.Count -gt 0) {
        Write-M365Log -Message "These modules are already loaded in this session: $($loaded.Name -join ', '). After installing, close PowerShell and start the toolkit again." -Level Warning
    }

    if (-not $Force -and -not $WhatIfPreference) {
        $answer = Read-Host ("Install / update {0} module(s) for the current user from the PowerShell Gallery? [y/N]" -f $todo.Count)
        if ($answer -notmatch '^(?i)(y|yes)$') {
            Write-M365Log -Message 'Dependency installation skipped by user.' -Level Warning
            return $report
        }
    }

    # BEGIN BUNDLED PACKAGE INSTALL PREREQUISITES (2026-10-21)
    # Core import and -CheckOnly remain offline; -WhatIf must not auto-load providers.
    if (-not $WhatIfPreference) { Initialize-ToolkitBundledPackagePrerequisites }
    $usePSResource = if ($WhatIfPreference) { $false } else {
        [bool](Get-Command -Name 'Install-PSResource' -ErrorAction SilentlyContinue)
    }
    # END BUNDLED PACKAGE INSTALL PREREQUISITES

    foreach ($item in $todo) {
        if (-not $PSCmdlet.ShouldProcess("$($item.Name) (CurrentUser)", 'Install latest version')) { continue }

        Write-M365Log -Message "Installing $($item.Name)..." -Level Info
        try {
            if ($usePSResource) {
                Install-PSResource -Name $item.Name -Scope CurrentUser -Repository PSGallery -TrustRepository -Reinstall:($item.Status -ne 'Missing') -Quiet -ErrorAction Stop -WarningAction SilentlyContinue
            }
            else {
                Install-Module -Name $item.Name -Scope CurrentUser -Repository PSGallery -MinimumVersion $item.MinimumVersion -Force -AllowClobber -ErrorAction Stop -WarningAction SilentlyContinue
            }
            Write-M365Log -Message "Installed $($item.Name)." -Level Success
        }
        catch {
            Write-M365Log -Message "Failed to install $($item.Name): $($_.Exception.Message)" -Level Error
        }
    }

    return @(Test-M365Dependencies -IncludeOptional:$IncludeOptional)
}
