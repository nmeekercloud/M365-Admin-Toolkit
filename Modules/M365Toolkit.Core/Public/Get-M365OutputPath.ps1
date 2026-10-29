function Get-M365OutputPath {
    <#
    .SYNOPSIS
        Returns a tenant-scoped folder for reports, exports, or pre-change backups.

    .DESCRIPTION
        Output is stored outside the repository, separated per tenant:
            %LOCALAPPDATA%\M365AdminToolkit\<Type>\<tenant initial domain>\

        Use -FileName to get a full, timestamped file path that is safe to write to.

    .PARAMETER Type
        Reports, Exports, or Backups.

    .PARAMETER FileName
        Optional base file name (for example 'LicenseReport.csv'). A timestamp is
        inserted before the extension: LicenseReport_20261015-142233.csv

    .EXAMPLE
        $csv = Get-M365OutputPath -Type Reports -FileName 'LicenseReport.csv'
        $data | Export-Csv -Path $csv -NoTypeInformation
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Reports', 'Exports', 'Backups')]
        [string] $Type,

        [Parameter()]
        [string] $FileName
    )

    $folder = Join-Path -Path (Join-Path -Path (Get-ToolkitDataRoot) -ChildPath $Type) -ChildPath (Get-ToolkitSessionLabel)
    if (-not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -Path $folder -ItemType Directory -Force
    }
    if (-not $FileName) { return $folder }

    $safeName = $FileName -replace '[\\/:*?"<>|]', '_'
    $base     = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
    $ext      = [System.IO.Path]::GetExtension($safeName)
    $stamped  = '{0}_{1}{2}' -f $base, (Get-Date -Format 'yyyyMMdd-HHmmss'), $ext
    return Join-Path -Path $folder -ChildPath $stamped
}
