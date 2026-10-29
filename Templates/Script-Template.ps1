#Requires -Version 7.4
<#
.SYNOPSIS
    <One line: what this script does.>

.DESCRIPTION
    <What it changes or reports, and anything the admin should know first.>

    Standard toolkit flow:
      1. Load M365Toolkit.Core (works from the launcher or standalone).
      2. Assert-M365Connection with only the services/scopes this script needs.
      3. Collect input (parameters first, prompts as fallback).
      4. Read current state and build a plan (read-only).
      5. Show the plan and confirm with Confirm-M365Action.
      6. Back up current state (for changes).
      7. Apply each change with ShouldProcess (-WhatIf supported) and log it.
      8. Print a summary.

.PARAMETER UserPrincipalName
    <Example parameter. Prompted for when omitted.>

.EXAMPLE
    .\Scripts\<Category>\<Verb-Noun>.ps1 -UserPrincipalName jdoe@contoso.com -WhatIf

.NOTES
    Services : Graph
    Scopes   : User.Read.All
    Impact   : Read-only | Changes (Low / Medium / High)
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string] $UserPrincipalName
)

$ErrorActionPreference = 'Stop'

# --- 1. Load the toolkit core --------------------------------------------
# Scripts live in Scripts\<Category>\, so the core module is two levels up.
if (-not (Get-Module -Name 'M365Toolkit.Core')) {
    $coreManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\M365Toolkit.Core\M365Toolkit.Core.psd1'
    Import-Module -Name $coreManifest -ErrorAction Stop
}

# --- 2. Connection ---------------------------------------------------------
$tenant = Assert-M365Connection -Service Graph -GraphScopes 'User.Read.All'
Write-M365Log -Message "Starting <task> in $($tenant.TenantName) ($($tenant.InitialDomain))." -Level Info

# --- 3. Input --------------------------------------------------------------
if (-not $UserPrincipalName) {
    $UserPrincipalName = (Read-Host 'User principal name (email)').Trim()
}
if (-not $UserPrincipalName) {
    Write-M365Log -Message 'No user entered. Nothing to do.' -Level Warning
    return
}

# --- 4. Read current state / build the plan (read-only) ---------------------
$user = Invoke-MgGraphRequest -Method GET -OutputType PSObject `
    -Uri "https://graph.microsoft.com/v1.0/users/$([Uri]::EscapeDataString($UserPrincipalName))?`$select=id,displayName,userPrincipalName,accountEnabled"

$plan = @(
    [pscustomobject]@{ Target = $user.userPrincipalName; Change = '<describe the change>' }
)

# --- 5. Confirm ------------------------------------------------------------
$approved = Confirm-M365Action -Action '<describe the change>' -Target $plan.Target -Impact Medium
if (-not $approved) { return }

# --- 6. Back up current state ----------------------------------------------
$backup = Get-M365OutputPath -Type Backups -FileName 'Template-Before.json'
$user | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backup -Encoding utf8
Write-M365Log -Message "Backup saved: $backup" -Level Info

# --- 7. Apply ----------------------------------------------------------------
$results = foreach ($item in $plan) {
    if ($PSCmdlet.ShouldProcess($item.Target, $item.Change)) {
        try {
            # <make the change here, e.g. Invoke-MgGraphRequest -Method PATCH ...>
            Write-M365Log -Message "$($item.Change): $($item.Target)" -Level Change
            [pscustomobject]@{ Target = $item.Target; Result = 'Success'; Error = $null }
        }
        catch {
            Write-M365Log -Message "Failed for $($item.Target): $($_.Exception.Message)" -Level Error
            [pscustomobject]@{ Target = $item.Target; Result = 'Failed'; Error = $_.Exception.Message }
        }
    }
    else {
        [pscustomobject]@{ Target = $item.Target; Result = 'Skipped (WhatIf)'; Error = $null }
    }
}

# --- 8. Summary --------------------------------------------------------------
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { $_.Result -eq 'Failed' }).Count
Write-M365Log -Message ("Done. {0} item(s), {1} failed." -f @($results).Count, $failed) -Level $(if ($failed) { 'Warning' } else { 'Success' })
