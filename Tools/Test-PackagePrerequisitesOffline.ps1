#Requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolkitPath,[switch]$SkipWiring)
$ErrorActionPreference='Stop'
. (Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/Private/PackagePrerequisites.ps1')
$script:Count=0
function Assert-PPTest { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAILED: $Message" }; $script:Count++ }
$roots=Get-ToolkitPackagePrerequisiteRoots
$versions=Get-ToolkitPackagePrerequisiteVersions
Assert-PPTest ($versions.PackageManagement -eq '1.4.8.1' -and $versions.PowerShellGet -eq '2.2.5') 'confirmed package versions'
Assert-ToolkitPackagePrerequisiteSnapshot -Roots $roots
Assert-PPTest $true 'clean snapshot accepted'
$good=[pscustomobject]@{Name='PackageManagement';Version=[version]'1.4.8.1';ModuleBase=$roots.PackageManagement}
Assert-ToolkitPackagePrerequisiteSnapshot -Modules @($good) -Roots $roots
Assert-PPTest $true 'correct package module accepted'
$psg=[pscustomobject]@{Name='PowerShellGet';Version=[version]'2.2.5.0';ModuleBase=$roots.PowerShellGet}
Assert-ToolkitPackagePrerequisiteSnapshot -Modules @($psg) -Roots $roots
Assert-PPTest $true 'equivalent zero-revision version accepted'
$bad=[pscustomobject]@{Name='PackageManagement';Version=[version]'1.1.0.0';ModuleBase=(Join-Path $HOME 'old-module')}
$threw=$false;try {Assert-ToolkitPackagePrerequisiteSnapshot -Modules @($bad) -Roots $roots} catch {$threw=$true}
Assert-PPTest $threw 'old module blocked'
$other=[pscustomobject]@{Name='PackageManagement';Version=[version]'1.4.8.1';ModuleBase=(Join-Path $HOME 'other-module')}
$threw=$false;try {Assert-ToolkitPackagePrerequisiteSnapshot -Modules @($other) -Roots $roots} catch {$threw=$true}
Assert-PPTest $threw 'same version from wrong root blocked'
$dll=[pscustomobject]@{Name='Microsoft.PackageManagement';Version=[version]'3.0.0.0';Location=(Join-Path $HOME 'old.dll')}
$threw=$false;try {Assert-ToolkitPackagePrerequisiteSnapshot -Assemblies @($dll) -Roots $roots} catch {$threw=$true}
Assert-PPTest $threw 'stale DLL blocked even without module'
$dllGood=[pscustomobject]@{Name='Microsoft.PackageManagement';Version=[version]'3.0.0.1';Location=(Join-Path $roots.PackageManagement 'Microsoft.PackageManagement.dll')}
Assert-ToolkitPackagePrerequisiteSnapshot -Assemblies @($dllGood) -Roots $roots
Assert-PPTest $true 'bundled DLL accepted'
$tokens=$null;$errors=$null
$helperPath=Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/Private/PackagePrerequisites.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($helperPath,[ref]$tokens,[ref]$errors)
Assert-PPTest (@($errors).Count -eq 0 -and @($ast.EndBlock.Statements | Where-Object {$_ -isnot [Management.Automation.Language.FunctionDefinitionAst]}).Count -eq 0) 'definition-only helper'
if ($SkipWiring) { Write-Host "Package prerequisite pure checks passed: $script:Count. No module imports or tenant calls."; return }
$launcher=Get-Content -LiteralPath (Join-Path $ToolkitPath 'Start-M365Toolkit.ps1') -Raw
$call=$launcher.IndexOf('    Initialize-ToolkitBundledPackagePrerequisites')
$core=$launcher.IndexOf('    Import-Module -Name $corePath')
$inventory=$launcher.IndexOf('$issues=@(Test-M365Dependencies')
Assert-PPTest ($call -gt 0 -and $call -lt $core -and $call -lt $inventory) 'preload before Core and inventory'
$public=Get-Content -LiteralPath (Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/Public/Install-M365Dependencies.ps1') -Raw
Assert-PPTest ($public.Contains('if (-not $WhatIfPreference) { Initialize-ToolkitBundledPackagePrerequisites }') -and $public.Contains('$usePSResource = if ($WhatIfPreference) { $false }')) 'install path and WhatIf guard'
Write-Host "Package prerequisite isolated checks passed: $script:Count. Pure synthetic snapshots; no module imports or tenant calls."
