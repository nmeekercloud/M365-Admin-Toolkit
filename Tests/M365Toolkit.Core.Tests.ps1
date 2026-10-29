#Requires -Modules Pester
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock stubs mirror real cmdlet parameters.')]
param()
<#
    Offline unit tests for M365Toolkit.Core. No tenant or Microsoft 365 modules are
    required: Graph / Exchange / PnP cmdlets are replaced with stubs and mocks.

    Run:  Invoke-Pester -Path .\Tests -Output Detailed
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:DataRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("m365toolkit-tests-" + [guid]::NewGuid().ToString('N'))
    $env:M365TOOLKIT_DATAROOT = $script:DataRoot

    # Stubs so Pester can mock cmdlets from modules that are not installed on the
    # test machine. Parameters mirror the real cmdlets so -ParameterFilter works.
    $stubs = @{
        'Connect-MgGraph'           = { [CmdletBinding()] param([string]$TenantId, [string[]]$Scopes, [string]$ContextScope, [switch]$NoWelcome, [switch]$UseDeviceCode) }
        'Disconnect-MgGraph'        = { [CmdletBinding()] param() }
        'Get-MgContext'             = { [CmdletBinding()] param() }
        'Invoke-MgGraphRequest'     = { [CmdletBinding()] param([string]$Method, [string]$Uri, [string]$OutputType) }
        'Connect-ExchangeOnline'    = { [CmdletBinding()] param([string]$UserPrincipalName, [switch]$ShowBanner, [switch]$Device, [switch]$DisableWAM) }
        'Disconnect-ExchangeOnline' = { [CmdletBinding(SupportsShouldProcess)] param() }
        'Get-ConnectionInformation' = { [CmdletBinding()] param() }
        'Get-PnPConnection'         = { [CmdletBinding()] param() }
        'Install-PSResource'        = { [CmdletBinding()] param([string[]]$Name,[string]$Version,[string]$Scope,[string]$Repository,[switch]$TrustRepository) }
        'Disconnect-PnPOnline'      = { [CmdletBinding()] param([switch]$ClearPersistedLogin) }
    }
    foreach ($name in $stubs.Keys) {
        if (-not (Get-Command -Name $name -ListImported -ErrorAction SilentlyContinue)) {
            New-Item -Path "Function:\global:$name" -Value $stubs[$name] -Force | Out-Null
        }
    }

    Import-Module -Name (Join-Path $script:RepoRoot 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force

    $script:TenantId = '11111111-2222-3333-4444-555555555555'
    $script:OtherId  = '99999999-8888-7777-6666-555555555555'

    function global:New-TestOrganization {
        param([string] $Id = $script:TenantId)
        [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    id              = $Id
                    displayName     = 'Contoso Ltd'
                    verifiedDomains = @(
                        [pscustomobject]@{ name = 'contoso.onmicrosoft.com'; isInitial = $true; isDefault = $false }
                        [pscustomobject]@{ name = 'contoso.com'; isInitial = $false; isDefault = $true }
                    )
                }
            )
        }
    }
}

AfterAll {
    Remove-Module -Name M365Toolkit.Core -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:DataRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\M365TOOLKIT_DATAROOT -ErrorAction SilentlyContinue
}

Describe 'Repository integrity' {
    It 'parses every PowerShell file without errors' {
        $files = Get-ChildItem -Path $script:RepoRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File
        foreach ($file in $files) {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty -Because $file.Name
        }
    }

    It 'exports exactly the functions in the Public folder' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path $script:RepoRoot 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1')
        $public   = (Get-ChildItem -Path (Join-Path $script:RepoRoot 'Modules/M365Toolkit.Core/Public') -Filter '*.ps1').BaseName
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($public | Sort-Object)
        @((Get-Command -Module M365Toolkit.Core).Name | Sort-Object) | Should -Be @($public | Sort-Object)
    }

    It 'has valid settings and menu data files' {
        $settings = Import-PowerShellDataFile -Path (Join-Path $script:RepoRoot 'Config/Toolkit.Settings.psd1')
        $settings.Dependencies.Count | Should -BeGreaterThan 0
        $menu = Import-PowerShellDataFile -Path (Join-Path $script:RepoRoot 'Config/Menu.psd1')
        @($menu.Categories.Key) | Should -Be @('1', '2', '3', '4', '5', '6', 'T')
        foreach ($category in $menu.Categories) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot "Scripts/$($category.Folder)") | Should -BeTrue
        }
    }

    It 'contains no hard-coded tenant IDs outside tests' {
        $guid  = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $files = Get-ChildItem -Path $script:RepoRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File |
            Where-Object { $_.FullName -notmatch '[\\/]Tests[\\/]' -and $_.Name -ne 'M365Toolkit.Core.psd1' }
        foreach ($file in $files) {
            (Get-Content -LiteralPath $file.FullName -Raw) | Should -Not -Match $guid -Because $file.Name
        }
    }

    It 'keeps the launcher compatible with Windows PowerShell 5.1 (so it can relaunch in PowerShell 7)' {
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) { Set-ItResult -Skipped -Because 'PSScriptAnalyzer not installed'; return }
        $settings = @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.4') } } }
        $issues = Invoke-ScriptAnalyzer -Path (Join-Path $script:RepoRoot 'Start-M365Toolkit.ps1') -IncludeRule PSUseCompatibleSyntax -Settings $settings
        $issues | Should -BeNullOrEmpty
    }
}

Describe 'Tenant helpers' {
    It 'accepts <Value> as a tenant identifier = <Expected>' -ForEach @(
        @{ Value = 'contoso.onmicrosoft.com'; Expected = $true }
        @{ Value = 'contoso.com'; Expected = $true }
        @{ Value = 'sub.contoso.co.uk'; Expected = $true }
        @{ Value = '11111111-2222-3333-4444-555555555555'; Expected = $true }
        @{ Value = 'contoso'; Expected = $false }
        @{ Value = 'https://contoso.com'; Expected = $false }
        @{ Value = ''; Expected = $false }
    ) {
        InModuleScope M365Toolkit.Core -Parameters @{ Value = $Value } { Test-TenantIdentifier -Value $Value } | Should -Be $Expected
    }

    It 'builds the SharePoint admin URL from a root URL and from the initial domain' {
        InModuleScope M365Toolkit.Core {
            ConvertTo-ToolkitSharePointAdminUrl -TenantRootUrl 'https://contoso.sharepoint.com' | Should -Be 'https://contoso-admin.sharepoint.com'
            ConvertTo-ToolkitSharePointAdminUrl -InitialDomain 'Contoso.onmicrosoft.com' | Should -Be 'https://contoso-admin.sharepoint.com'
            ConvertTo-ToolkitSharePointAdminUrl -InitialDomain 'contoso.com' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Logging' {
    BeforeEach { Set-M365FileLogging -Disable; InModuleScope M365Toolkit.Core { $script:M365Session = $null } }
    AfterEach { Set-M365FileLogging -Disable }

    It 'writes only to an explicitly selected log path' {
        $path = Join-Path $TestDrive 'selected-session.log'
        Set-M365FileLogging -Path $path -NoInteractive
        Write-M365Log -Message 'hello log' -Level Info -Quiet
        Get-Content -LiteralPath $path -Raw | Should -Match 'hello log'
    }

    It 'redacts access tokens and secrets' {
        $path = Join-Path $TestDrive 'redaction-selected.log'
        Set-M365FileLogging -Path $path -NoInteractive
        $jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U'
        Write-M365Log -Message "token $jwt and client_secret=SuperSecret123" -Level Warning -Quiet
        $content = Get-Content -LiteralPath $path -Raw
        $content | Should -Not -Match 'SuperSecret123'
        $content | Should -Not -Match 'dozjgNryP4J3'
        $content | Should -Match 'REDACTED'
    }

    It 'returns tenant-scoped, timestamped output paths' {
        $file = Get-M365OutputPath -Type Reports -FileName 'LicenseReport.csv'
        $file | Should -Match 'Reports[\\/]no-tenant[\\/]LicenseReport_\d{8}-\d{6}\.csv$'
    }
}

Describe 'Confirm-M365Action' {
    BeforeAll {
        InModuleScope M365Toolkit.Core {
            $script:M365Session = ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName 'Contoso Ltd' `
                -InitialDomain 'contoso.onmicrosoft.com' -Account 'admin@contoso.com'
        }
    }
    AfterAll { InModuleScope M365Toolkit.Core { $script:M365Session = $null } }

    It 'approves a Medium action when the user types CONFIRM' {
        Mock -ModuleName M365Toolkit.Core Read-Host { 'confirm' }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Confirm-M365Action -Action 'Test' -Impact Medium | Should -BeTrue
    }

    It 'cancels a Medium action without CONFIRM' {
        Mock -ModuleName M365Toolkit.Core Read-Host { '' }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Confirm-M365Action -Action 'Test' -Impact Medium | Should -BeFalse
    }

    It 'requires CONFIRM rather than Y for High impact actions' {
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Mock -ModuleName M365Toolkit.Core Read-Host { 'y' }
        Confirm-M365Action -Action 'Delete things' -Target 'a', 'b' -Impact High | Should -BeFalse

        Mock -ModuleName M365Toolkit.Core Read-Host { 'CONFIRM' }
        Confirm-M365Action -Action 'Delete things' -Target 'a', 'b' -Impact High | Should -BeTrue
    }

    It 'skips the prompt with -Force' {
        Mock -ModuleName M365Toolkit.Core Read-Host { throw 'should not prompt' }
        Confirm-M365Action -Action 'Test' -Impact High -Force | Should -BeTrue
    }
}

Describe 'Connect-M365 tenant verification' {
    BeforeEach {
        InModuleScope M365Toolkit.Core { $script:M365Session = $null }
        Mock -ModuleName M365Toolkit.Core Import-ToolkitModule { }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Mock -ModuleName M365Toolkit.Core Start-Process { }
        Mock -ModuleName M365Toolkit.Core Test-ToolkitIsWindows10 { $false }
        Mock -ModuleName M365Toolkit.Core Connect-MgGraph { }
        Mock -ModuleName M365Toolkit.Core Read-Host { 'y' }
        Mock -ModuleName M365Toolkit.Core Disconnect-MgGraph { }
        Mock -ModuleName M365Toolkit.Core Get-MgContext {
            [pscustomobject]@{ TenantId = '11111111-2222-3333-4444-555555555555'; Account = 'admin@contoso.com'; Scopes = @('User.Read') }
        }
        Mock -ModuleName M365Toolkit.Core Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*organization*' } { New-TestOrganization }
        Mock -ModuleName M365Toolkit.Core Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/me?*' } {
            [pscustomobject]@{ userPrincipalName = 'admin@contoso.com'; userType = 'Member' }
        }
    }

    It 'connects and records the verified tenant when a verified domain is entered' {
        Connect-M365 -TenantDomain 'contoso.com'
        $info = Get-M365TenantInfo
        $info.TenantName    | Should -Be 'Contoso Ltd'
        $info.InitialDomain | Should -Be 'contoso.onmicrosoft.com'
        $info.DefaultDomain | Should -Be 'contoso.com'
        $info.Account       | Should -Be 'admin@contoso.com'
        Should -Invoke -ModuleName M365Toolkit.Core Connect-MgGraph -Times 1 -ParameterFilter { $ContextScope -eq 'Process' -and $TenantId -eq 'contoso.com' }
    }

    It 'refuses and disconnects when the signed-in tenant does not own the requested domain' {
        { Connect-M365 -TenantDomain 'fabrikam.com' } | Should -Throw '*Tenant verification failed*'
        Should -Invoke -ModuleName M365Toolkit.Core Disconnect-MgGraph -Times 1
        Get-M365TenantInfo | Should -BeNullOrEmpty
    }

    It 'refuses guest accounts' {
        Mock -ModuleName M365Toolkit.Core Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/me?*' } {
            [pscustomobject]@{ userPrincipalName = 'admin_partner.com#EXT#@contoso.onmicrosoft.com'; userType = 'Guest' }
        }
        { Connect-M365 -TenantDomain 'contoso.com' } | Should -Throw '*GUEST*'
        Get-M365TenantInfo | Should -BeNullOrEmpty
    }

    It 'will not connect to a second tenant without Switch-M365Tenant' {
        Connect-M365 -TenantDomain 'contoso.com'
        { Connect-M365 -TenantDomain 'fabrikam.com' } | Should -Throw '*Switch-M365Tenant*'
    }

    It 'offers device code when interactive sign-in fails and retries if approved' {
        Mock -ModuleName M365Toolkit.Core Read-Host { 'y' }
        Mock -ModuleName M365Toolkit.Core Connect-MgGraph -ParameterFilter { -not $UseDeviceCode } { throw 'WAM failed' }
        Mock -ModuleName M365Toolkit.Core Connect-MgGraph -ParameterFilter { $UseDeviceCode } { }
        Connect-M365 -TenantDomain 'contoso.com'
        Should -Invoke -ModuleName M365Toolkit.Core Connect-MgGraph -Times 1 -ParameterFilter { $UseDeviceCode }
    }

    It 'disconnects Exchange Online when it lands in a different tenant' {
        Mock -ModuleName M365Toolkit.Core Connect-ExchangeOnline { }
        Mock -ModuleName M365Toolkit.Core Disconnect-ExchangeOnline { }
        Mock -ModuleName M365Toolkit.Core Get-ConnectionInformation {
            [pscustomobject]@{ State = 'Connected'; IsEopSession = $false; TenantID = '99999999-8888-7777-6666-555555555555'; UserPrincipalName = 'admin@contoso.com'; TokenStatus = 'Active' }
        }
        { Connect-M365 -TenantDomain 'contoso.com' -Service ExchangeOnline } | Should -Throw '*Tenant verification failed*'
        Should -Invoke -ModuleName M365Toolkit.Core Disconnect-ExchangeOnline -Times 1
    }

    It 'connects Exchange Online with the Graph account when tenants match' {
        Mock -ModuleName M365Toolkit.Core Connect-ExchangeOnline { }
        Mock -ModuleName M365Toolkit.Core Get-ConnectionInformation {
            [pscustomobject]@{ State = 'Connected'; IsEopSession = $false; TenantID = '11111111-2222-3333-4444-555555555555'; UserPrincipalName = 'admin@contoso.com'; TokenStatus = 'Active' }
        }
        Connect-M365 -TenantDomain 'contoso.com' -Service ExchangeOnline
        # Already-connected EXO in the same tenant is reused, not reconnected.
        Should -Invoke -ModuleName M365Toolkit.Core Connect-ExchangeOnline -Times 0
        (Get-M365ConnectionStatus | Where-Object Service -eq 'ExchangeOnline').TenantMatch | Should -BeTrue
    }
}

Describe 'Disconnect-M365' {
    It 'clears the session' {
        InModuleScope M365Toolkit.Core {
            $script:M365Session = ConvertTo-ToolkitSession -TenantId '11111111-2222-3333-4444-555555555555' -TenantName 'Contoso Ltd' `
                -InitialDomain 'contoso.onmicrosoft.com' -Account 'admin@contoso.com'
        }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Mock -ModuleName M365Toolkit.Core Get-MgContext { $null }
        Mock -ModuleName M365Toolkit.Core Get-ConnectionInformation { $null }
        Disconnect-M365
        Get-M365TenantInfo | Should -BeNullOrEmpty
    }
}

Describe 'Test-M365Dependencies' {
    It 'reports Missing, Outdated, OK and Graph VersionMismatch correctly' {
        Mock -ModuleName M365Toolkit.Core Get-Module -ParameterFilter { $ListAvailable } {
            @(
                [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; Version = [version]'2.42.0'; Path = 'x' }
                [pscustomobject]@{ Name = 'Microsoft.Graph.Users'; Version = [version]'2.41.1'; Path = 'x' }
                [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; Version = [version]'3.9.0'; Path = 'x' }
            )
        }
        $results = Test-M365Dependencies
        ($results | Where-Object Name -eq 'Microsoft.Graph.Authentication').Status | Should -Be 'OK'
        ($results | Where-Object Name -eq 'Microsoft.Graph.Users').Status | Should -Be 'VersionMismatch'
        ($results | Where-Object Name -eq 'Microsoft.Graph.Groups').Status | Should -Be 'Missing'
        ($results | Where-Object Name -eq 'ExchangeOnlineManagement').Status | Should -Be 'Outdated'
        ($results | Where-Object Name -eq 'PnP.PowerShell') | Should -BeNullOrEmpty
        (Test-M365Dependencies -IncludeOptional | Where-Object Name -eq 'PnP.PowerShell').Status | Should -Be 'Missing'
    }

    It 'works on a clean machine with nothing installed' {
        Mock -ModuleName M365Toolkit.Core Get-Module -ParameterFilter { $ListAvailable } { }
        $results = @(Test-M365Dependencies -IncludeOptional)
        @($results | Where-Object { $_.Name -ne 'PowerShell' -and $_.Status -ne 'Missing' }) | Should -BeNullOrEmpty
    }

    It 'prints the report and installs nothing when the user declines' {
        Mock -ModuleName M365Toolkit.Core Get-Module { }
        Mock -ModuleName M365Toolkit.Core Write-Host { }
        Mock -ModuleName M365Toolkit.Core Read-Host { 'n' }
        Mock -ModuleName M365Toolkit.Core Install-PSResource { throw 'should not install' }
        { Install-M365Dependencies -IncludeOptional } | Should -Not -Throw
        Should -Invoke -ModuleName M365Toolkit.Core Install-PSResource -Times 0
    }
}
