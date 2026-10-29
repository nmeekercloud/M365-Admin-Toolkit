#Requires -Version 7.4
# Definitions only. Importing Core must not import package tools or cloud SDKs.
function Get-ToolkitPackagePrerequisiteVersions {
    [CmdletBinding()]
    param()
    @{PackageManagement='1.4.8.1';PowerShellGet='2.2.5'}
}
function ConvertTo-ToolkitPackagePrerequisiteVersion {
    param([Parameter(Mandatory)][version]$Value)
    [version]::new($Value.Major,$Value.Minor,[Math]::Max(0,$Value.Build),[Math]::Max(0,$Value.Revision))
}
function Get-ToolkitPackagePrerequisiteRoots {
    [CmdletBinding()]
    param()
    @{PackageManagement=(Join-Path $PSHOME 'Modules/PackageManagement');PowerShellGet=(Join-Path $PSHOME 'Modules/PowerShellGet')}
}
function Get-ToolkitPackagePrerequisiteSnapshot {
    [CmdletBinding()]
    param()
    $modules=@(Get-Module -All -Name PackageManagement,PowerShellGet)
    $assemblies=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.PackageManagement' } | ForEach-Object {
        [pscustomobject]@{Name=$_.GetName().Name;Version=$_.GetName().Version;Location=$_.Location}
    })
    [pscustomobject]@{Modules=$modules;Assemblies=$assemblies}
}
function Assert-ToolkitPackagePrerequisiteSnapshot {
    [CmdletBinding()]
    param([object[]]$Modules=@(),[object[]]$Assemblies=@(),
          [hashtable]$Roots=(Get-ToolkitPackagePrerequisiteRoots),
          [hashtable]$Versions=(Get-ToolkitPackagePrerequisiteVersions))
    foreach ($module in $Modules) {
        $name=[string]$module.Name
        if (-not $Versions.ContainsKey($name)) { continue }
        if ((ConvertTo-ToolkitPackagePrerequisiteVersion $module.Version) -ne (ConvertTo-ToolkitPackagePrerequisiteVersion $Versions[$name])) {
            throw "Incompatible $name $($module.Version) is already loaded from '$($module.ModuleBase)'. Required: $($Versions[$name]) from PSHOME. Start a fresh 64-bit PowerShell 7 process (pwsh -NoProfile); do not retry in this process. No module was removed."
        }
        $actual=[IO.Path]::GetFullPath([string]$module.ModuleBase).TrimEnd([char[]]'\/')
        $expected=[IO.Path]::GetFullPath([string]$Roots[$name]).TrimEnd([char[]]'\/')
        if ($actual -ine $expected) { throw "$name is loaded outside its PSHOME bundled directory. Start a fresh 64-bit PowerShell 7 process (pwsh -NoProfile). No module was removed." }
    }
    foreach ($assembly in $Assemblies) {
        if ([string]$assembly.Name -ne 'Microsoft.PackageManagement') { continue }
        if ([version]$assembly.Version -lt [version]'3.0.0.1') { throw 'An incompatible Microsoft.PackageManagement DLL is already loaded. Start a fresh 64-bit PowerShell 7 process (pwsh -NoProfile); removing a module does not unload its DLL.' }
        $expected=[IO.Path]::GetFullPath([string]$Roots.PackageManagement).TrimEnd([char[]]'\/')+[IO.Path]::DirectorySeparatorChar
        if (-not ([string]$assembly.Location).StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'Microsoft.PackageManagement DLL is outside the PSHOME bundled directory. Start a fresh 64-bit PowerShell 7 process (pwsh -NoProfile).' }
    }
}
function Initialize-ToolkitBundledPackagePrerequisites {
    [CmdletBinding()]
    param()
    if (-not $IsWindows -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion -lt [version]'7.6.0') {
        throw 'Bundled package prerequisites require Windows in 64-bit PowerShell 7.6.0 or later.'
    }
    $roots=Get-ToolkitPackagePrerequisiteRoots
    $versions=Get-ToolkitPackagePrerequisiteVersions
    $snapshot=Get-ToolkitPackagePrerequisiteSnapshot
    Assert-ToolkitPackagePrerequisiteSnapshot -Modules $snapshot.Modules -Assemblies $snapshot.Assemblies -Roots $roots -Versions $versions
    $manifests=@{}
    # Validate BOTH manifests before importing either package tool. Never install here.
    foreach ($name in @('PackageManagement','PowerShellGet')) {
        $path=Join-Path $roots[$name] ($name+'.psd1')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bundled $name is missing: $path. Repair/review PowerShell installation; no install/uninstall attempted." }
        $data=Import-PowerShellDataFile -LiteralPath $path -ErrorAction Stop
        if (-not $data.ContainsKey('ModuleVersion') -or (ConvertTo-ToolkitPackagePrerequisiteVersion $data.ModuleVersion) -ne (ConvertTo-ToolkitPackagePrerequisiteVersion $versions[$name])) {
            throw "Bundled $name does not match tested version $($versions[$name]). Review compatibility; no fallback to user-module discovery."
        }
        $manifests[$name]=$path
    }
    foreach ($name in @('PackageManagement','PowerShellGet')) {
        $snapshot=Get-ToolkitPackagePrerequisiteSnapshot
        Assert-ToolkitPackagePrerequisiteSnapshot -Modules $snapshot.Modules -Assemblies $snapshot.Assemblies -Roots $roots -Versions $versions
        if (-not @($snapshot.Modules | Where-Object Name -eq $name).Count) {
            Import-Module -Name $manifests[$name] -Global -ErrorAction Stop -Verbose:$false | Out-Null
        }
        $snapshot=Get-ToolkitPackagePrerequisiteSnapshot
        Assert-ToolkitPackagePrerequisiteSnapshot -Modules $snapshot.Modules -Assemblies $snapshot.Assemblies -Roots $roots -Versions $versions
        if (-not @($snapshot.Modules | Where-Object Name -eq $name).Count) { throw "Bundled $name import did not yield a visible loaded module; prerequisites are not ready." }
    }
    Write-Verbose 'PSHOME package prerequisites ready: PackageManagement 1.4.8.1; PowerShellGet 2.2.5. No cloud SDK imports or tenant connections.'
}
