#Requires -Version 7.4
[CmdletBinding()]
param([string] $ToolkitPath = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Toolkit.Catalog.ps1')
$catalog=@(Get-ToolkitCatalog -Root $ToolkitPath)
$tasks=@($catalog | ForEach-Object { $_.Tasks })
[pscustomobject]@{Categories=$catalog.Count;Tasks=$tasks.Count;Ready=@($tasks | Where-Object Status -eq 'Ready').Count;Planned=@($tasks | Where-Object Status -eq 'Planned').Count;Disabled=@($tasks | Where-Object Status -eq 'Disabled').Count} | Format-List
Write-Host 'Catalog validation passed. This does not verify API permissions, security, or task behavior.' -ForegroundColor Green
