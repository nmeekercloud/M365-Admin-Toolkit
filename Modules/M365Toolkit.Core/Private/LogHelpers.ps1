function Protect-ToolkitLogText {
    <#
    .SYNOPSIS
        Removes access tokens and secret-looking values from text before it is logged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $result = $Text -replace 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', '[REDACTED-TOKEN]'
    $result = $result -replace '(?i)((client_secret|password|secret|access_token|refresh_token)\s*[=:]\s*)("?)[^\s";,]+', '$1$3[REDACTED]'
    return $result
}

function Remove-ToolkitExpiredLog {
    <# Automatic deletion of existing logs is disabled. No files are removed. #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    return
}
