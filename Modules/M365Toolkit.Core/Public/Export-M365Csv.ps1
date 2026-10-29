function Export-M365Csv {
 <# .SYNOPSIS
 Offer CSV export after the caller displays results. No writes occur when export is declined.
 .DESCRIPTION
 Path explicitly requests export. NoInteractive without Path skips saving; noninteractive
 saving requires an existing directory and explicit Overwrite for an existing file.
 Save errors are reported as export errors, never as administrative-operation failures.
 #>
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InputObject,
       [string]$ReportName='Report',[string]$Path,[switch]$NoInteractive,[switch]$Overwrite,[switch]$PassThru)
 $status='NotRequested'; $savedPath=$null; $issue=$null
 try {
  if ($InputObject.Count -eq 0) { Write-Host 'No results to export.' }
  elseif ($NoInteractive -and -not $Path) { Write-Host 'No output path supplied; no report files saved.' }
  elseif ($Path -or (Read-Host "Export '$ReportName' results to CSV? [y/N]") -match '^(?i)y(es)?$') {
   $choice=Request-ToolkitSaveFile -Path $Path -Extension csv -NoInteractive:$NoInteractive -AllowExisting:$Overwrite
   if ($choice) {
    $destination=$choice.Path
    # NoClobber protects new destinations against a file appearing after validation.
    $safeRows=@($InputObject | ForEach-Object { ConvertTo-ToolkitSafeCsvRow $_ })
    $safeRows | Export-Csv -LiteralPath $destination -NoTypeInformation -Encoding utf8 -NoClobber:(!$choice.ExistingApproved) -ErrorAction Stop
    $savedPath=$destination; $status='Saved'
    Write-Host "CSV saved: $destination" -ForegroundColor Green
   } else { $status='Cancelled'; Write-Host 'Saving cancelled; displayed results are unchanged.' }
  } else { $status='Declined'; Write-Host 'No report files saved.' }
 } catch {
  $status='ExportFailed'; $issue=$_.Exception.Message
  Write-Warning "CSV export failed: $issue. The underlying task result is unchanged; do not rerun an administrative action just to save its report."
 }
 if ($PassThru) { [pscustomobject]@{Status=$status;Path=$savedPath;Error=$issue;RowCount=$InputObject.Count} }
}
