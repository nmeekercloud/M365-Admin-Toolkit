function Assert-M365TaskAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ReadOnly','Changes')][string] $AccessMode,
        [Parameter(Mandatory)][string] $TaskId
    )
    if ($script:M365TaskPolicy -eq 'Reporting' -and $AccessMode -ne 'ReadOnly') {
        throw "Task '$TaskId' changes tenant data and is blocked in Reporting mode. Use Connect / Prepare Tenant Session to change mode."
    }
}
