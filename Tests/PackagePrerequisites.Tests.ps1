#Requires -Version 7.4
BeforeAll {
    $root=Split-Path $PSScriptRoot
    . (Join-Path $root 'Modules/M365Toolkit.Core/Private/PackagePrerequisites.ps1')
}
Describe 'Bundled package prerequisite safety' {
    BeforeEach {
        $script:Loaded=[System.Collections.Generic.List[object]]::new()
        $script:Imports=[System.Collections.Generic.List[string]]::new()
        $script:Roots=Get-ToolkitPackagePrerequisiteRoots
        Mock Get-ToolkitPackagePrerequisiteSnapshot { [pscustomobject]@{Modules=@($script:Loaded.ToArray());Assemblies=@()} }
        Mock Test-Path { $true }
        Mock Import-PowerShellDataFile {
            if ($LiteralPath -match 'PackageManagement') { @{ModuleVersion='1.4.8.1'} } else { @{ModuleVersion='2.2.5'} }
        }
        Mock Import-Module {
            $name=[IO.Path]::GetFileNameWithoutExtension($Name)
            $script:Imports.Add($name)
            $version=if ($name -eq 'PackageManagement') {'1.4.8.1'} else {'2.2.5'}
            $script:Loaded.Add([pscustomobject]@{Name=$name;Version=[version]$version;ModuleBase=$script:Roots[$name]})
        }
    }
    It 'loads the explicit PSHOME package manifests in confirmed order' {
        Initialize-ToolkitBundledPackagePrerequisites
        ($script:Imports -join ',') | Should -Be 'PackageManagement,PowerShellGet'
        Should -Invoke Import-Module -Times 2 -Exactly -ParameterFilter { $Global -and $Name.StartsWith($PSHOME,[StringComparison]::OrdinalIgnoreCase) }
    }
    It 'does not import a second time when the bundled copies are already loaded' {
        Initialize-ToolkitBundledPackagePrerequisites
        Initialize-ToolkitBundledPackagePrerequisites
        Should -Invoke Import-Module -Times 2 -Exactly
    }
    It 'blocks an old user module before importing anything' {
        $script:Loaded.Add([pscustomobject]@{Name='PackageManagement';Version=[version]'1.1.0.0';ModuleBase=(Join-Path $HOME 'OldPackageManagement')})
        { Initialize-ToolkitBundledPackagePrerequisites } | Should -Throw '*already loaded*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'blocks a non-bundled copy even if the version matches' {
        $script:Loaded.Add([pscustomobject]@{Name='PackageManagement';Version=[version]'1.4.8.1';ModuleBase=(Join-Path $HOME 'OtherPackageManagement')})
        { Initialize-ToolkitBundledPackagePrerequisites } | Should -Throw '*outside*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'validates both manifests before any import' {
        Mock Import-PowerShellDataFile { if ($LiteralPath -match 'PackageManagement') { @{ModuleVersion='1.4.8.1'} } else { @{ModuleVersion='9.9.9'} } }
        { Initialize-ToolkitBundledPackagePrerequisites } | Should -Throw '*does not match*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'blocks missing manifests without attempting installation' {
        Mock Test-Path { $false }
        { Initialize-ToolkitBundledPackagePrerequisites } | Should -Throw '*missing*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'detects an old DLL with no visible module' {
        $a=[pscustomobject]@{Name='Microsoft.PackageManagement';Version=[version]'3.0.0.0';Location=(Join-Path $HOME 'old.dll')}
        { Assert-ToolkitPackagePrerequisiteSnapshot -Assemblies @($a) } | Should -Throw '*DLL*'
    }
}
Describe 'Startup wiring and offline import contracts' {
    It 'prepares package tools before Core import and dependency inspection, independent of SkipDependencyCheck' {
        $root=Split-Path $PSScriptRoot
        $text=Get-Content -LiteralPath (Join-Path $root 'Start-M365Toolkit.ps1') -Raw
        $call=$text.IndexOf('    Initialize-ToolkitBundledPackagePrerequisites')
        $core=$text.IndexOf('    Import-Module -Name $corePath')
        $inventory=$text.IndexOf('$issues=@(Test-M365Dependencies')
        $call | Should -BeGreaterThan 0
        $call | Should -BeLessThan $core
        $call | Should -BeLessThan $inventory
    }
    It 'keeps prerequisite helper import definition-only' {
        $root=Split-Path $PSScriptRoot
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Modules/M365Toolkit.Core/Private/PackagePrerequisites.ps1'),[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        @($ast.EndBlock.Statements | Where-Object { $_ -isnot [Management.Automation.Language.FunctionDefinitionAst] }).Count | Should -Be 0
    }
}
