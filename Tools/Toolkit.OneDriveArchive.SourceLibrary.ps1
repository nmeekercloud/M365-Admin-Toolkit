# Definitions only; read-only source-library discovery, no moves or permission writes.
function Get-ODSLValue {
 param([object]$Object,[string]$Name)
 try {if ($null -eq $Object) {return $null};if ($Object -is [System.Collections.IDictionary]) {return $Object[$Name]};$p=$Object.PSObject.Properties[$Name];if ($p) {return $p.Value}} catch {return $null}
}
function Get-ODSourceLibraryCandidates {
 [CmdletBinding()]
 param([AllowEmptyCollection()][object[]]$Lists=@(),[Parameter(Mandatory)][string]$WebRoot)
 $prefix=$WebRoot.TrimEnd('/')+'/'
 foreach ($list in $Lists) {
  $base=[string](Get-ODSLValue $list 'BaseType');$hidden=Get-ODSLValue $list 'Hidden'
  if ($base -notin @('DocumentLibrary','1') -or $hidden -isnot [bool] -or $hidden) {continue}
  $folder=Get-ODSLValue $list 'RootFolder';$path=[string](Get-ODSLValue $folder 'ServerRelativeUrl');$id=[guid]::Empty
  if (-not [guid]::TryParse([string](Get-ODSLValue $list 'Id'),[ref]$id) -or $id -eq [guid]::Empty -or -not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith('//')) {continue}
  [pscustomobject]@{Id=$id.ToString('D');Title=[string](Get-ODSLValue $list 'Title');Template=[string](Get-ODSLValue $list 'BaseTemplate');Root=$path.TrimEnd('/');Library=$list}
 }
}
function Select-ODSourceLibraryCandidate {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object[]]$Candidates,[string]$LibraryId)
 if (-not $Candidates.Count) {throw 'No visible document-library candidates were returned. Review library metadata/access; no move submitted.'}
 if ($LibraryId) {
  $id=[guid]::Empty;if (-not [guid]::TryParse($LibraryId,[ref]$id)) {throw 'Selected source library ID must be a GUID.'}
  $match=@($Candidates | Where-Object {$_.Id -ieq $id.ToString('D')})
  if ($match.Count -ne 1) {throw 'Requested source library is not a unique accessible document-library candidate.'}
  return $match[0]
 }
 $personal=@($Candidates | Where-Object Template -eq '700')
 if ($personal.Count -eq 1) {return $personal[0]}
 # Do not fall through to another automatic heuristic if multiple personal libraries exist.
 if ($personal.Count -gt 1) {return}
 $documents=@($Candidates | Where-Object {$_.Root -match '/Documents$'})
 if ($documents.Count -eq 1) {return $documents[0]}
 if ($Candidates.Count -eq 1) {return $Candidates[0]}
 # Ambiguous: caller must obtain explicit user selection before any move plan.
}
function Resolve-ODArchiveSourceLibrary {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object]$Connection,[Parameter(Mandatory)][string]$OneDriveUrl,[string]$LibraryId)
 $web=Get-PnPWeb -Includes Url,ServerRelativeUrl -Connection $Connection -ErrorAction Stop
 if (([string]$web.Url).TrimEnd('/') -ine $OneDriveUrl.TrimEnd('/')) {throw 'Source web URL differs from selected OneDrive; no library selected.'}
 $lists=@(Get-PnPList -Includes Id,Title,BaseType,BaseTemplate,Hidden,RootFolder -Connection $Connection -ErrorAction Stop)
 foreach ($list in $lists) {
  if ($list.RootFolder) {$null=Get-PnPProperty -ClientObject $list.RootFolder -Property ServerRelativeUrl -Connection $Connection -ErrorAction Stop}
 }
 $candidates=@(Get-ODSourceLibraryCandidates -Lists $lists -WebRoot ([string]$web.ServerRelativeUrl) | Sort-Object Title,Id)
 if (-not $candidates.Count) {
  $lists | ForEach-Object {[pscustomobject]@{Title=[string]$_.Title;Id=[string]$_.Id;BaseType=[string]$_.BaseType;Template=[string]$_.BaseTemplate;Hidden=$_.Hidden;Root=[string]$_.RootFolder.ServerRelativeUrl}} | Format-Table -AutoSize -Wrap | Out-Host
  throw 'No accessible visible document-library candidates. Above is returned metadata; no source was guessed or move submitted.'
 }
 $chosen=Select-ODSourceLibraryCandidate -Candidates $candidates -LibraryId $LibraryId
 if (-not $chosen) {
  Write-Host 'Choose the SOURCE library inside this OneDrive. No move has been submitted.' -ForegroundColor Cyan
  for ($i=0;$i -lt $candidates.Count;$i++) {Write-Host ('[{0}] {1} | template {2} | {3} | ID {4}' -f ($i+1),$candidates[$i].Title,$candidates[$i].Template,$candidates[$i].Root,$candidates[$i].Id)}
  while ($true) {
   $answer=([string](Read-Host 'Source library number (Enter cancels)')).Trim()
   if (-not $answer) {throw [OperationCanceledException]::new('Source library selection cancelled.')}
   $n=0
   if ([int]::TryParse($answer,[ref]$n) -and $n -ge 1 -and $n -le $candidates.Count) {$chosen=$candidates[$n-1];break}
   Write-Host 'Choose a displayed number, or Enter to cancel.' -ForegroundColor Yellow
  }
 }
 Write-Host ('Selected source library: '+$chosen.Title+' | '+$chosen.Root+' | ID '+$chosen.Id) -ForegroundColor Cyan
 # Return the real list object expected by the existing archive plan/engine.
 $chosen.Library
}
