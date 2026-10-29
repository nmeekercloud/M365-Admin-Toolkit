# Windows compatibility profile, based on the successful 2026-10-20 connection test.
# Definitions only. Startup explicitly calls Initialize-ToolkitDependencyCompatibility.
function ConvertTo-ToolkitComparableVersion {
    [CmdletBinding()]
    [OutputType([version])]
    param([Parameter(Mandatory)][version]$Value)
    [version]::new($Value.Major,$Value.Minor,[Math]::Max(0,$Value.Build),[Math]::Max(0,$Value.Revision))
}
function Get-ToolkitCompatibilityProfile {
    [CmdletBinding()]
    param()
    [ordered]@{
        'PackageManagement'='1.4.8.1'
        'PowerShellGet'='2.2.5'
        'PnP.PowerShell'='3.3.0'
        'Microsoft.Graph.Authentication'='2.41.2'
        'ExchangeOnlineManagement'='3.10.1'
    }
}
function Get-ToolkitBundledPackageRoots {
    [CmdletBinding()]
    param()
    @{
        PackageManagement=(Join-Path $PSHOME 'Modules/PackageManagement')
        PowerShellGet=(Join-Path $PSHOME 'Modules/PowerShellGet')
    }
}
function Assert-ToolkitCompatibilitySnapshot {
    [CmdletBinding()]
    param([object[]]$Modules=@(),[object[]]$PackageAssemblies=@(),
          [hashtable]$BundledRoots=(Get-ToolkitBundledPackageRoots))
    # Package-provider safeguards belong to PackagePrerequisites.ps1, not runtime connections.
    $profile=Get-ToolkitCompatibilityProfile
    foreach ($module in $Modules) {
        $name=[string]$module.Name
        if ($name -in @('PackageManagement','PowerShellGet')) { continue }
        if (-not $profile.Contains($name)) { continue }
        if ((ConvertTo-ToolkitComparableVersion $module.Version) -ne (ConvertTo-ToolkitComparableVersion $profile[$name])) {
            throw ("Incompatible service module already loaded: $name $($module.Version). Expected $($profile[$name]). No modules were installed or removed.")
        }
    }
}

function Assert-ToolkitCurrentCompatibility {
    [CmdletBinding()]
    param()
    $profile=Get-ToolkitCompatibilityProfile
    $modules=@(Get-Module -All -Name @($profile.Keys))
    $assemblies=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {$_.GetName().Name -eq 'Microsoft.PackageManagement'} | ForEach-Object {
        [pscustomobject]@{Name=$_.GetName().Name;Version=$_.GetName().Version;Location=$_.Location}
    })
    Assert-ToolkitCompatibilitySnapshot -Modules $modules -PackageAssemblies $assemblies
}
function Initialize-ToolkitDependencyCompatibility {
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { return }
    if (-not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion -lt [version]'7.6.0') {
        throw 'This toolkit requires 64-bit PowerShell 7.6.0 or later.'
    }
    Assert-ToolkitCurrentCompatibility
    Write-Verbose 'Runtime service compatibility checked. No package tools or cloud SDKs imported.'
}
