BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Force
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        function global:Invoke-MgGraphRequest {
            [CmdletBinding()]
            param([string]$Method,[string]$Uri,[string]$OutputType)
        }
    }
}
Describe 'Tenant option scripts' {
    BeforeEach {
        Mock Assert-M365Connection {
            [pscustomobject]@{TenantName='Contoso';TenantId='test-tenant';InitialDomain='contoso.onmicrosoft.com';DefaultDomain='contoso.com';Account='admin@contoso.com';AccountType='Member';ConnectedServices=@('Graph');ConnectedAt=[datetime]'2026-01-01'}
        }
        Mock Write-Host {}
        Mock Export-M365Csv {}
    }
    It 'displays tenant details without offering export or querying Graph again' {
        & (Join-Path $root 'Scripts/Tenant/Get-TenantDetails.ps1') | Out-Null
        Should -Invoke Export-M365Csv -Times 0 -Exactly
        Should -Invoke Assert-M365Connection -Times 1 -Exactly
    }
    It 'lists domains and offers export of structured rows' {
        Mock Invoke-MgGraphRequest {
            [pscustomobject]@{value=@(
                [pscustomobject]@{id='contoso.com';isVerified=$true;isDefault=$true;isInitial=$false;authenticationType='Managed';supportedServices=@('Email')},
                [pscustomobject]@{id='example.com';isVerified=$false;isDefault=$false;isInitial=$false;authenticationType='Managed';supportedServices=@()}
            )}
        }
        & (Join-Path $root 'Scripts/Tenant/Get-TenantDomains.ps1') | Out-Null
        Should -Invoke Export-M365Csv -Times 1 -Exactly -ParameterFilter {
            $InputObject.Count -eq 2 -and $InputObject[0].Domain -eq 'contoso.com' -and $InputObject[1].Verified -eq $false
        }
    }
    It 'does not offer a misleading export when the domain request fails' {
        Mock Invoke-MgGraphRequest { throw 'Simulated API failure' }
        { & (Join-Path $root 'Scripts/Tenant/Get-TenantDomains.ps1') | Out-Null } | Should -Throw '*Simulated API failure*'
        Should -Invoke Export-M365Csv -Times 0 -Exactly
    }
}
