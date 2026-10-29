#Requires -Version 7.0
BeforeAll {
    $PSNativeCommandUseErrorActionPreference = $false
    $root = Split-Path $PSScriptRoot -Parent
    $existingTracked = @(& git -C $root -c core.quotepath=false ls-files | Where-Object {
        Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf
    })
    $ignore = Get-Content -LiteralPath (Join-Path $root '.gitignore') -Raw
}
Describe 'Beta repository cleanup contracts (offline)' {
    It 'keeps the launcher and core module' {
        Test-Path (Join-Path $root 'Start-M365Toolkit.ps1') | Should -BeTrue
        Test-Path (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') | Should -BeTrue
    }
    It 'keeps security configuration and workflow source' {
        Test-Path (Join-Path $root '.gitleaks.toml') | Should -BeTrue
        Test-Path (Join-Path $root '.github/workflows/ci.yml') | Should -BeTrue
    }
    It 'keeps supported CSV templates' {
        Test-Path (Join-Path $root 'Templates/CSV/Bulk-User-Edits-Template.csv') | Should -BeTrue
        @(Get-ChildItem (Join-Path $root 'Templates/CSV') -Filter '*.csv' -File).Count | Should -BeGreaterThan 0
    }
    It 'has no remaining tracked backup files on disk' {
        @($existingTracked | Where-Object { $_ -match '(^|/)(\.local-backups|PatchBackups)/|\.backup-' }).Count | Should -Be 0
    }
    It 'retires the workbook and catalog inventory' {
        Test-Path (Join-Path $root 'Documentation/Testing/M365-Toolkit-Test-Tracker.xlsx') | Should -BeFalse
        Test-Path (Join-Path $root 'Documentation/Testing/Local-Catalog-Inventory.csv') | Should -BeFalse
    }
    It 'retires phase-specific documentation but keeps automated phase regression tests' {
        @(Get-ChildItem (Join-Path $root 'Documentation') -Filter 'Output-Standardization-Phase*.md').Count | Should -Be 0
        Test-Path (Join-Path $root 'Tests/OutputStandardization.Phase1.Tests.ps1') | Should -BeTrue
    }
    It 'does not allow the retired spreadsheets back through gitignore' {
        $ignore | Should -Not -Match '(?m)^!.*(?:Test-Tracker|Catalog-Inventory)'
    }
    It 'ignores representative backup and scanner-download artifacts' {
        foreach ($path in @('PatchBackups/example/file.ps1','Start-M365Toolkit.ps1.backup-example','gitleaks_8.0.0_windows_x64/gitleaks.exe','gitleaks-report.json','gitleaks-results.sarif')) {
            & git -C $root check-ignore --no-index --quiet -- $path
            $LASTEXITCODE | Should -Be 0 -Because "$path must stay local"
        }
    }
    It 'does not ignore security config or supported sample CSVs' {
        $sample = Get-ChildItem (Join-Path $root 'Templates/CSV') -Filter '*.csv' -File | Select-Object -First 1
        foreach ($path in @('.gitleaks.toml','Templates/CSV/Bulk-User-Edits-Template.csv',('Templates/CSV/' + $sample.Name))) {
            & git -C $root check-ignore --no-index --quiet -- $path
            $LASTEXITCODE | Should -Be 1 -Because "$path is maintained source"
        }
    }
    It 'provides a maintained testing guide without spreadsheet dependency' {
        $guide = Get-Content (Join-Path $root 'Documentation/Testing/Testing-Guide.md') -Raw
        $guide | Should -Match 'dedicated test tenant'
        $guide | Should -Not -Match 'M365-Toolkit-Test-Tracker\.xlsx|Local-Catalog-Inventory\.csv|Publish-TestingDocs\.ps1'
    }
    It 'removes stale foundation-only README status' {
        $readme = Get-Content (Join-Path $root 'README.md') -Raw
        $readme | Should -Not -Match 'Version 0\.1\.0 is the foundation'
        $readme | Should -Not -Match '<your-account>'
    }
}
