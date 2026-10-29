#Requires -Version 7.4
[CmdletBinding()]
param([string] $ToolkitPath=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
$folder=Get-M365LogPath -Folder
$lines=@()
$logs=@(Get-ChildItem -LiteralPath $folder -Filter '*.log' -File | Sort-Object LastWriteTime | Select-Object -Last 10)
foreach ($file in $logs) {
    foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern '\[AuthDiag\] .*')) {
        $lines += $match.Matches[0].Value
    }
}
if ($lines.Count -eq 0) { Write-Host 'No diagnostic markers found. Run a connection test with this version first.'; return }
# Fixed diagnostic labels only, not complete log lines, paths or credentials.
$lines | Select-Object -Last 30
