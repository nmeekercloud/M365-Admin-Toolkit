#Requires -Version 7.4
Describe 'Reports and Auditing baselines' {
    It 'passes isolated paging, licensing and contact rules' {
        $root=Split-Path $PSScriptRoot
        $exe=(Get-Process -Id $PID).Path
        $output=& $exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $root 'Tools/Test-ReportsAuditingOffline.ps1') -ToolkitPath $root 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
    It 'parses all three scripts and the shared helper' {
        $root=Split-Path $PSScriptRoot
        foreach ($path in @('Scripts/Reports/Get-LicenseReport.ps1','Scripts/Reports/Get-UserAccessReport.ps1','Scripts/Reports/Export-ContactList.ps1','Tools/Toolkit.ReportsAuditing.ps1')) {
            $tokens=$null; $parseErrors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $path
        }
    }
}
