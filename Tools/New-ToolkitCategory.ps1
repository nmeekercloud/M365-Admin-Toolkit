#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Folder,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9.-]*$')][string] $Id,
    [Parameter(Mandatory)][string] $Name,
    [int] $Order=100,
    [string] $ToolkitPath=(Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Toolkit.Catalog.ps1')
$catalog=@(Get-ToolkitCatalog -Root $ToolkitPath)
if ($catalog.Id -contains $Id -or $catalog.Folder -contains $Folder) { throw 'Category ID or folder already registered.' }
$path=Join-Path $ToolkitPath "Scripts/$Folder/Category.psd1"
if (Test-Path -LiteralPath $path) { throw 'Category file already exists.' }
$quote={param($s) "'" + ([string]$s).Replace("'","''") + "'"}
$content="@{`n    Id = $(& $quote $Id)`n    Name = $(& $quote $Name)`n    Order = $Order`n}`n"
if ($PSCmdlet.ShouldProcess($path,'Create category definition')) {
    $null=New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force
    [IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
    Write-Host 'Category created. Press R at the main menu to discover it.'
}
