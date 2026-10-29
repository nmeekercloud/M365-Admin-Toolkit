# Session-only state. Core import does not create files or folders.
$script:ToolkitFileLogPath=$null
# Automatic activity logs are the approved exception to optional report exports.
$script:ToolkitDefaultFileLogging=$true
function Request-ToolkitSaveFile {
 [CmdletBinding()]
 param([string]$Path,[Parameter(Mandatory)][string]$Extension,
       [switch]$NoInteractive,[switch]$AllowExisting,[ValidateSet('Overwrite','Append')][string]$ExistingAction='Overwrite')
 if ([string]::IsNullOrWhiteSpace($Path)) {
  if ($NoInteractive) { return $null }
  $Path=([string](Read-Host ("Full file path including filename.$Extension (Enter cancels saving)"))).Trim().Trim('"')
  if (-not $Path -or $Path -imatch '^(q|quit|cancel)$') { return $null }
 }
 $Path=Assert-ToolkitExternalPath -Path $Path
 if ([IO.Path]::GetExtension($Path) -ine ('.'+$Extension)) { throw "Include a filename with the .$Extension extension." }
 if (Test-Path -LiteralPath $Path -PathType Container) { throw 'Destination is a directory; include the filename.' }
 $parent=[IO.Path]::GetDirectoryName($Path)
 $exists=Test-Path -LiteralPath $Path
 if ($exists -and -not $AllowExisting) {
  if ($NoInteractive) { throw 'Destination exists; explicit overwrite/append approval is required.' }
  if ((Read-Host "$ExistingAction existing file '$Path'? [y/N]") -notmatch '^(?i)y(es)?$') { return $null }
 }
 # Folder creation happens only after a complete destination has been approved.
 if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
  if ($NoInteractive) { throw 'Destination directory must already exist for noninteractive saving.' }
  if ((Read-Host "Create destination directory '$parent'? [y/N]") -notmatch '^(?i)y(es)?$') { return $null }
  $null=New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
 }
 return [pscustomobject]@{Path=$Path;ExistingApproved=[bool]($exists -or $AllowExisting)}
}
function ConvertTo-ToolkitSafeCsvRow {
 param([Parameter(Mandatory)]$Row)
 $values=[ordered]@{}
 if ($Row -is [Collections.IDictionary]) {
  foreach ($key in $Row.Keys) {
   $v=$Row[$key]
   if ($v -is [string] -and $v -match '^\s*[=+@-]') { $v="'"+$v }
   $values[[string]$key]=$v
  }
 } else {
  foreach ($p in $Row.PSObject.Properties) {
   $v=$p.Value
   if ($v -is [string] -and $v -match '^\s*[=+@-]') { $v="'"+$v }
   $values[$p.Name]=$v
  }
 }
 [pscustomobject]$values
}
