function Invoke-ToolkitExitCleanup {
    [CmdletBinding()]
    param()
    try {
        Disconnect-M365 -Service All
        Write-Host 'Toolkit session ended. Requested service connections disconnected.' -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning ('Toolkit is exiting, but connection cleanup was incomplete: '+$_.Exception.Message)
        Write-Warning 'Close this PowerShell window before doing more tenant work. No successful-disconnect guarantee is being made.'
        return $false
    }
}
