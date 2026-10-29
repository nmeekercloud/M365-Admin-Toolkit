function Get-ToolkitVisibleCategories {
    param([object[]] $Catalog)
    # Catalog discovery already applies category Order/Name/Id sorting.
    # Keep categories separate and preserve original category/task objects.
    return @($Catalog)
}

function Invoke-ToolkitSubcategoryMenu {
    param([Parameter(Mandatory)] $Category)
    while ($true) {
        Show-M365Header -Title $Category.Name.ToUpperInvariant()
        $children=@($Category.SubCategories); $valid=@('0')
        for ($i=0; $i -lt $children.Count; $i++) {
            $key=[string]($i+1); $valid+=$key
            Write-Host ('[{0}] {1}' -f $key,$children[$i].Name)
        }
        Write-Host '[0] Back'
        $choice=Read-M365Choice -Prompt 'Select an option' -Valid $valid
        if ($choice -eq '0') { return }
        Invoke-CategoryMenu -Category $children[([int]$choice)-1]
    }
}
