#Requires -Version 7.0
BeforeAll {
    $PSNativeCommandUseErrorActionPreference = $false
    $root = Split-Path $PSScriptRoot -Parent
    $catalog = Import-PowerShellDataFile (Join-Path $root 'Config/BulkCsvTemplates.psd1')
    . (Join-Path $root 'Tools/Toolkit.BulkCsvTemplates.ps1')
    $newRelative = 'Templates/CSV/Bulk-User-Edits-Template.csv'
    $header = 'Action,UserPrincipalName,DisplayName,Department,JobTitle,OfficeLocation'
}
Describe 'Template relocation and changelog retirement (offline)' {
    It 'points the user template registry at Templates/CSV' {
        $catalog.Users.Template | Should -BeExactly $newRelative
        (Get-ToolkitBulkCsvDefinition -ToolkitRoot $root -Kind Users).Template | Should -BeExactly $newRelative
    }
    It 'ships the unchanged header without customer rows' {
        $file = Join-Path $root $newRelative
        [IO.File]::ReadAllText($file).Trim() | Should -BeExactly $header
        @(Import-Csv -LiteralPath $file).Count | Should -Be 0
    }
    It 'removes the old root template and stale changelog' {
        Test-Path -LiteralPath (Join-Path $root 'Bulk-User-Edits-Template.csv') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'CHANGELOG.md') | Should -BeFalse
    }
    It 'keeps all registered blank templates under Templates/CSV with matching schemas' {
        foreach ($kind in $catalog.Keys) {
            $definition = $catalog[$kind]
            $definition.Template | Should -Match '^Templates/CSV/'
            [IO.File]::ReadAllText((Join-Path $root $definition.Template)).Trim() | Should -BeExactly ($definition.Columns -join ',')
        }
    }
    It 'displays the relocated path without requesting input for a supplied CSV path' {
        Mock Write-Host {}
        Mock Read-Host { throw 'Unexpected prompt' }
        Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind Users -CsvPath 'private-working-copy.csv' | Should -Be 'private-working-copy.csv'
        $expected = Join-Path $root $newRelative
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like ('*' + $expected) }
        Should -Invoke Read-Host -Times 0
    }
    It 'saves a blank user template to a disposable external working file only' {
        Mock Write-Host {}
        Mock Read-Host { throw 'Unexpected prompt' }
        $destination = Join-Path $TestDrive 'user-working-copy.csv'
        (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users -Path $destination).Status | Should -Be 'Saved'
        [IO.File]::ReadAllText($destination).Trim() | Should -BeExactly $header
        @(Import-Csv -LiteralPath $destination).Count | Should -Be 0
    }
    It 'continues to block working copies inside the repository' {
        $destination = Join-Path $root 'must-not-write.csv'
        Test-Path -LiteralPath $destination | Should -BeFalse
        (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users -Path $destination -WarningAction SilentlyContinue).Status | Should -Be 'SaveFailed'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }
    It 'tracks only the allowed template path and not arbitrary customer CSVs' {
        foreach ($path in @($newRelative,'Templates/CSV/Bulk-Group-Members-Template.csv','Templates/CSV/Bulk-SharePoint-Access-Template.csv')) {
            & git -C $root check-ignore --no-index --quiet -- $path
            $LASTEXITCODE | Should -Be 1
        }
        foreach ($path in @('Bulk-User-Edits-Template.csv','private-customer.csv')) {
            & git -C $root check-ignore --no-index --quiet -- $path
            $LASTEXITCODE | Should -Be 0
        }
        Get-Content (Join-Path $root '.gitignore') -Raw | Should -Not -Match '(?m)^!/Bulk-User-Edits-Template\.csv\s*$'
    }
    It 'preserves scanner configuration and existing regression suites' {
        Test-Path -LiteralPath (Join-Path $root '.gitleaks.toml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'Tests/Gitleaks.Configuration.Tests.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'Tests/BulkCsvTemplates.Tests.ps1') | Should -BeTrue
    }
    It 'documents the relocated blank template and valid local link' {
        $guide = Get-Content (Join-Path $root 'Documentation/Bulk-CSV-Templates.md') -Raw
        $guide | Should -Match ([regex]::Escape($newRelative))
        $guide | Should -Not -Match 'existing root Bulk-User-Edits'
        $csvReadme = Get-Content (Join-Path $root 'Templates/CSV/README.md') -Raw
        $csvReadme | Should -Match '\[Bulk User Edits\]\(Bulk-User-Edits-Template\.csv\)'
    }
}
