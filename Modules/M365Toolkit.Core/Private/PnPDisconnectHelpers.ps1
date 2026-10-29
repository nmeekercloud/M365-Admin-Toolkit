function Get-ToolkitPnPCurrentConnection {
    [CmdletBinding()]
    param()
    if (-not (Get-Command Get-PnPConnection -ErrorAction SilentlyContinue)) { return $null }
    try {
        return Get-PnPConnection -ErrorAction Stop
    }
    catch {
        $message=$_.Exception.Message.Trim()
        # Only known absence-of-global-session responses count as already disconnected.
        # Do not hide authorization, network, module or other unexpected failures.
        $noSession='^(?i:You are not signed in\. Please use Connect-PnPOnline to connect\.?|You are not connected\. Please use Connect-PnPOnline to connect\.?)$'
        if ($message -match $noSession) { return $null }
        throw
    }
}
