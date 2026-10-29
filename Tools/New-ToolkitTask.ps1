#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Category,
    [string] $Name,
    [string] $Id,
    [string] $Script,
    [string] $Description,
    [int] $Order=100,
    [ValidateSet('Graph','ExchangeOnline','SharePoint')][string[]] $Services=@('Graph'),
    [string[]] $GraphScopes=@(),
    [ValidateSet('ReadOnly','Changes')][string] $AccessMode='Changes',
    [switch] $Changes,
    [string] $ToolkitPath=(Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Toolkit.Catalog.ps1')
$catalog=@(Get-ToolkitCatalog -Root $ToolkitPath)
if (-not $Category) {
    $catalog | ForEach-Object { Write-Host "$($_.Id) : $($_.Name)" }
    $Category=Read-Host 'Category ID'
}
$c=@($catalog | Where-Object Id -eq $Category)
if ($c.Count -ne 1) { throw 'Choose an existing category ID.' }
if (-not $Name) { $Name=Read-Host 'Task display name' }
if (-not $Id) { $Id=Read-Host 'Unique task ID (for example groups.my-report)' }
if (-not $Script) { $Script=Read-Host 'Script filename (for example Get-MyReport.ps1)' }
if (-not $Description) { $Description=Read-Host 'Short description' }
if ($Id -notmatch '^[a-z][a-z0-9.-]*$') { throw 'Invalid task ID.' }
$allIds=@($catalog.Id)+@($catalog | ForEach-Object { $_.Tasks.Id })
if ($Id -in $allIds) { throw 'ID already exists.' }
if ($Script -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*\.ps1$') { throw 'Use a plain .ps1 filename, without a path.' }
$folder=Join-Path $ToolkitPath ('Scripts/'+$c[0].Folder)
$scriptPath=Join-Path $folder $Script
$metaPath=Join-Path $folder ([IO.Path]::GetFileNameWithoutExtension($Script)+'.task.psd1')
if ((Test-Path -LiteralPath $scriptPath) -or (Test-Path -LiteralPath $metaPath)) { throw 'Script or definition already exists; existing files will not be overwritten.' }
$quote={param($s) "'" + ([string]$s).Replace("'","''") + "'"}
$svc=(@($Services | ForEach-Object { & $quote $_ }) -join ', ')
$scope=(@($GraphScopes | ForEach-Object { & $quote $_ }) -join ', ')
$meta="@{`n    Id = $(& $quote $Id)`n    Name = $(& $quote $Name)`n    Description = $(& $quote $Description)`n    Script = $(& $quote $Script)`n    Order = $Order`n    Status = 'Planned'`n    Services = @($svc)`n    GraphScopes = @($scope)`n}`n"
if ($Changes) { $AccessMode='Changes' }
$meta=$meta.Replace("    Status = 'Planned'", "    Status = 'Planned'`n    AccessMode = '$AccessMode'`n    PermissionReview = 'Unreviewed'")
$template=Get-Content -LiteralPath (Join-Path $ToolkitPath 'Templates/Discoverable-Task.ps1') -Raw
$template=$template.Replace('__TASK_META__',[IO.Path]::GetFileName($metaPath))
if ($Changes) { $template=$template.Replace('# READ-ONLY TASK TEMPLATE','# CHANGE TASK: implement plan, Confirm-M365Action, backup, and ShouldProcess before enabling.') }
if ($PSCmdlet.ShouldProcess($folder,'Create Planned task definition and script scaffold')) {
    [IO.File]::WriteAllText($metaPath,$meta,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($scriptPath,$template,[Text.UTF8Encoding]::new($false))
    Write-Host 'Created as Planned. Implement, test, and review before changing Status to Ready.'
    Write-Host $scriptPath
}
