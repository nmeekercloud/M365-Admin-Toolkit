function Merge-ToolkitHashtable {
    <#
    .SYNOPSIS
        Recursively merges an override hashtable over a base hashtable.
        Nested hashtables are merged; all other values (including arrays) are replaced.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable] $Base,
        [Parameter(Mandatory)] [hashtable] $Override
    )

    $result = @{}
    foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }

    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-ToolkitHashtable -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

function Import-ToolkitSettings {
    <#
    .SYNOPSIS
        Loads Config\Toolkit.Settings.psd1 and merges the optional, git-ignored
        Config\Toolkit.Settings.local.psd1 over it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $configDir    = Join-Path -Path $script:ToolkitRoot -ChildPath 'Config'
    $defaultsPath = Join-Path -Path $configDir -ChildPath 'Toolkit.Settings.psd1'
    $localPath    = Join-Path -Path $configDir -ChildPath 'Toolkit.Settings.local.psd1'

    if (-not (Test-Path -LiteralPath $defaultsPath)) {
        throw "Settings file not found: $defaultsPath"
    }

    $settings = Import-PowerShellDataFile -LiteralPath $defaultsPath

    if (Test-Path -LiteralPath $localPath) {
        try {
            $local    = Import-PowerShellDataFile -LiteralPath $localPath
            $settings = Merge-ToolkitHashtable -Base $settings -Override $local
        }
        catch {
            Write-Warning "Ignoring invalid local settings file '$localPath': $($_.Exception.Message)"
        }
    }

    return $settings
}

function Get-ToolkitDataRoot {
    <#
    .SYNOPSIS
        Returns (and creates) the per-user data folder used for logs, reports and backups.
        Order of precedence: $env:M365TOOLKIT_DATAROOT, Settings.Paths.DataRoot,
        %LOCALAPPDATA%\M365AdminToolkit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = $null
    if ($env:M365TOOLKIT_DATAROOT) {
        $root = $env:M365TOOLKIT_DATAROOT
    }
    elseif (Get-ToolkitSetting -Path 'Paths.DataRoot') {
        $root = [Environment]::ExpandEnvironmentVariables((Get-ToolkitSetting -Path 'Paths.DataRoot'))
    }
    elseif ($env:LOCALAPPDATA) {
        $root = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'M365AdminToolkit'
    }
    else {
        # Non-Windows fallback used only by CI / unit tests.
        $root = Join-Path -Path $HOME -ChildPath '.m365admintoolkit'
    }

    $root = Assert-ToolkitExternalPath -Path $root
    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -Path $root -ItemType Directory -Force
    }
    return $root
}

function Get-ToolkitSetting {
    <#
    .SYNOPSIS
        Safely reads a value from the merged settings using a dotted path.
        Returns -Default when any part of the path does not exist.

    .EXAMPLE
        Get-ToolkitSetting -Path 'Authentication.UseDeviceCode' -Default $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter()] [object] $Default = $null
    )

    $node = $script:Settings
    foreach ($part in $Path.Split('.')) {
        if ($node -is [hashtable] -and $node.ContainsKey($part)) {
            $node = $node[$part]
        }
        else {
            return $Default
        }
    }
    if ($null -eq $node) { return $Default }
    return $node
}
