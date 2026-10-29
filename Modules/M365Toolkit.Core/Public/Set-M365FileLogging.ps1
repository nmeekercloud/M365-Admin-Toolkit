function Set-M365FileLogging {
 <# .SYNOPSIS
 Enable automatic daily tenant-scoped logs at the toolkit data location, select a custom file, or disable logging.
 .DESCRIPTION
 With no Path, logging is enabled at the standard data-folder location without prompts.
 Explicit custom paths retain existing append/destination safeguards. No file is created
 by enabling default mode alone; the first log entry creates the daily log as needed.
 #>
 [CmdletBinding(DefaultParameterSetName='Enable')]
 param([Parameter(ParameterSetName='Enable')][string]$Path,
       [Parameter(ParameterSetName='Enable')][switch]$NoInteractive,
       [Parameter(ParameterSetName='Enable')][switch]$Append,
       [Parameter(Mandatory,ParameterSetName='Disable')][switch]$Disable)
 $script:ToolkitFileLogPath=$null
 $script:ToolkitDefaultFileLogging=$false
 if ($Disable) { return }
 if ([string]::IsNullOrWhiteSpace($Path)) {
  $script:ToolkitDefaultFileLogging=$true
  return
 }
 try {
  $selected=Request-ToolkitSaveFile -Path $Path -Extension log -NoInteractive:$NoInteractive -AllowExisting:$Append -ExistingAction Append
  if ($selected) {
   $script:ToolkitFileLogPath=$selected.Path
   Write-Host "Session log selected: $($selected.Path) (includes activity across tenants used in this session)." -ForegroundColor Cyan
  }
 } catch { Write-Warning ('Persistent logging remains disabled: '+$_.Exception.Message) }
}
