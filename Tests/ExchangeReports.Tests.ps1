#Requires -Version 7.4
Describe 'Exchange read-only report baselines' {
    It 'passes isolated rule and trace continuation checks' {
        $root=Split-Path $PSScriptRoot
        $exe=(Get-Process -Id $PID).Path
        $output=& $exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $root 'Tools/Test-ExchangeReportsOffline.ps1') -ToolkitPath $root 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
    It 'parses the two reporting scripts and helper' {
        $root=Split-Path $PSScriptRoot
        foreach ($path in @('Scripts/Exchange/Search-InboxRules.ps1','Scripts/Exchange/Get-MessageTraceReport.ps1','Tools/Toolkit.ExchangeReports.ps1')) {
            $tokens=$null; $parseErrors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $path
        }
    }
}
