. (Join-Path $PSScriptRoot 'Toolkit.TaskFirstMenus.ps1')

function Get-ToolkitMainMenuEntries {
    param([object[]] $Catalog)
    $entries=@(); $number=1
    foreach ($category in @(Get-ToolkitVisibleCategories -Catalog $Catalog)) {
        $entries += [pscustomobject]@{Key=[string]$number;Label=$category.Name;Action='Category';Category=$category}
        $number++
    }
    foreach ($item in @(
        @('Select Tenant / Connection Options','Connect'),
        @('Switch Tenant','Switch'),
        @('Disconnect Tenant','Disconnect'),
        @('Connection Status','Status'),
        @('Toolkit Tools','Tools')
    )) {
        $entries += [pscustomobject]@{Key=[string]$number;Label=$item[0];Action=$item[1];Category=$null}
        $number++
    }
    return $entries
}

function Get-ToolkitTaskPageEntries {
    param([object[]] $Tasks,[int] $Page,[int] $PageSize=8)
    $entries=@(); $number=1
    $start=$Page*$PageSize; $end=[Math]::Min($Tasks.Count,$start+$PageSize)
    for ($i=$start; $i -lt $end; $i++) {
        $entries += [pscustomobject]@{Key=[string]$number;Action='Task';Task=$Tasks[$i];Label=$Tasks[$i].Name}
        $number++
    }
    if ($end -lt $Tasks.Count) {
        $entries += [pscustomobject]@{Key=[string]$number;Action='Next';Task=$null;Label='Next Page'}; $number++
    }
    if ($Page -gt 0) {
        $entries += [pscustomobject]@{Key=[string]$number;Action='Previous';Task=$null;Label='Previous Page'}
    }
    return $entries
}
