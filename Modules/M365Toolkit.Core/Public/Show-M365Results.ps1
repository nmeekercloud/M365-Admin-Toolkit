function Show-M365Results {
 <# .SYNOPSIS
 Display structured results in pages without writing files or changing the input collection.
 #>
 [CmdletBinding()]
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InputObject,
       [string]$Title='Results',[ValidateRange(1,1000)][int]$PageSize=50,[switch]$NoPaging)
 Write-Host "$Title ($($InputObject.Count) results)" -ForegroundColor Cyan
 if ($InputObject.Count -eq 0) { Write-Host 'No results returned.'; return }
 if ($NoPaging) { $InputObject | Format-Table -Wrap -AutoSize | Out-Host; return }
 for ($offset=0; $offset -lt $InputObject.Count; $offset+=$PageSize) {
  $count=[Math]::Min($PageSize,$InputObject.Count-$offset)
  $InputObject[$offset..($offset+$count-1)] | Format-Table -Wrap -AutoSize | Out-Host
  if ($offset+$count -lt $InputObject.Count) {
   $answer=Read-Host ('Showing {0}-{1} of {2}. Enter = next page; Q = stop display (all results remain available for export)' -f ($offset+1),($offset+$count),$InputObject.Count)
   if ($answer -imatch '^(q|quit|cancel)$') { break }
  }
 }
}
