@{
    RootModule           = 'M365Toolkit.Core.psm1'
    ModuleVersion        = '0.3.4'
    GUID                 = '6f3c2a8e-4b7d-4e1a-9c5f-2d8b1e7a3c90'
    Author               = 'M365-Admin-Toolkit contributors'
    CompanyName          = 'Community'
    Copyright            = '(c) 2026 M365-Admin-Toolkit contributors. MIT License.'
    Description          = 'Shared framework for M365-Admin-Toolkit: connection management, tenant verification, logging, confirmations, dependency checks, and console UI.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        # Connection management
        'Connect-M365'
        'Disconnect-M365'
        'Switch-M365Tenant'
        'Assert-M365Connection'
        'Assert-M365TaskAccess'
        'Set-M365TaskPolicy'
        'Get-M365ConnectionStatus'
        'Get-M365TenantInfo'
        'Show-M365ConnectionStatus'
        'Get-M365SharePointConnection'
        # Dependencies
        'Test-M365Dependencies'
        'Install-M365Dependencies'
        # Logging and paths
        'Write-M365Log'
        'Get-M365LogPath'
        'Get-M365OutputPath'
        'Export-M365Csv'
        'Show-M365Results'
        'Set-M365FileLogging'
        # Safeguards
        'Confirm-M365Action'
        # Console UI
        'Show-M365Header'
        'Read-M365Choice'
        'Wait-M365KeyPress'
        # Toolkit info
        'Get-M365ToolkitInfo'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Microsoft365', 'M365', 'ExchangeOnline', 'MicrosoftGraph', 'SharePoint', 'Admin', 'MSP')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
