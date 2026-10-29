# Task-first connection planning. Legacy presets remain on disk but are not used.
$script:ToolkitConnectionMode='OnDemand'
$script:ToolkitProfilePrepared=$false
$script:ToolkitEverAdministrative=$false
$script:ToolkitPreferredTenant=$TenantDomain

function Get-ToolkitConnectionPlan {
    [CmdletBinding()]
    param([object[]] $Catalog,
        [ValidateSet('Reporting','Administration','OnDemand')][string] $Mode='OnDemand',
        [hashtable] $Profiles)
    # Retained for compatibility: choosing a mode no longer requests any service.
    return [pscustomobject]@{Mode=$Mode;Services=@();GraphScopes=@();TaskCount=0;ChangeTaskCount=0;Source='Task-first: no upfront service preset'}
}

function Get-ToolkitTaskConnectionPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Task,[object[]] $Catalog)
    $services=@((@('Graph')+@($Task.Services)) | Sort-Object -Unique)
    $scopes=@((@('User.Read')+@($Task.GraphScopes)) | Where-Object { $_ } | Sort-Object -Unique)
    $group=''; $members=@(); $bundled=@()
    foreach ($category in $Catalog) {
        if (@($category.Tasks | Where-Object Id -eq $Task.Id).Count) { $group=$category.Id; break }
    }
    if ($group -in @('sharepoint','onedrive')) { $group='sharepoint-onedrive' }
    foreach ($category in $Catalog) {
        $key=$category.Id
        if ($key -in @('sharepoint','onedrive')) { $key='sharepoint-onedrive' }
        if ($group -and $key -eq $group) { $members+=@($category.Tasks) }
    }
    # Never pre-request access for change, planned, disabled, or unreviewed tasks.
    # A companion task cannot introduce another provider (especially PnP).
    if ($Task.AccessMode -eq 'ReadOnly' -and $Task.PermissionReview -eq 'Reviewed') {
        $companions=@($members | Where-Object {
            $_.Status -eq 'Ready' -and $_.AccessMode -eq 'ReadOnly' -and $_.PermissionReview -eq 'Reviewed' -and
            @($_.Services | Where-Object { $_ -notin $services }).Count -eq 0
        })
        $candidate=@((@('User.Read')+@($companions | ForEach-Object { $_.GraphScopes })+@($Task.GraphScopes)) |
            Where-Object { $_ } | Sort-Object -Unique)
        # Keep bundles bounded as categories grow. Larger sets fall back to the selected task.
        if ($companions.Count -le 8 -and $candidate.Count -le 8) {
            $scopes=$candidate
            $bundled=@($companions | Where-Object Id -ne $Task.Id | ForEach-Object Name)
        }
    }
    # This resolver is used by every Ready menu task, not just user creation.
    $module=Get-Module -Name M365Toolkit.Core
    if (-not $module) { throw 'Load M365Toolkit.Core before planning task authentication.' }
    $definitions=@{}
    foreach ($entry in (@($Catalog | ForEach-Object { $_.Tasks })+@($Task))) {
        $definition=@{Id=$entry.Id;Status=$entry.Status;Services=@($entry.Services);GraphScopes=@($entry.GraphScopes)}
        if ($entry.PSObject.Properties['Path'] -and $entry.Path) {
            $sidecar=[IO.Path]::ChangeExtension([string]$entry.Path,'task.psd1')
            if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
                $definition=Import-PowerShellDataFile -LiteralPath $sidecar
                if ($definition.Id -ne $entry.Id) { throw 'Task sidecar ID differs from the selected task.' }
            }
        }
        $definitions[$entry.Id]=$definition
    }
    $complete=& $module { param($id,$defs) Get-ToolkitTaskAuthenticationRequirements -TaskId $id -Definitions $defs } $Task.Id $definitions
    $services=@((@($services)+@($complete.Services)) | Where-Object { $_ } | Sort-Object -Unique)
    $scopes=@((@($scopes)+@($complete.GraphScopes)) | Where-Object { $_ } | Sort-Object -Unique)
    return [pscustomobject]@{Services=$services;GraphScopes=$scopes;PermissionGroup=$group;BundledTaskNames=$bundled;TaskIds=@($complete.TaskIds)}
}

function Initialize-ToolkitConnectionProfile {
    param([ValidateSet('Reporting','Administration','OnDemand')][string] $Mode='OnDemand',[string] $TargetTenant)
    if ($Mode -eq 'Reporting' -and $script:ToolkitEverAdministrative) {
        throw 'For Reporting after Administration/change tasks, close PowerShell and start a fresh session. This does not revoke account roles or prior consent.'
    }
    $script:ToolkitConnectionMode=$Mode
    $script:ToolkitProfilePrepared=$false
    if ($TargetTenant) { $script:ToolkitPreferredTenant=$TargetTenant }
    Set-M365TaskPolicy -Mode $Mode
    if ($Mode -eq 'Administration') { $script:ToolkitEverAdministrative=$true }
    return $true
}

function Select-ToolkitConnectionProfile {
    param([switch] $Initial)
    while ($true) {
        Write-Host ''
        Write-Host 'TENANT / CONNECTION OPTIONS' -ForegroundColor Cyan
        Write-Host '[1] Select tenant for the next task (no sign-in)'
        Write-Host '[2] Connect / verify tenant identity now (Graph only)'
        Write-Host '[3] Enable Reporting task restrictions (no sign-in)'
        Write-Host '[4] Use task-first mode (allow confirmed change tasks)'
        Write-Host '[0] Back'
        $choice=([string](Read-Host 'Select an option [0]')).Trim()
        if (-not $choice -or $choice -eq '0') { return $false }
        try {
            switch ($choice) {
                '1' {
                    $domain=([string](Read-Host 'Tenant domain or ID (blank to cancel)')).Trim()
                    if (-not $domain) { continue }
                    if (-not (& $script:core { param($value) Test-TenantIdentifier -Value $value } $domain)) {
                        throw 'Enter a valid tenant domain or ID.'
                    }
                    $info=Get-M365TenantInfo
                    if ($info) { throw 'Already connected. Use Switch Tenant to select another tenant safely.' }
                    $script:ToolkitPreferredTenant=$domain
                    Write-Host ('Selected tenant: '+$domain+'. No sign-in started.') -ForegroundColor Green
                    return $true
                }
                '2' {
                    Connect-M365 -TenantDomain $script:ToolkitPreferredTenant -Service Graph -GraphScopes @('User.Read') -TaskName 'Verify tenant identity'
                    return $true
                }
                '3' {
                    $null=Initialize-ToolkitConnectionProfile -Mode Reporting
                    Write-Host 'Change tasks blocked. Underlying account/service privileges are NOT guaranteed read-only.' -ForegroundColor Yellow
                    return $true
                }
                '4' { return (Initialize-ToolkitConnectionProfile -Mode OnDemand) }
                default { Write-Host 'Choose 0, 1, 2, 3, or 4.' -ForegroundColor Yellow }
            }
        }
        catch { Write-M365Log -Message $_.Exception.Message -Level Error }
    }
}

function Invoke-ToolkitPreparedTask {
    param([Parameter(Mandatory)] $Task)
    if ($Task.Status -ne 'Ready') { throw 'Task is not Ready.' }
    Assert-M365TaskAccess -AccessMode $Task.AccessMode -TaskId $Task.Id
    if ($script:ToolkitConnectionMode -eq 'Reporting' -and $Task.PermissionReview -ne 'Reviewed') {
        throw 'Read-only task permissions have not been reviewed.'
    }
    $plan=Get-ToolkitTaskConnectionPlan -Task $Task -Catalog $script:catalog
    $name=$Task.Name
    if ($plan.BundledTaskNames.Count) {
        # Shown by the shared layer only if the bundle actually needs access.
        $name+=' (reviewed read bundle also covers: '+($plan.BundledTaskNames -join '; ')+')'
    }
    $null=Assert-M365Connection -TenantDomain $script:ToolkitPreferredTenant -Service $plan.Services -GraphScopes $plan.GraphScopes -TaskName $name
    # Conservative: a dispatched change task requires a fresh process before Reporting.
    if ($Task.AccessMode -eq 'Changes') { $script:ToolkitEverAdministrative=$true }
    # Complete preflight must succeed before workflow code is dispatched.
    $null=Assert-M365Connection -TenantDomain $script:ToolkitPreferredTenant -Service $plan.Services -GraphScopes $plan.GraphScopes -TaskName $name -NoPrompt
    $module=Get-Module -Name M365Toolkit.Core
    if ($Task.Id -eq 'users.disable-user') {
        # Before workflow approval or tenant mutations, avoid the failing
        # InteractiveBrowser credential reconstruction path for this task.
        & $module {
            param([string[]]$RequiredScopes)
            if (-not $script:M365Session) { throw 'Verified tenant session required.' }
            $expectedTenant=[string]$script:M365Session.TenantId
            $expectedAccount=[string]$script:M365Session.Account
            $context=Get-ToolkitGraphContext
            $mustReconnect=$false
            if (-not $context -or [string]$context.TenantId -ine $expectedTenant -or [string]$context.Account -ine $expectedAccount) {
                throw 'Graph session identity differs from the verified toolkit session. Restart and connect to the intended tenant.'
            }
            # Reuse a healthy connection regardless of its sign-in method.
            try {
                $null=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName' -OutputType PSObject -ErrorAction Stop
            } catch {
                $trace=$_.Exception.ToString()
                if ($trace -match 'GetInteractiveBrowserCredentialAsync' -or $trace -match 'System.UriFormatException') {
                    $mustReconnect=$true
                } else {
                    throw
                }
            }
            if ($mustReconnect) {
                Write-Host 'Graph sign-in needs a device-code refresh before offboarding can start.' -ForegroundColor Yellow
                if ((Read-Host 'Reconnect to the same tenant and administrator account? [y/N]') -notmatch '^(?i)y(es)?$') {
                    throw 'Authentication refresh cancelled. No offboarding steps started.'
                }
                $scopes=@((@('User.Read')+@($RequiredScopes)+@($script:M365Session.GraphScopes)) | Where-Object { $_ } | Sort-Object -Unique)
                try {
                    Disconnect-MgGraph -ErrorAction Stop | Out-Null
                    Connect-ToolkitGraph -TenantId $expectedTenant -Scopes $scopes -UseDeviceCode
                    $verified=Get-ToolkitVerifiedTenant -RequestedTenant $expectedTenant
                    if ([string]$verified.TenantId -ine $expectedTenant -or [string]$verified.Account -ine $expectedAccount) {
                        throw 'Reconnected Graph account or tenant differs from the approved connection target.'
                    }
                    if (-not (Test-ToolkitScopesPresent -Granted @($verified.GraphScopes) -Required $RequiredScopes)) {
                        throw 'Reconnected Graph session lacks required task scopes.'
                    }
                    $script:M365Session.GraphScopes=$verified.GraphScopes
                    $script:M365Session.Account=$verified.Account
                } catch {
                    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'Graph disconnect failed.' }
                    throw ('Graph recovery failed. Restart the toolkit before more tenant work. '+$_.Exception.Message)
                }
            }
            # Real read requests validate authentication before the task starts.
            $verified=Get-ToolkitVerifiedTenant -RequestedTenant $expectedTenant
            if ([string]$verified.Account -ine $expectedAccount -or [string]$verified.TenantId -ine $expectedTenant) {
                try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'Graph disconnect failed.' }
                throw 'Graph verification identity mismatch. Restart the toolkit.'
            }
        } -RequiredScopes @($plan.GraphScopes)
    }
    $previous=& $module { $script:ToolkitActiveTaskAuthentication }
    $active=[pscustomobject]@{TaskId=$Task.Id;Services=@($plan.Services);GraphScopes=@($plan.GraphScopes)}
    & $module { param($value) $script:ToolkitActiveTaskAuthentication=$value } $active
    try { & $Task.Path }
    finally { & $module { param($value) $script:ToolkitActiveTaskAuthentication=$value } $previous }
}
