# Offline CSV template guidance. No tenant/module operations.
function Get-ToolkitBulkCsvDefinition {
 param([Parameter(Mandatory)][string]$ToolkitRoot,[Parameter(Mandatory)][string]$Kind)
 $catalog=Import-PowerShellDataFile -LiteralPath (Join-Path $ToolkitRoot 'Config/BulkCsvTemplates.psd1') -ErrorAction Stop
 if (-not $catalog.ContainsKey($Kind)) { throw 'Unknown bulk CSV template type.' }
 return $catalog[$Kind]
}
function Resolve-ToolkitBulkCsvDestination {
 param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ToolkitRoot)
 if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Use an absolute CSV path including filename.csv.' }
 $full=[IO.Path]::GetFullPath($Path)
 if ([IO.Path]::GetExtension($full) -ine '.csv') { throw 'The destination must include a filename with .csv extension.' }
 $repo=[IO.Path]::GetFullPath($ToolkitRoot).TrimEnd([char[]]'\/')
 if ($full.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Save the working template copy outside the toolkit repository.' }
 $cursor=$full
 while ($cursor) {
  if (Test-Path -LiteralPath $cursor) {
   $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
   if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Template output through symbolic links or junctions is blocked.' }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if ($parent -eq $cursor) { break }
  $cursor=$parent
 }
 return $full
}
function Save-ToolkitBulkCsvTemplate {
 [CmdletBinding(SupportsShouldProcess)]
 param([Parameter(Mandatory)][string]$ToolkitRoot,[Parameter(Mandatory)][string]$Kind,[string]$Path)
 $definition=Get-ToolkitBulkCsvDefinition -ToolkitRoot $ToolkitRoot -Kind $Kind
 $source=Join-Path $ToolkitRoot $definition.Template
 $header=$definition.Columns -join ','
 $destination=$null
 try {
  # Refuse to propagate any accidentally populated repository template.
  if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or [IO.File]::ReadAllText($source).Trim() -cne $header) { throw 'Bundled template is missing or no longer header-only. Restore the shipped template before saving a copy.' }
  if (-not $Path) { $Path=([string](Read-Host 'Full destination path including filename.csv (Enter cancels template saving)')).Trim().Trim('"') }
  if (-not $Path -or $Path -imatch '^(q|quit|cancel)$') { return [pscustomobject]@{Status='Cancelled';Path=$null;Error=$null} }
  $destination=Resolve-ToolkitBulkCsvDestination -Path $Path -ToolkitRoot $ToolkitRoot
  $exists=Test-Path -LiteralPath $destination
  if ($exists -and -not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Template destination is not a file.' }
  if ($exists -and (Read-Host "Overwrite existing file '$destination' with a BLANK template? [y/N]") -notmatch '^(?i)y(es)?$') { return [pscustomobject]@{Status='Cancelled';Path=$null;Error=$null} }
  $parent=[IO.Path]::GetDirectoryName($destination)
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
   if ((Read-Host "Create destination directory '$parent'? [y/N]") -notmatch '^(?i)y(es)?$') { return [pscustomobject]@{Status='Cancelled';Path=$null;Error=$null} }
  }
  if (-not $PSCmdlet.ShouldProcess($destination,'Save header-only bulk CSV template copy')) { return [pscustomobject]@{Status='Planned';Path=$destination;Error=$null} }
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $null=New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop }
  $stream=$null; $writer=$null
  try {
   $mode=if ($exists) {[IO.FileMode]::Create} else {[IO.FileMode]::CreateNew}
   $stream=[IO.File]::Open($destination,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
   $writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false))
   $writer.WriteLine($header)
  } finally { if ($writer) { $writer.Dispose() } elseif ($stream) { $stream.Dispose() } }
  Write-Host "Blank template saved: $destination" -ForegroundColor Green
  Write-Host 'Populate that copy, then enter its path. No bulk changes have been submitted.'
  return [pscustomobject]@{Status='Saved';Path=$destination;Error=$null}
 } catch {
  Write-Warning ('Template copy was not saved successfully: '+$_.Exception.Message)
  return [pscustomobject]@{Status='SaveFailed';Path=$destination;Error=$_.Exception.Message}
 }
}
function Read-ToolkitBulkCsvPath {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$ToolkitRoot,[Parameter(Mandatory)][string]$Kind,[string]$CsvPath,[switch]$NoInteractive)
 $definition=Get-ToolkitBulkCsvDefinition -ToolkitRoot $ToolkitRoot -Kind $Kind
 Write-Host ($definition.Title+' CSV template: '+(Join-Path $ToolkitRoot $definition.Template)) -ForegroundColor Cyan
 Write-Host ('Required template columns: '+($definition.Columns -join ','))
 foreach ($line in $definition.Help) { Write-Host $line -ForegroundColor DarkGray }
 Write-Host 'Use a separate populated working copy outside this repository; never commit customer CSVs.' -ForegroundColor Yellow
 if ($CsvPath) { return $CsvPath.Trim().Trim('"') }
 if ($NoInteractive) { throw 'CsvPath is required with NoInteractive. No template or input files were created.' }
 while ($true) {
  $answer=([string](Read-Host 'CSV path, or T to save a blank template copy (Enter cancels)')).Trim().Trim('"')
  if (-not $answer -or $answer -imatch '^(q|quit|cancel)$') { return $null }
  if ($answer -ieq 'T') {
   $null=Save-ToolkitBulkCsvTemplate -ToolkitRoot $ToolkitRoot -Kind $Kind
   continue
  }
  return $answer
 }
}
