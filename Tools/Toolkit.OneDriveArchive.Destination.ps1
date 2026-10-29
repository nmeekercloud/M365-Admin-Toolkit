# Definitions only. Title-to-URL conversion and read-only default-library lookup.
function ConvertTo-ODArchiveSiteSlug {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Title)
 if ([string]::IsNullOrWhiteSpace($Title)) {throw 'Site title is required.'}
 $decomposed=$Title.Normalize([Text.NormalizationForm]::FormD)
 $builder=[Text.StringBuilder]::new()
 foreach ($c in $decomposed.ToCharArray()) {
  if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {$null=$builder.Append($c)}
 }
 $slug=($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-')
 if ($slug.Length -gt 60) {$slug=$slug.Substring(0,60).TrimEnd('-')}
 if (-not $slug) {throw 'Cannot generate a site address from this title. Use a title containing Latin letters or numbers.'}
 $slug
}
function Assert-ODArchiveDefaultLibraryMetadata {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object]$Library,[Parameter(Mandatory)][string]$WebRoot)
 $id=[guid]::Empty
 if (-not [guid]::TryParse([string]$Library.Id,[ref]$id) -or $id -eq [guid]::Empty) {throw [ArgumentException]::new('Default library has no valid immutable ID.')}
 if ([string]$Library.BaseType -notin @('DocumentLibrary','1') -or $Library.Hidden -isnot [bool] -or $Library.Hidden) {throw [ArgumentException]::new('Reported default is not a visible document library.')}
 $path=[string]$Library.RootFolder.ServerRelativeUrl
 if (-not $path.StartsWith($WebRoot.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith('//')) {throw [ArgumentException]::new('Default-library root is outside the selected destination web.')}
}
function Get-ODArchiveDefaultLibraryOnce {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object]$Connection,[Parameter(Mandatory)][string]$ExpectedSiteUrl)
 $context=Get-PnPContext -Connection $Connection -ErrorAction Stop
 $web=$context.Web
 $context.Load($web);$context.ExecuteQuery()
 if (([string]$web.Url).TrimEnd('/') -ine $ExpectedSiteUrl.TrimEnd('/')) {throw [ArgumentException]::new('Default-library lookup connected to the wrong destination web.')}
 if (-not $web.PSObject.Methods['DefaultDocumentLibrary']) {throw [ArgumentException]::new('Installed CSOM does not expose Web.DefaultDocumentLibrary. No arbitrary library selected.')}
 # Ask SharePoint for its actual default rather than counting all libraries.
 $library=$web.DefaultDocumentLibrary()
 $context.Load($library);$context.ExecuteQuery()
 $null=Get-PnPProperty -ClientObject $library -Property Id,Title,RootFolder,BaseType,Hidden -Connection $Connection -ErrorAction Stop
 $null=Get-PnPProperty -ClientObject $library.RootFolder -Property ServerRelativeUrl -Connection $Connection -ErrorAction Stop
 Assert-ODArchiveDefaultLibraryMetadata -Library $library -WebRoot ([string]$web.ServerRelativeUrl)
 $library
}
function Resolve-ODArchiveNewDefaultLibrary {
 [CmdletBinding()]
 param([Parameter(Mandatory)][object]$Connection,[Parameter(Mandatory)][string]$ExpectedSiteUrl,
 [ValidateRange(1,120)][int]$MaxAttempts=30,[ValidateRange(0,30)][int]$DelaySeconds=2)
 $lastError=''
 for ($attempt=1;$attempt -le $MaxAttempts;$attempt++) {
  try {
   $library=Get-ODArchiveDefaultLibraryOnce -Connection $Connection -ExpectedSiteUrl $ExpectedSiteUrl
   Write-Host ('Destination default library: '+$library.Title+' | '+$library.RootFolder.ServerRelativeUrl+' | ID '+$library.Id) -ForegroundColor Cyan
   return $library
  } catch {
   $lastError=$_.Exception.Message
   if ($_.Exception -is [ArgumentException] -or $lastError -match '(?i)\b(401|403)\b|access denied|unauthorized|forbidden') {throw}
   if ($attempt -lt $MaxAttempts) {
    Write-Host ('Waiting for destination default document library ('+$attempt+'/'+$MaxAttempts+')...') -ForegroundColor DarkGray
    if ($DelaySeconds -gt 0) {Start-Sleep -Seconds $DelaySeconds}
   }
  }
 }
 throw ('Destination site is accessible, but its default library was not verified after '+$MaxAttempts+' read attempts. No file move submitted at this stage. The new site may remain: '+$ExpectedSiteUrl+'. Replan using Existing SharePoint site after inspecting it. Last error: '+$lastError)
}
