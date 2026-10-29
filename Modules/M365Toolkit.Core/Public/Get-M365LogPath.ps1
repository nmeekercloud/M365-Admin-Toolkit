function Get-M365LogPath {
 <# .SYNOPSIS
 Return the selected custom log or the default daily tenant log (Folder returns its directory).
 .DESCRIPTION
 Default: %LOCALAPPDATA%\M365AdminToolkit\Logs, using existing toolkit DataRoot overrides
 when configured. Entries before connection use no-tenant; after switching tenants the
 daily filename follows the current tenant. Existing custom log selections are honored.
 #>
 [CmdletBinding()]
 [OutputType([string])]
 param([switch]$Folder)
 $selected=Get-Variable -Name ToolkitFileLogPath -Scope Script -ValueOnly -ErrorAction SilentlyContinue
 if ($selected) {
  $path=Assert-ToolkitExternalPath -Path ([string]$selected)
  if ($Folder) { return [IO.Path]::GetDirectoryName($path) }
  return $path
 }
 $logDir=Assert-ToolkitExternalPath -Path (Join-Path (Get-ToolkitDataRoot) 'Logs')
 if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
  $null=New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop
 }
 if ($Folder) { return $logDir }
 $label=[string](Get-ToolkitSessionLabel)
 $safe=$label -replace '[^a-zA-Z0-9._-]','_'
 if (-not $safe) { $safe='no-tenant' }
 $fileName='{0}_{1}.log' -f (Get-Date -Format 'yyyy-MM-dd'),$safe
 return Assert-ToolkitExternalPath -Path (Join-Path $logDir $fileName)
}
