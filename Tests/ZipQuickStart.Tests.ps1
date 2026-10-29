#Requires -Version 7.0
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'))
    $section = [regex]::Match($readme,'(?ms)^## Quick start\r?\n.*?(?=^## Repository layout\r?$)')
    $quick = $section.Value
}
Describe 'ZIP-first README quick start (offline documentation checks)' {
    It 'contains one quick-start section and retains repository layout' {
        $section.Success | Should -BeTrue
        ([regex]::Matches($readme,'(?m)^## Quick start\r?$')).Count | Should -Be 1
        $readme | Should -Match '(?m)^## Repository layout'
    }
    It 'does not require Git or GitHub Desktop' {
        $quick | Should -Match 'do not need Git or GitHub Desktop'
        $quick | Should -Not -Match '(?m)^\s*git\s+(clone|pull|checkout|switch)\b'
    }
    It 'links to repository releases and distinguishes complete packages from patches' {
        $quick | Should -Match 'https://github\.com/nmeekercloud/M365-Admin-Toolkit/releases'
        $quick | Should -Match 'Under Assets'
        $quick | Should -Match 'not a complete installation'
        $quick | Should -Match 'Source code ZIP'
    }
    It 'explains unblocking and extracting the full archive' {
        $quick | Should -Match 'Unblock checkbox'
        $quick | Should -Match 'Extract All'
        $quick | Should -Match 'Do not run the toolkit from inside the compressed ZIP'
        $quick | Should -Match 'Config, Modules, Scripts, and Tools'
    }
    It 'explains how to launch from the extracted folder in PowerShell 7' {
        $quick | Should -Match 'Open PowerShell 7'
        $quick | Should -Match 'Set-Location -LiteralPath'
        $quick | Should -Match '\.\\Start-M365Toolkit\.ps1'
    }
    It 'avoids an obsolete fixed connection menu number' {
        $quick | Should -Match "toolkit's connection option"
        $quick | Should -Not -Match '\[7\]'
    }
    It 'includes beta tenant safety and the full guide link' {
        $quick | Should -Match 'dedicated test tenant'
        $quick | Should -Match 'Documentation/Getting-Started\.md'
    }
    It 'does not present disabling security policy as an installation step' {
        $quick | Should -Not -Match 'Set-ExecutionPolicy|ExecutionPolicy Bypass'
        $quick | Should -Match 'Do not disable'
    }
}
