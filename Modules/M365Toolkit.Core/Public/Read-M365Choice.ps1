function Read-M365Choice {
    <#
    .SYNOPSIS
        Prompts until the user enters one of the allowed choices (case-insensitive).

    .PARAMETER Prompt
        Prompt text.

    .PARAMETER Valid
        Allowed answers, for example '1','2','0'.

    .OUTPUTS
        [string] the choice, upper-cased.

    .EXAMPLE
        $choice = Read-M365Choice -Prompt 'Select an option' -Valid '1', '2', '0'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [string] $Prompt = 'Select an option',
        [Parameter(Mandatory)] [string[]] $Valid
    )

    while ($true) {
        $answer = Read-Host $Prompt
        # $null means the input stream ended (redirected / non-interactive host).
        if ($null -eq $answer) { throw 'No input available. The toolkit menu must be run in an interactive console.' }
        $answer = $answer.Trim().ToUpperInvariant()
        if ($Valid -icontains $answer) { return $answer }
        Write-Host ("Invalid choice. Enter one of: {0}" -f ($Valid -join ', ')) -ForegroundColor Yellow
    }
}
