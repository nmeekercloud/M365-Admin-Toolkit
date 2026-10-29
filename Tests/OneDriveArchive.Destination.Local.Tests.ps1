#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.OneDriveArchive.Destination.ps1')
function Assert-ODDstTest([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
Assert-ODDstTest ((ConvertTo-ODArchiveSiteSlug 'Test User OneDrive') -eq 'test-user-onedrive') 'Title-to-address failed.'
Assert-ODDstTest ((ConvertTo-ODArchiveSiteSlug '  Test / Site & Archive  ') -eq 'test-site-archive') 'Punctuation normalization failed.'
Assert-ODDstTest ((ConvertTo-ODArchiveSiteSlug ('Caf'+[char]233+' Archive')) -eq 'cafe-archive') 'Accent normalization failed.'
Assert-ODDstTest ((ConvertTo-ODArchiveSiteSlug ('a'*80)).Length -eq 60) 'Length limit failed.'
$failed=$false;try {$null=ConvertTo-ODArchiveSiteSlug '***'} catch {$failed=$true};Assert-ODDstTest $failed 'Invalid title must fail.'
$lib=[pscustomobject]@{Id='11111111-1111-4111-8111-111111111111';Title='Localized library';BaseType='DocumentLibrary';Hidden=$false;RootFolder=[pscustomobject]@{ServerRelativeUrl='/sites/Test/Shared Documents'}}
Assert-ODArchiveDefaultLibraryMetadata -Library $lib -WebRoot '/sites/Test'
$failed=$false;try {Assert-ODArchiveDefaultLibraryMetadata -Library $lib -WebRoot '/sites/Other'} catch {$failed=$true};Assert-ODDstTest $failed 'Wrong-web root accepted.'
$lib.Hidden=$true;$failed=$false;try {Assert-ODArchiveDefaultLibraryMetadata -Library $lib -WebRoot '/sites/Test'} catch {$failed=$true};Assert-ODDstTest $failed 'Hidden default accepted.';$lib.Hidden=$false
# Override only the single-read seam: no actual PnP/network calls.
$script:ODDstReads=0;$script:ODDstMode='Transient'
function Get-ODArchiveDefaultLibraryOnce {
 param($Connection,$ExpectedSiteUrl)
 $script:ODDstReads++
 if ($script:ODDstMode -eq 'Permanent403') {throw '403 Forbidden'}
 if ($script:ODDstMode -eq 'NeverReady' -or ($script:ODDstMode -eq 'Transient' -and $script:ODDstReads -lt 3)) {throw 'Provisioning not ready'}
 $lib
}
try {
 $resolved=Resolve-ODArchiveNewDefaultLibrary -Connection ([pscustomobject]@{}) -ExpectedSiteUrl 'https://contoso.sharepoint.com/sites/Test' -MaxAttempts 4 -DelaySeconds 0
 Assert-ODDstTest ($resolved.Id -eq $lib.Id -and $script:ODDstReads -eq 3) 'Read readiness retry failed.'
 $script:ODDstMode='NeverReady';$script:ODDstReads=0;$failed=$false
 try {$null=Resolve-ODArchiveNewDefaultLibrary -Connection ([pscustomobject]@{}) -ExpectedSiteUrl 'https://contoso.sharepoint.com/sites/Test' -MaxAttempts 2 -DelaySeconds 0} catch {$failed=$true}
 Assert-ODDstTest ($failed -and $script:ODDstReads -eq 2) 'Retry must be bounded.'
 $script:ODDstMode='Permanent403';$script:ODDstReads=0;$failed=$false
 try {$null=Resolve-ODArchiveNewDefaultLibrary -Connection ([pscustomobject]@{}) -ExpectedSiteUrl 'https://contoso.sharepoint.com/sites/Test' -MaxAttempts 4 -DelaySeconds 0} catch {$failed=$true}
 Assert-ODDstTest ($failed -and $script:ODDstReads -eq 1) 'Access-denied must not be repeatedly retried.'
} finally {Remove-Item Function:Get-ODArchiveDefaultLibraryOnce -ErrorAction SilentlyContinue}
$archive=[IO.File]::ReadAllText((Join-Path $root 'Scripts/OneDrive/Backup-OneDrive.ps1'))
Assert-ODDstTest (-not $archive.Contains("Read-ODValue 'New site URL name")) 'Manual URL-name prompt still present.'
Assert-ODDstTest ($archive.Contains('Resolve-ODArchiveNewDefaultLibrary') -and -not $archive.Contains('Cannot uniquely identify the new default document library.')) 'Default-library count assumption still present.'
Assert-ODDstTest ($archive.IndexOf('Resolve-ODArchiveNewDefaultLibrary -Connection') -lt $archive.IndexOf('OD-Move-SingleSourceItem -Type')) 'Default destination must resolve before moves.'
Write-Host 'Destination/name helper tests passed. Synthetic/mocked reads only; no site creation or moves.' -ForegroundColor Green
