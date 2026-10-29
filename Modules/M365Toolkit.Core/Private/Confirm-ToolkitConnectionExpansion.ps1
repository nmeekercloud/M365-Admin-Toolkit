function Confirm-ToolkitConnectionExpansion {
    [CmdletBinding()]
    param([string[]] $Services,[string[]] $Scopes,$GraphContext,[string] $TaskName)
    $session=$script:M365Session
    if ($session -and $GraphContext) {
        if ($GraphContext.TenantId -ne $session.TenantId) {
            throw 'Graph tenant changed outside the toolkit. Disconnect and select the intended tenant again.'
        }
        if ([string]$GraphContext.Account -ine [string]$session.Account) {
            throw 'Graph account changed outside the toolkit. Disconnect before continuing.'
        }
    }
    $granted=@()
    if ($session -and $GraphContext) { $granted=@($GraphContext.Scopes) }
    $missing=@($Scopes | Where-Object { $_ -notin $granted })
    $newServices=@()
    if (-not $session -or -not $GraphContext) { $newServices+= 'Graph' }
    if ($Services -contains 'ExchangeOnline') {
        $exo=Get-ToolkitExchangeConnection
        if ($session -and $exo) {
            if ([string]$exo.TenantID -ne [string]$session.TenantId) {
                throw 'Exchange is connected to a different tenant. Disconnect before continuing.'
            }
            if ([string]$exo.UserPrincipalName -ine [string]$session.Account) {
                throw 'Exchange is connected as a different account. Disconnect before continuing.'
            }
        }
        else { $newServices+='ExchangeOnline' }
    }
    if ($Services -contains 'SharePoint' -and (-not $session -or -not $session.SharePoint.Connected)) {
        $newServices+='SharePoint (PnP)'
    }
    if (-not $missing.Count -and -not $newServices.Count) { return $true }
    Write-Host ''
    Write-Host ('CONNECTION REQUIRED: '+$TaskName) -ForegroundColor Cyan
    if ($session) { Write-Host ('Tenant: '+$session.InitialDomain+' | Account: '+$session.Account) }
    if ($newServices.Count) { Write-Host ('Services to connect: '+($newServices -join ', ')) }
    if ($missing.Count) { Write-Host ('Graph scopes not currently available: '+($missing -join ', ')) }
    Write-Host 'Continuing may open sign-in, MFA, or consent prompts. Previously granted consent may be reused.' -ForegroundColor Yellow
    if ($Services -contains 'ExchangeOnline') {
        Write-Host 'Exchange capabilities depend on the account roles; a connection is not a read-only sandbox.' -ForegroundColor Yellow
    }
    if ($Services -contains 'SharePoint') {
        Write-Host 'PnP needs a tenant app registration/client ID. Setup may be required; its permissions may be broader than this task.' -ForegroundColor Yellow
    }
    Write-Host 'Connecting does not perform the task changes. Existing task-level confirmations still apply.'
    return (([string](Read-Host 'Continue with this connection request? [y/N]')).Trim() -match '^(?i)y(es)?$')
}
