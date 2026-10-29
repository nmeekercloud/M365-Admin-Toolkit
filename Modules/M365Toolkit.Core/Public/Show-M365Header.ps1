function Show-M365Header {
    <#
    .SYNOPSIS
        Clears the console (configurable) and prints the toolkit banner.

    .PARAMETER Title
        Banner title. Defaults to the main toolkit title.

    .PARAMETER NoClear
        Do not clear the screen first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Title = 'MICROSOFT 365 ADMIN TOOLKIT',
        [Parameter()] [switch] $NoClear
    )

    $width = [int](Get-ToolkitSetting -Path 'UI.Width' -Default 45)
    if (-not $NoClear -and [bool](Get-ToolkitSetting -Path 'UI.ClearScreen' -Default $false)) {
        try { Clear-Host } catch { Write-Verbose 'Clear-Host not supported by this host.' }
    }

    $padLeft = [Math]::Max(0, [int][Math]::Floor(($width - $Title.Length) / 2))
    Write-Host ('=' * $width) -ForegroundColor Cyan
    Write-Host ((' ' * $padLeft) + $Title) -ForegroundColor White
    Write-Host ('=' * $width) -ForegroundColor Cyan
    Write-Host ''
}
