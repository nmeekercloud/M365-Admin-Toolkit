# Shared optional report-bundle exporter. Definitions only; no implicit staging.
function Resolve-ToolkitReportBundlePath {
 param([Parameter(Mandatory)][string]$Path)
 if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Use an absolute output directory.' }
 $full=[IO.Path]::GetFullPath($Path)
 $repo=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd([char[]]'\/')
 if ($full.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Customer report output inside the toolkit repository is blocked.'
 }
 $cursor=$full
 while ($cursor) {
  if (Test-Path -LiteralPath $cursor) {
   $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
   if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Output through symbolic links/junctions is blocked.' }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if ($parent -eq $cursor) { break }
  $cursor=$parent
 }
 return $full
}
function Export-ToolkitReportBundle {
 [CmdletBinding()]
 param([Parameter(Mandatory)][hashtable]$Tables,
       [Parameter(Mandatory)][Collections.IDictionary]$Manifest,
       [Parameter(Mandatory)][hashtable]$Columns,
       [string]$OutputDirectory,[string]$BundleName,[switch]$NoInteractive,[hashtable]$JsonFiles=@{})
 $folder=$null
 try {
  $explicit=[bool]$OutputDirectory -and [bool]$BundleName
  if ($NoInteractive -and -not $explicit) {
   if ($OutputDirectory -or $BundleName) { throw 'Noninteractive export requires both ExportDirectory and ReportName.' }
   return [pscustomobject]@{Status='NotRequested';ReportFolder=$null;Error=$null}
  }
  # Allow only declared, safe leaf filenames; Run.json is reserved for the manifest.
  $tableNames=@($Tables.Keys | Sort-Object)
  if (-not $tableNames.Count) { throw 'A report bundle needs at least one declared CSV table.' }
  foreach ($name in $tableNames) {
   if ($name -ne [IO.Path]::GetFileName($name) -or $name -match '[\\/]' -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or [IO.Path]::GetExtension($name) -ine '.csv') { throw 'CSV table names must be safe leaf filenames with .csv extensions.' }
   if (-not $Columns.ContainsKey($name) -or @($Columns[$name]).Count -eq 0) { throw 'Every CSV table requires explicit columns.' }
  }
  foreach ($name in @($JsonFiles.Keys)) {
   if ($name -ieq 'Run.json' -or $name -ne [IO.Path]::GetFileName($name) -or $name -match '[\\/]' -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or [IO.Path]::GetExtension($name) -ine '.json') { throw 'Companion JSON filenames must be safe leaf names, excluding reserved Run.json.' }
  }
  $declaredNames=@($tableNames)+@($JsonFiles.Keys | Sort-Object)+@('Run.json')
  Write-Host ('Optional bundle files: '+($declaredNames -join ', ')+'. These filenames are fixed inside your named bundle folder.')
  if (-not $explicit -and (Read-Host 'Export this report bundle? [y/N]') -notmatch '^(?i)y(es)?$') {
   Write-Host 'No report files or folders saved.'
   return [pscustomobject]@{Status='Declined';ReportFolder=$null;Error=$null}
  }
  if (-not $OutputDirectory) { $OutputDirectory=([string](Read-Host 'Destination DIRECTORY for the report bundle (Enter cancels saving)')).Trim().Trim('"') }
  if (-not $OutputDirectory -or $OutputDirectory -imatch '^(q|quit|cancel)$') { return [pscustomobject]@{Status='Cancelled';ReportFolder=$null;Error=$null} }
  if (-not $BundleName) { $BundleName=([string](Read-Host 'Report bundle NAME (folder name only; Enter cancels saving)')).Trim() }
  if (-not $BundleName -or $BundleName -imatch '^(q|quit|cancel)$') { return [pscustomobject]@{Status='Cancelled';ReportFolder=$null;Error=$null} }
  if ($BundleName -in @('.','..') -or $BundleName -ne [IO.Path]::GetFileName($BundleName) -or $BundleName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $BundleName -match '[\\/]|[. ]$') {
   throw 'Use a single valid folder name without separators, trailing spaces or periods.'
  }
  $base=Resolve-ToolkitReportBundlePath $OutputDirectory
  $folder=Resolve-ToolkitReportBundlePath (Join-Path $base $BundleName)
  if (Test-Path -LiteralPath $folder) { throw 'A file or folder with that bundle name already exists. Choose a new name; nothing will be overwritten.' }
  # Serialize BEFORE creating directories. No hidden temporary files are used.
  $contents=[ordered]@{}
  foreach ($name in $tableNames) {
   $raw=$Tables[$name]
   $rows=@(if ($raw -is [Collections.Generic.List[object]]) { $raw.ToArray() } else { @($raw) })
   $safe=@($rows | ForEach-Object {
    $v=[ordered]@{}
    foreach ($column in $Columns[$name]) {
     $value=if ($_ -is [Collections.IDictionary]) { $_[$column] } else { $p=$_.PSObject.Properties[$column]; if ($p) { $p.Value } else { '' } }
     if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
     $v[$column]=$value
    }
    [pscustomobject]$v
   })
   if ($safe.Count) { $contents[$name]=($safe | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine }
   else {
    $empty=[ordered]@{}; foreach ($column in $Columns[$name]) { $empty[$column]='' }
    $contents[$name]=@([pscustomobject]$empty | ConvertTo-Csv -NoTypeInformation)[0]
   }
  }
  foreach ($name in @($JsonFiles.Keys | Sort-Object)) {
   $contents[$name]=$JsonFiles[$name] | ConvertTo-Json -Depth 12 -ErrorAction Stop
  }
  $exportManifest=[ordered]@{}
  foreach ($key in $Manifest.Keys) { $exportManifest[$key]=$Manifest[$key] }
  $exportManifest['ExportStatus']='Saved'
  $contents['Run.json']=$exportManifest | ConvertTo-Json -Depth 12 -ErrorAction Stop
  if (-not (Test-Path -LiteralPath $base -PathType Container)) {
   if (Test-Path -LiteralPath $base) { throw 'Destination directory is an existing file.' }
   if ($NoInteractive) { throw 'Noninteractive destination directory must already exist.' }
   if ((Read-Host "Create destination directory '$base'? [y/N]") -notmatch '^(?i)y(es)?$') { return [pscustomobject]@{Status='Cancelled';ReportFolder=$null;Error=$null} }
   $null=New-Item -ItemType Directory -Path $base -Force -ErrorAction Stop
  }
  # Do not merge into existing bundles. Creation failure/races leave existing data alone.
  $null=New-Item -ItemType Directory -Path $folder -ErrorAction Stop
  foreach ($name in $contents.Keys) {
   $stream=$null; $writer=$null
   try {
    $stream=[IO.File]::Open((Join-Path $folder $name),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false))
    $writer.WriteLine($contents[$name])
   } finally {
    if ($writer) { $writer.Dispose() } elseif ($stream) { $stream.Dispose() }
   }
  }
  Write-Host "Report bundle saved: $folder" -ForegroundColor Green
  return [pscustomobject]@{Status='Saved';ReportFolder=$folder;Error=$null}
 } catch {
  Write-Warning ('Report export failed; scan results are unchanged: '+$_.Exception.Message+' Any partially written bundle must not be treated as a completed export.')
  return [pscustomobject]@{Status='ExportFailed';ReportFolder=$folder;Error=$_.Exception.Message}
 }
}
