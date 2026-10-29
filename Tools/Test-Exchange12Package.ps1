#Requires -Version 7.4
[CmdletBinding()]
param([switch]$RunUnitTests)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
foreach ($file in @('Tools/Toolkit.Exchange12.ps1','Tools/Test-Exchange12Offline.ps1','Scripts/Exchange/Copy-MailboxPermissions.ps1','Scripts/Exchange/Invoke-SharedMailboxManagement.ps1','Tests/Exchange12.Tests.ps1')) {
    $tokens=$null; $parseErrors=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count) { throw ($file+': '+($parseErrors.Message -join '; ')) }
}
$exe=(Get-Process -Id $PID).Path
& $exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Test-Exchange12Offline.ps1') -ToolkitPath $root
if ($LASTEXITCODE -ne 0) { throw 'Isolated helper checks failed.' }
if ($RunUnitTests) {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $result=Invoke-Pester -Path (Join-Path $root 'Tests/Exchange12.Tests.ps1') -PassThru -Output Detailed
    if ($result.Result -ne 'Passed') { throw 'Pester checks did not pass.' }
}
