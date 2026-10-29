# Pester 5 tests; snapshots are synthetic. No service-module imports or tenant calls.
BeforeAll {
    $root=Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'Modules/M365Toolkit.Core/Private/DependencyCompatibility.ps1')
    $script:compatRoot=$root
}
Describe 'Windows dependency compatibility profile' {
    It 'pins the five modules to the observed working profile' {
        $p=Get-ToolkitCompatibilityProfile
        $p['PackageManagement'] | Should -Be '1.4.8.1'
        $p['PowerShellGet'] | Should -Be '2.2.5'
        $p['PnP.PowerShell'] | Should -Be '3.3.0'
        $p['Microsoft.Graph.Authentication'] | Should -Be '2.41.2'
        $p['ExchangeOnlineManagement'] | Should -Be '3.10.1'
    }
    It 'accepts an empty process snapshot' {
        { Assert-ToolkitCompatibilitySnapshot } | Should -Not -Throw
    }
    It 'accepts the pinned PnP version' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='PnP.PowerShell';Version=[version]'3.3.0';ModuleBase='synthetic'}) } | Should -Not -Throw
    }
    It 'rejects loaded PnP 3.4.1 before doing any import' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='PnP.PowerShell';Version=[version]'3.4.1';ModuleBase='synthetic'}) } | Should -Throw '*Start a fresh*'
    }
    It 'rejects loaded old PackageManagement DLL even without a module object' {
        { Assert-ToolkitCompatibilitySnapshot -PackageAssemblies @([pscustomobject]@{Name='Microsoft.PackageManagement';Version=[version]'3.0.0.0';Location='synthetic'}) } | Should -Throw '*Old Microsoft.PackageManagement*'
    }
    It 'rejects a bundled-version module loaded from another directory' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='PowerShellGet';Version=[version]'2.2.5';ModuleBase='synthetic-other-root'}) } | Should -Throw '*different location*'
    }
    It 'accepts bundled package modules at their expected roots' {
        $roots=Get-ToolkitBundledPackageRoots
        $m=@([pscustomobject]@{Name='PackageManagement';Version=[version]'1.4.8.1';ModuleBase=$roots.PackageManagement},[pscustomobject]@{Name='PowerShellGet';Version=[version]'2.2.5';ModuleBase=$roots.PowerShellGet})
        { Assert-ToolkitCompatibilitySnapshot -Modules $m } | Should -Not -Throw
    }
    It 'does not block unrelated modules' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='Synthetic.Unrelated';Version=[version]'99.0';ModuleBase='synthetic'}) } | Should -Not -Throw
    }
    It 'rejects a non-profile Graph authentication version' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'2.38.1';ModuleBase='synthetic'}) } | Should -Throw '*Incompatible module*'
    }
    It 'keeps core import offline while retaining the service-load compatibility boundary' {
        $text=[IO.File]::ReadAllText((Join-Path $script:compatRoot 'Modules/M365Toolkit.Core/M365Toolkit.Core.psm1'))
        $text | Should -Not -Match '(?m)^Initialize-ToolkitDependencyCompatibility\s*$'
        $loader=[IO.File]::ReadAllText((Join-Path $script:compatRoot 'Modules/M365Toolkit.Core/Private/TenantHelpers.ps1'))
        $loader | Should -Match 'Initialize-ToolkitDependencyCompatibility'
        $probes=[IO.File]::ReadAllText((Join-Path $script:compatRoot 'Modules/M365Toolkit.Core/Private/ConnectionHelpers.ps1'))
        $probes | Should -Match "Get-Command -Name 'Get-MgContext' -ListImported"
        $probes | Should -Match "Get-Command -Name 'Get-ConnectionInformation' -ListImported"
    }
    It 'accepts the same Graph version with an explicit zero revision' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'2.41.2.0';ModuleBase='synthetic'}) } | Should -Not -Throw
    }
    It 'still rejects an actual nonzero revision change' {
        { Assert-ToolkitCompatibilitySnapshot -Modules @([pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'2.41.2.1';ModuleBase='synthetic'}) } | Should -Throw '*Incompatible module*'
    }
    It 'normalizes absent version components without losing actual revisions' {
        (ConvertTo-ToolkitComparableVersion ([version]'2.41.2')) | Should -Be ([version]'2.41.2.0')
        (ConvertTo-ToolkitComparableVersion ([version]'2.41.2.1')) | Should -Be ([version]'2.41.2.1')
    }
    It 'accepts all service pins with explicit zero revision' {
        $modules=@(
            [pscustomobject]@{Name='PnP.PowerShell';Version=[version]'3.3.0.0';ModuleBase='synthetic'}
            [pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'2.41.2.0';ModuleBase='synthetic'}
            [pscustomobject]@{Name='ExchangeOnlineManagement';Version=[version]'3.10.1.0';ModuleBase='synthetic'}
        )
        { Assert-ToolkitCompatibilitySnapshot -Modules $modules } | Should -Not -Throw
    }
}
