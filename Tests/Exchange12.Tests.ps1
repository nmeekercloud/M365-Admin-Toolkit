#Requires -Version 7.4
Describe 'Exchange Online tasks 1 and 2 offline checks' {
    It 'passes isolated helper tests without connecting to a tenant' {
        $exe=(Get-Process -Id $PID).Path
        $root=Split-Path $PSScriptRoot
        $output=& $exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $root 'Tools/Test-Exchange12Offline.ps1') -ToolkitPath $root 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
    It 'parses the two task scripts and shared helper' {
        $root=Split-Path $PSScriptRoot
        foreach ($relative in @('Scripts/Exchange/Copy-MailboxPermissions.ps1','Scripts/Exchange/Invoke-SharedMailboxManagement.ps1','Tools/Toolkit.Exchange12.ps1')) {
            $tokens=$null; $parseErrors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $relative
        }
    }
}
