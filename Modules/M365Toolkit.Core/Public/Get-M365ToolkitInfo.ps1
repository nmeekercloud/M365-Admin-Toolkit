function Get-M365ToolkitInfo {
    <#
    .SYNOPSIS
        Returns toolkit version and path information.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $module = $ExecutionContext.SessionState.Module
    [pscustomobject]@{
        PSTypeName        = 'M365Toolkit.Info'
        Name              = Get-ToolkitSetting -Path 'ToolkitName' -Default 'Microsoft 365 Admin Toolkit'
        Version           = $module.Version
        ToolkitRoot       = $script:ToolkitRoot
        DataRoot          = Get-ToolkitDataRoot
        LogFolder         = Get-M365LogPath -Folder
        PowerShellVersion = $PSVersionTable.PSVersion
        MinimumPowerShell = [version](Get-ToolkitSetting -Path 'MinimumPowerShellVersion' -Default '7.6.0')
    }
}
