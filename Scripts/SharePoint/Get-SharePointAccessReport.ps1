#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$SiteUrls,[switch]$AllSites,
 [ValidateSet('RootWeb','Lists','DocumentLibraryItems')][string]$ScanScope,
 [ValidateRange(1,100000)][int]$MaxItemsPerLibrary=1000,
 [ValidateRange(1,1000)][int]$MaxLibrariesPerSite=100,
 [ValidateRange(100,1000000)][int]$MaxBufferedRows=100000,
 [string]$ExportDirectory,[string]$ReportName,
 [switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.SharePointAccessScanner.ps1')
$argsForScan=@{}; foreach ($key in $PSBoundParameters.Keys) { $argsForScan[$key]=$PSBoundParameters[$key] }
$argsForScan['WhatIf']=[bool]$WhatIfPreference
Invoke-SARReport -TaskId 'sharepoint.get-sharepointaccessreport' -Mode 'All' @argsForScan
