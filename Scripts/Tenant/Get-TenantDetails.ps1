#Requires -Version 7.4
[CmdletBinding()]
param([string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Optional unattended export requires both ExportDirectory and ReportName.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UsersTenantOutput.ps1')
$definition=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Get-TenantDetails.task.psd1')
if ($definition.Status -ne 'Ready') { throw 'Task is not Ready.' }
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop }
Assert-M365TaskAccess -AccessMode $definition.AccessMode -TaskId $definition.Id
$tenant=Assert-M365Connection -Service $definition.Services -GraphScopes $definition.GraphScopes
$row=[pscustomobject][ordered]@{
    'Tenant name'=$tenant.TenantName
    'Tenant ID'=$tenant.TenantId
    'Initial domain'=$tenant.InitialDomain
    'Default domain'=$tenant.DefaultDomain
    'Signed in as'=$tenant.Account
    'Account type'=$tenant.AccountType
    'Connected services'=(@($tenant.ConnectedServices) -join ', ')
    'Connected at'=$tenant.ConnectedAt
}
$columns=@('Tenant name','Tenant ID','Initial domain','Default domain','Signed in as','Account type','Connected services','Connected at')
$export=Invoke-UT19Output -Tables @{'TenantDetails.csv'=@($row)} -Columns @{'TenantDetails.csv'=$columns} -Manifest @{Task='tenant.get-tenantdetails';Status='VerifiedSessionView';TenantId=$tenant.TenantId;Source='Verified toolkit session identity; not a fresh full tenant configuration audit'} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoOutputPrompt:$NoInteractive
Write-Host ('Result export: '+$export.Status)
if ($PassThru) {$row}
