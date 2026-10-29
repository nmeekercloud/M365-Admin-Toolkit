function Confirm-M365Action {
    <#
    .SYNOPSIS
        Shows what is about to change, in which tenant, and asks for confirmation.

    .DESCRIPTION
        Every administrative change in the toolkit goes through this function.

          All impacts: type CONFIRM to continue; anything else cancels.
          Confirmation is amber, not failure-red. Tenant and targets remain visible.

        The decision is always written to the log.

        Use together with PowerShell's -WhatIf / -Confirm (SupportsShouldProcess):
        Confirm-M365Action is the human "are you sure, and is this the right tenant"
        gate; ShouldProcess still controls each individual change.

    .PARAMETER Action
        Plain-language description of the change.

    .PARAMETER Target
        Items affected (users, groups, sites...). Up to 10 are listed; the rest are counted.

    .PARAMETER Impact
        Low, Medium (default), or High. Use High for destructive or bulk changes.

    .PARAMETER Force
        Skip the prompt (the bypass is logged).

    .OUTPUTS
        [bool] $true when approved.

    .EXAMPLE
        if (Confirm-M365Action -Action 'Disable sign-in' -Target $upns -Impact High) { ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Action,

        [Parameter()]
        [string[]] $Target = @(),

        [Parameter()]
        [ValidateSet('Low', 'Medium', 'High')]
        [string] $Impact = 'Medium',

        [Parameter()]
        [switch] $Force
    )

    $session    = $script:M365Session
    $tenantText = if ($session) { "$($session.TenantName) ($($session.InitialDomain))" } else { 'Not connected' }
    $logData    = @{ Action = $Action; Impact = $Impact; TargetCount = $Target.Count; Targets = @($Target | Select-Object -First 25) }

    if ($Force) {
        Write-M365Log -Message "Confirmation bypassed (-Force): $Action" -Level Warning -Data $logData -Quiet
        return $true
    }

    $impactColor = 'DarkYellow'
    $line        = '-' * [int](Get-ToolkitSetting -Path 'UI.Width' -Default 45)

    Write-Host ''
    Write-Host $line -ForegroundColor $impactColor
    Write-Host ' CONFIRM ADMINISTRATIVE ACTION' -ForegroundColor $impactColor
    Write-Host $line -ForegroundColor $impactColor
    Write-Host ' Tenant : ' -NoNewline; Write-Host $tenantText -ForegroundColor White
    if ($session) { Write-Host ' Account: ' -NoNewline; Write-Host $session.Account }
    Write-Host ' Action : ' -NoNewline; Write-Host $Action -ForegroundColor White
    Write-Host ' Impact : ' -NoNewline; Write-Host $Impact.ToUpperInvariant() -ForegroundColor $impactColor

    if ($Target.Count -gt 0) {
        Write-Host (' Targets: {0} item(s)' -f $Target.Count)
        foreach ($t in ($Target | Select-Object -First 10)) { Write-Host "   - $t" -ForegroundColor Gray }
        if ($Target.Count -gt 10) { Write-Host ("   ... and {0} more" -f ($Target.Count - 10)) -ForegroundColor Gray }
    }
    Write-Host $line -ForegroundColor $impactColor

    Write-Host 'Type CONFIRM to continue, or press Enter to cancel.' -ForegroundColor $impactColor
    $answer = Read-Host 'Confirm'
    $approved = ($null -ne $answer) -and ($answer.Trim() -ieq 'CONFIRM')

    if ($approved) {
        Write-M365Log -Message "Approved: $Action" -Level Info -Data $logData -Quiet
    }
    else {
        Write-M365Log -Message "Cancelled by user: $Action" -Level Warning -Data $logData
    }
    return $approved
}
