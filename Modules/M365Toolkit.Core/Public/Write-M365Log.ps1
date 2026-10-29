function Write-M365Log {
 <# .SYNOPSIS
 Display a redacted progress message and persist it to the current daily tenant log by default.
 .DESCRIPTION
 Quiet suppresses console output. An explicit Disable still prevents file writes for every level.
 #>
 [CmdletBinding()]
 param([Parameter(Mandatory,Position=0)][AllowEmptyString()][string]$Message,
       [Parameter(Position=1)][ValidateSet('Debug','Info','Success','Change','Warning','Error')][string]$Level='Info',
       [object]$Data,[switch]$Quiet)
 $safeMessage=Protect-ToolkitLogText -Text $Message
 if ($PSBoundParameters.ContainsKey('Data') -and $null -ne $Data) {
  try { $safeMessage+=' | '+(Protect-ToolkitLogText -Text ($Data | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue)) }
  catch { $safeMessage+=' | [data could not be serialized]' }
 }
 $order=@{Debug=0;Info=1;Success=1;Change=1;Warning=2;Error=3}
 $minimum=Get-ToolkitSetting -Path 'Logging.MinimumLevel' -Default 'Info'
 if (-not $order.ContainsKey($minimum)) { $minimum='Info' }
 if (($script:ToolkitDefaultFileLogging -or $script:ToolkitFileLogPath) -and ($order[$Level] -ge $order[$minimum] -or $Level -in @('Change','Error'))) {
  try {
   $selectedPath=if ($script:ToolkitDefaultFileLogging) { Get-M365LogPath } else { $script:ToolkitFileLogPath }
   $path=Assert-ToolkitExternalPath -Path $selectedPath
   $parent=[IO.Path]::GetDirectoryName($path)
   if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Selected log directory no longer exists.' }
   $account=if ($script:M365Session) { $script:M365Session.Account } else { '-' }
   $stack=@(Get-PSCallStack); $source=if ($stack.Count -gt 1) { $stack[1].Command } else { 'Toolkit' }
   $line='{0} | {1,-7} | {2} | {3} | {4} | {5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level.ToUpperInvariant(),(Get-ToolkitSessionLabel),$account,$source,$safeMessage
   Add-Content -LiteralPath $path -Value $line -Encoding utf8 -ErrorAction Stop
  } catch {
   $script:ToolkitFileLogPath=$null
   $script:ToolkitDefaultFileLogging=$false
   Write-Warning ('Persistent logging disabled after a save failure: '+$_.Exception.Message)
  }
 }
 if (-not $Quiet -and $Level -ne 'Debug') {
  $color=switch ($Level) { Success {'Green'} Change {'Cyan'} Warning {'Yellow'} Error {'Red'} default {'Gray'} }
  $prefix=switch ($Level) { Success {'[OK]   '} Change {'[CHG]  '} Warning {'[WARN] '} Error {'[ERR]  '} default {'[INFO] '} }
  Write-Host "$prefix$safeMessage" -ForegroundColor $color
 } elseif ($Level -eq 'Debug') { Write-Verbose $safeMessage }
}
