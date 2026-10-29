#Requires -Version 7.4
<#
    M365Toolkit.Core
    Shared framework loaded by the launcher and by every toolkit script.

    Module-scoped state (never exported):
      $script:ToolkitRoot  - repository root folder
      $script:Settings     - merged settings from Config\Toolkit.Settings(.local).psd1
      $script:M365Session  - the verified tenant session, or $null when not connected
#>

Set-StrictMode -Version 3.0

$script:ModuleRoot  = $PSScriptRoot
$script:ToolkitRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:M365Session = $null
$script:ToolkitGraphAuthAttempts = 0
$script:Settings    = $null

# Dot-source private helpers first, then public functions.
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "M365Toolkit.Core: failed to load '$($file.Name)': $($_.Exception.Message)"
    }
}

$script:Settings = Import-ToolkitSettings

# SDKs are prepared lazily by Import-ToolkitModule at a service-load boundary.
# Core import and connection-status probes must remain offline.

Export-ModuleMember -Function $public.BaseName
