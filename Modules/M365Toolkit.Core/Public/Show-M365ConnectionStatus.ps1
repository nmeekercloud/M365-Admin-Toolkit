function Show-M365ConnectionStatus {
    <#
    .SYNOPSIS
        Prints a formatted connection status screen (menu option 9).
    #>
    [CmdletBinding()]
    param()

    $info   = Get-M365TenantInfo -Refresh
    $status = @(Get-M365ConnectionStatus)

    Show-M365Header -Title 'CONNECTION STATUS'

    if (-not $info) {
        Write-Host 'Tenant : ' -NoNewline; Write-Host 'Not Connected' -ForegroundColor Yellow
    }
    else {
        Write-Host ('Tenant         : {0}' -f $info.TenantName) -ForegroundColor Green
        Write-Host ('Tenant ID      : {0}' -f $info.TenantId)
        Write-Host ('Initial domain : {0}' -f $info.InitialDomain)
        Write-Host ('Default domain : {0}' -f $info.DefaultDomain)
        Write-Host ('Signed in as   : {0} ({1})' -f $info.Account, $info.AccountType)
        if ($info.Country)       { Write-Host ('Country        : {0}' -f $info.Country) }
        if ($info.TenantCreated) { Write-Host ('Tenant created : {0}' -f $info.TenantCreated) }
        Write-Host ('Connected at   : {0}' -f $info.ConnectedAt)
        Write-Host ('Domains        : {0}' -f ($info.VerifiedDomains -join ', ')) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'Services' -ForegroundColor Cyan
    Write-Host ('-' * 45) -ForegroundColor DarkGray
    foreach ($s in $status) {
        $label = switch ($s.Service) { 'Graph' { 'Microsoft Graph' } 'ExchangeOnline' { 'Exchange Online' } default { 'SharePoint (PnP)' } }
        Write-Host ('{0,-18}' -f $label) -NoNewline
        if (-not $s.Connected) {
            Write-Host 'Not connected' -ForegroundColor DarkGray
        }
        elseif ($s.TenantMatch -eq $false) {
            Write-Host 'WRONG TENANT' -ForegroundColor Red -NoNewline
            Write-Host "  ($($s.TenantId))"
        }
        else {
            Write-Host 'Connected' -ForegroundColor Green -NoNewline
            if ($s.Account) { Write-Host "  $($s.Account)" -ForegroundColor DarkGray } else { Write-Host '' }
        }
        if ($s.Service -eq 'SharePoint' -and $s.Connected) {
            $property = $s.PSObject.Properties['ClientId']
            $clientId = if ($property) { [string]$property.Value } else { '' }
            $parsed = [guid]::Empty
            if ([guid]::TryParse($clientId, [ref]$parsed) -and $parsed -ne [guid]::Empty) {
                Write-Host ('  PnP app client ID: {0}' -f $parsed.ToString('D')) -ForegroundColor DarkGray
            }
            else {
                Write-Host '  PnP app client ID: Unavailable' -ForegroundColor DarkGray
            }
        }
    }

    $graph = $status | Where-Object { $_.Service -eq 'Graph' -and $_.Connected }
    if ($graph) {
        Write-Host ''
        Write-Host 'Graph permissions granted this session:' -ForegroundColor Cyan
        Write-Host ("  " + ($graph.Detail -replace '^Scopes: ', '')) -ForegroundColor DarkGray
    }

    Write-Host ''
    $defaultLogging = Get-Variable -Name ToolkitDefaultFileLogging -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $selectedLog = Get-Variable -Name ToolkitFileLogPath -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($defaultLogging) {
        try { Write-Host ('Log file: {0}' -f (Get-M365LogPath)) -ForegroundColor DarkGray }
        catch { Write-Host ('Log file unavailable: {0}' -f $_.Exception.Message) -ForegroundColor Yellow }
    }
    elseif ($selectedLog) {
        Write-Host ('Log file: {0}' -f $selectedLog) -ForegroundColor DarkGray
    }
    else {
        Write-Host 'File logging: Off' -ForegroundColor DarkGray
    }
}
