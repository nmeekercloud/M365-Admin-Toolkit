BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $path = Join-Path $root 'Modules/M365Toolkit.Core/Private/ConnectionHelpers.ps1'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw 'Connection helper parse error.' }
    $definition = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Connect-ToolkitGraph'}, $true)
    # Load only this function, never the module or any actual cloud commands.
    . ([scriptblock]::Create($definition.Extent.Text))
    function Import-ToolkitModule { param($Name) throw 'Unmocked import blocked' }
    function Get-ToolkitSetting { param($Path, $Default) return $Default }
    function Write-M365Log { param($Message, $Level) }
    function Connect-MgGraph {
        [CmdletBinding()]
        param($TenantId, $Scopes, $ContextScope, [switch]$NoWelcome, [switch]$UseDeviceAuthentication)
        throw 'Unmocked network call blocked'
    }
    function Get-MgContext { [CmdletBinding()]param() throw 'Unmocked context access blocked' }
}
Describe 'Graph interactive authentication regression' {
    BeforeEach {
        $script:ToolkitGraphAuthAttempts = 0
        Mock Import-ToolkitModule {}
        Mock Get-ToolkitSetting { $false }
        Mock Write-M365Log {}
        Mock Connect-MgGraph {}
        Mock Get-MgContext { [pscustomobject]@{Account='admin@contoso.com';TokenCredentialType='InteractiveBrowser'} }
    }
    It 'uses interactive authentication by default and keeps tenant and process scope' {
        Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read')
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
            -not $UseDeviceAuthentication -and $TenantId -eq 'contoso.com' -and $ContextScope -eq 'Process' -and $Scopes -contains 'User.Read'
        }
    }
    It 'accepts a non-device-code authenticated context' {
        { Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read') } | Should -Not -Throw
    }
    It 'allows explicit device-code selection' {
        Mock Get-MgContext { [pscustomobject]@{Account='admin@contoso.com';TokenCredentialType='DeviceCode'} }
        Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read') -UseDeviceCode
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $UseDeviceAuthentication }
    }
    It 'honors a deliberately enabled local device-code setting' {
        Mock Get-ToolkitSetting { $true } -ParameterFilter { $Path -eq 'Authentication.UseDeviceCode' }
        Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read')
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $UseDeviceAuthentication }
    }
    It 'does not retry using device code when interactive login fails' {
        Mock Connect-MgGraph { throw 'Simulated interactive failure' }
        { Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read') } | Should -Throw '*Simulated interactive failure*'
        Should -Invoke Connect-MgGraph -Times 1 -Exactly
        Should -Invoke Connect-MgGraph -Times 0 -Exactly -ParameterFilter { $UseDeviceAuthentication }
    }
    It 'rejects an empty authentication context' {
        Mock Get-MgContext { $null }
        { Connect-ToolkitGraph -TenantId 'contoso.com' -Scopes @('User.Read') } | Should -Throw '*authenticated account*'
    }
    It 'disables automatic device-code defaults' {
        $settings = Import-PowerShellDataFile (Join-Path $root 'Config/Toolkit.Settings.psd1')
        $settings.Authentication.UseDeviceCode | Should -BeFalse
        $settings.Authentication.Windows10UseDeviceCode | Should -BeFalse
        $settings.Authentication.FallbackToDeviceCode | Should -BeFalse
    }
}
