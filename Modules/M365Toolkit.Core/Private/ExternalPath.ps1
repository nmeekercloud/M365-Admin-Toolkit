function Assert-ToolkitExternalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Path)

    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Use an absolute filesystem path for customer data.' }
    $full = [IO.Path]::GetFullPath($Path)
    $repo = [IO.Path]::GetFullPath($script:ToolkitRoot).TrimEnd([char[]]'\/')
    if ($full.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Customer-data output inside the toolkit repository is blocked. Choose an external folder, such as C:\Temp.'
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Output paths through junctions or symbolic links are blocked. Choose a regular local folder.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}
