#Requires -Version 7.4
[CmdletBinding()]
param([string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$definition=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Get-TenantDomains.task.psd1')
if ($definition.Status -ne 'Ready') { throw 'Task is not Ready.' }
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop }
Assert-M365TaskAccess -AccessMode $definition.AccessMode -TaskId $definition.Id
$tenant=Assert-M365Connection -Service $definition.Services -GraphScopes $definition.GraphScopes
$uri='https://graph.microsoft.com/v1.0/domains?$select=id,isDefault,isInitial,isVerified,authenticationType,supportedServices'
$domains=@()
while ($uri) {
    $parsed=[uri]$uri
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com') { throw 'Unexpected pagination URL.' }
    $response=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    foreach ($domain in @($response.value)) {
        $domains += [pscustomobject][ordered]@{
            Domain=$domain.id
            Verified=[bool]$domain.isVerified
            Default=[bool]$domain.isDefault
            Initial=[bool]$domain.isInitial
            AuthenticationType=$domain.authenticationType
            SupportedServices=(@($domain.supportedServices) -join '; ')
            TenantId=$tenant.TenantId
        }
    }
    $next=$response.PSObject.Properties['@odata.nextLink']
    $uri=if ($next) { [string]$next.Value } else { $null }
}
$domains=@($domains | Sort-Object Domain)
$columns=@('Domain','Verified','Default','Initial','AuthenticationType','SupportedServices','TenantId')
$export=Invoke-UT19Output -Tables @{'Domains.csv'=$domains} -Columns @{'Domains.csv'=$columns} -Manifest @{Task='tenant.get-tenantdomains';Status='CompletedWithinDeclaredScope';TenantId=$tenant.TenantId;Rows=$domains.Count;Scope='Graph domain inventory; not full tenant configuration'} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoOutputPrompt:$NoInteractive
Write-Host ('Result export: '+$export.Status)
if ($PassThru) {$domains}
