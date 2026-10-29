BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools/Toolkit.Catalog.ps1')
}
Describe 'Catalog auto-discovery' {
    BeforeEach {
        $root=Join-Path $TestDrive ('toolkit-' + [IO.Path]::GetRandomFileName())
        $folder=Join-Path $root 'Scripts/Example'
        $null=New-Item -Path $folder -ItemType Directory -Force
        "@{ Id='example'; Name='Example'; Order=10 }" | Set-Content (Join-Path $folder 'Category.psd1')
        $task="@{ Id='example.report'; Name='Report'; Description='Sample'; Script='Get-Report.ps1'; Order=10; Status='Planned'; Services=@('Graph'); GraphScopes=@() }"
        $task | Set-Content (Join-Path $folder 'Get-Report.task.psd1')
    }
    It 'discovers a new category and planned task without launcher edits or a script' {
        $catalog=@(Get-ToolkitCatalog -Root $root)
        $catalog.Count | Should -Be 1
        $catalog[0].Key | Should -Be '1'
        $catalog[0].Tasks[0].Status | Should -Be 'Planned'
    }
    It 'rejects a missing Ready script' {
        $task.Replace("Status='Planned'","Status='Ready'") | Set-Content (Join-Path $folder 'Get-Report.task.psd1')
        { Get-ToolkitCatalog -Root $root } | Should -Throw '*missing*'
    }
    It 'rejects script paths outside the category' {
        $task.Replace('Get-Report.ps1','../Get-Report.ps1') | Set-Content (Join-Path $folder 'Get-Report.task.psd1')
        { Get-ToolkitCatalog -Root $root } | Should -Throw '*Unsafe*'
    }
    It 'rejects duplicate task IDs' {
        $task | Set-Content (Join-Path $folder 'Duplicate.task.psd1')
        { Get-ToolkitCatalog -Root $root } | Should -Throw '*duplicate*'
    }
    It 'ignores legacy keys and assigns sequential numbers' {
        "@{ Id='example'; Name='Example'; Order=10; Key='7' }" | Set-Content (Join-Path $folder 'Category.psd1')
        { Get-ToolkitCatalog -Root $root } | Should -Not -Throw
    }
}
