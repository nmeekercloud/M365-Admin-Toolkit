function Wait-M365KeyPress {
    <#
    .SYNOPSIS
        Pauses until the user presses Enter.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string] $Message = 'Press Enter to continue'
    )

    Write-Host ''
    $null = Read-Host $Message
}
