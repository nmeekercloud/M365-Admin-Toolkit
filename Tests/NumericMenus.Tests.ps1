BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools/Toolkit.NumericMenus.ps1')
}
Describe 'Numeric menu routing' {
    It 'numbers categories and controls sequentially without collisions' {
        $categories=@([pscustomobject]@{Name='Users'},[pscustomobject]@{Name='Tenant'})
        $menu=@(Get-ToolkitMainMenuEntries -Catalog $categories)
        @($menu.Key) | Should -Be @('1','2','3','4','5','6','7')
        @($menu | Where-Object Action -eq 'Disconnect').Count | Should -Be 1
    }
    It 'numbers page actions and task selections uniquely' {
        $tasks=@(1..18 | ForEach-Object { [pscustomobject]@{Name="Task $_"} })
        $page=@(Get-ToolkitTaskPageEntries -Tasks $tasks -Page 1)
        @($page.Key) | Should -Be @('1','2','3','4','5','6','7','8','9','10')
        $page[0].Task.Name | Should -Be 'Task 9'
        $page[8].Action | Should -Be 'Next'
        $page[9].Action | Should -Be 'Previous'
    }
}
