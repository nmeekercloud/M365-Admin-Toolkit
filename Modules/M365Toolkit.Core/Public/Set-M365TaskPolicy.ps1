function Set-M365TaskPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Reporting','Administration','OnDemand')][string] $Mode)
    $script:M365TaskPolicy=$Mode
}
