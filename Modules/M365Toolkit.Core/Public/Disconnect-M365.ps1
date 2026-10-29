function Disconnect-M365 {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet('All','Graph','ExchangeOnline','SharePoint')]
        [string[]] $Service=@('All')
    )
    $all=$Service -contains 'All'
    $failures=[Collections.Generic.List[string]]::new()
    if ($all -or $Service -contains 'SharePoint') {
        try {
            if (Get-Command Disconnect-PnPOnline -ErrorAction SilentlyContinue) {
                $params=@{ErrorAction='Stop'}
                if ([bool](Get-ToolkitSetting -Path 'SharePoint.PersistLogin' -Default $false)) { $params['ClearPersistedLogin']=$true }
                # An unconnected global PnP context needs no Disconnect call.
                if (Get-Command Get-PnPConnection -ErrorAction SilentlyContinue) {
                    $current=Get-ToolkitPnPCurrentConnection
                    if ($current) { Disconnect-PnPOnline @params }
                }
            }
            if ($script:M365Session) {
                $script:M365Session.SharePoint.Connection=$null
                $script:M365Session.SharePoint.Connected=$false
                $script:M365Session.SharePoint.ClientId=$null
            }
        }
        catch { $failures.Add('SharePoint: '+$_.Exception.Message) }
    }
    if ($all -or $Service -contains 'ExchangeOnline') {
        try {
            if (Get-ToolkitExchangeConnection) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop | Out-Null }
            if (Get-ToolkitExchangeConnection) { throw 'An Exchange connection remains active.' }
            if ($script:M365Session) {
                $script:M365Session.Exchange.Connected=$false
                $script:M365Session.Exchange.Account=$null
            }
        }
        catch { $failures.Add('Exchange Online: '+$_.Exception.Message) }
    }
    if ($all -or $Service -contains 'Graph') {
        try {
            if (Get-ToolkitGraphContext) { Disconnect-MgGraph -ErrorAction Stop | Out-Null }
            if (Get-ToolkitGraphContext) { throw 'A Graph context remains active.' }
        }
        catch { $failures.Add('Graph: '+$_.Exception.Message) }
    }
    if ($failures.Count -gt 0) {
        $message='Disconnect incomplete. Close this PowerShell window before further tenant work. '+($failures -join ' | ')
        Write-M365Log -Message $message -Level Error
        throw $message
    }
    if ($all -or $Service -contains 'Graph') { $script:M365Session=$null }
    Write-M365Log -Message 'Requested toolkit service connections disconnected.' -Level Success
    # Local session cleanup is not token revocation or global browser/Windows sign-out.
}
