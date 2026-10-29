#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.NumericMenus.ps1')
function Assert-SplitMenuTest([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
$spTask=[pscustomobject]@{Id='sharepoint.example';Name='Test SP';Path='Scripts/SharePoint/example.ps1';Status='Ready';Services=@('Graph','SharePoint');GraphScopes=@('Sites.Read.All')}
$odTask=[pscustomobject]@{Id='onedrive.example';Name='Test OD';Path='Scripts/OneDrive/example.ps1';Status='Ready';Services=@('Graph','SharePoint');GraphScopes=@('User.Read.All')}
$catalog=@(
 [pscustomobject]@{Id='users';Name='User Management';Order=10;Tasks=@()},
 [pscustomobject]@{Id='groups';Name='Group Management';Order=20;Tasks=@()},
 [pscustomobject]@{Id='sharepoint';Name='SharePoint Administration';Order=30;Tasks=@($spTask)},
 [pscustomobject]@{Id='onedrive';Name='OneDrive Administration';Order=40;Tasks=@($odTask)},
 [pscustomobject]@{Id='exchange';Name='Exchange Online';Order=50;Tasks=@()},
 [pscustomobject]@{Id='custom';Name='Custom';Order=60;Tasks=@()}
)
$visible=@(Get-ToolkitVisibleCategories -Catalog $catalog)
Assert-SplitMenuTest ($visible.Count -eq $catalog.Count) 'A category was merged/lost.'
$entries=@(Get-ToolkitMainMenuEntries -Catalog $catalog)
$cats=@($entries | Where-Object Action -eq 'Category')
Assert-SplitMenuTest ($cats[2].Key -eq '3' -and $cats[2].Category.Id -eq 'sharepoint') 'SharePoint must be main option 3 in this catalog.'
Assert-SplitMenuTest ($cats[3].Key -eq '4' -and $cats[3].Category.Id -eq 'onedrive') 'OneDrive must be main option 4 in this catalog.'
Assert-SplitMenuTest (@($cats | Where-Object Label -eq 'SharePoint & OneDrive').Count -eq 0) 'Synthetic combined category still present.'
Assert-SplitMenuTest ($cats[2].Category.Tasks[0].Path -eq $spTask.Path -and $cats[3].Category.Tasks[0].Path -eq $odTask.Path) 'Task paths changed.'
Assert-SplitMenuTest ($cats[3].Category.Tasks[0].GraphScopes[0] -eq 'User.Read.All' -and $cats[3].Category.Tasks[0].Status -eq 'Ready') 'Task metadata changed.'
Assert-SplitMenuTest (@($entries.Key | Select-Object -Unique).Count -eq $entries.Count) 'Duplicate menu keys.'
Assert-SplitMenuTest (($entries.Key -join ',') -eq ((1..$entries.Count) -join ',')) 'Keys are not sequential, including multi-digit controls.'
Assert-SplitMenuTest (@($entries | Where-Object Action -eq 'Disconnect').Count -eq 1) 'Disconnect action lost/duplicated.'
Assert-SplitMenuTest (@($entries | Where-Object Action -eq 'Tools').Count -eq 1) 'Tools action lost/duplicated.'
$single=@(Get-ToolkitMainMenuEntries -Catalog @($catalog[2]))
Assert-SplitMenuTest (@($single | Where-Object Action -eq 'Category').Count -eq 1) 'Single category failed.'
$empty=@(Get-ToolkitMainMenuEntries -Catalog @())
Assert-SplitMenuTest ($empty.Count -eq 5) 'Empty catalog must still expose five existing controls.'
$page=@(Get-ToolkitTaskPageEntries -Tasks @($spTask) -Page 0)
Assert-SplitMenuTest ($page.Count -eq 1 -and $page[0].Task.Id -eq $spTask.Id) 'Task pagination/routing changed.'
Write-Host 'Split-menu regression tests passed. Synthetic catalog; no authentication or tenant calls.' -ForegroundColor Green
