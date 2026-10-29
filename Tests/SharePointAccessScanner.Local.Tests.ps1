#Requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.SharePointAccessScanner.ps1')
function Assert-SARTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$ctx=@{IdentityCache=@{'guest@contoso.com'='DirectoryGuest';'member@contoso.com'='DirectoryMember'}}
Assert-SARTest ((Get-SARExposure $ctx ([pscustomobject]@{PrincipalType='User';LoginName='i:0#.f|membership|guest@contoso.com'})) -eq 'DirectoryGuest') 'Guest classification failed.'
Assert-SARTest ((Get-SARExposure $ctx ([pscustomobject]@{PrincipalType='User';LoginName='i:0#.f|membership|member@contoso.com'})) -eq 'DirectoryMember') 'Member classification failed.'
Assert-SARTest ((Get-SARExposure $ctx ([pscustomobject]@{PrincipalType='SecurityGroup';LoginName='group'})) -eq 'UnexpandedDirectoryGroup') 'Do not label an unexpanded group internal.'
Assert-SARTest ((Get-SARExposure $ctx ([pscustomobject]@{PrincipalType='User';LoginName='unknown'})) -eq 'UnresolvedPrincipal') 'Unknown principal must remain unresolved.'
Assert-SARTest ((Get-SARExposure $ctx ([pscustomobject]@{PrincipalType='User';IsEmailAuthenticationGuestUser=$true})) -eq 'SharePointGuestIndicator') 'SharePoint guest indicator missing.'
$row=ConvertTo-SARLinkRow -Permission ([pscustomobject]@{Id='synthetic';Link=[pscustomobject]@{Scope='anonymous';Type='view';WebUrl='DO-NOT-EXPORT'}}) -Site Test -Object Test -ObjectType File
Assert-SARTest ($row.LinkScope -eq 'anonymous' -and -not ($row | ConvertTo-Json).Contains('DO-NOT-EXPORT')) 'Link URL should not leak into reports.'
$row=ConvertTo-SARLinkRow -Permission ([pscustomobject]@{Id='synthetic'}) -Site Test -Object Test -ObjectType File
Assert-SARTest ($row.LinkScope -eq 'Unknown') 'Missing link metadata must remain unknown.'
Assert-SARTest ((ConvertTo-SARUrl 'https://contoso.sharepoint.com/sites/Test/' 'contoso.sharepoint.com') -eq 'https://contoso.sharepoint.com/sites/Test') 'URL normalization failed.'
$failed=$false; try { $null=ConvertTo-SARUrl 'https://other.sharepoint.com/sites/Test' 'contoso.sharepoint.com' } catch { $failed=$true }
Assert-SARTest $failed 'Cross-host URL accepted.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('SAR-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
 Initialize-SARCsv (Join-Path $temp 'Grants.csv') @('SiteUrl','Object','ObjectType','Origin','ViaSharePointGroup','PrincipalId','PrincipalType','PrincipalTitle','LoginName','RoleNames','Exposure','Interpretation')
 $c=@{Folder=$temp;Mode='ExternalCandidates';IdentityCache=$ctx.IdentityCache;OutputFailed=$false;Gaps=0;GrantRows=0;FilteredMemberRows=0;UnresolvedGrantRows=0}
 Write-SARGrant -Context $c -Site Test -Object Test -ObjectType RootWeb -Principal ([pscustomobject]@{PrincipalType='User';LoginName='i:0#.f|membership|member@contoso.com'}) -Origin Test -Roles Read
 Assert-SARTest ($c.GrantRows -eq 0 -and $c.FilteredMemberRows -eq 1) 'External candidate mode must track filtered directory Member rows.'
 Write-SARGrant -Context $c -Site Test -Object Test -ObjectType RootWeb -Principal ([pscustomobject]@{PrincipalType='SecurityGroup';LoginName='group'}) -Origin Test -Roles Read
 Assert-SARTest ($c.GrantRows -eq 1 -and $c.UnresolvedGrantRows -eq 1) 'Unexpanded group must be retained, not silently excluded.'
 $safe=ConvertTo-SARSafeCsv ([pscustomobject]@{Name='=BAD()';Count=0})
 Assert-SARTest ($safe.Name.StartsWith("'=") -and $safe.Count -eq 0) 'CSV text safety failed.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
$engine=[IO.File]::ReadAllText((Join-Path $root 'Tools/Toolkit.SharePointAccessScanner.ps1'))
Assert-SARTest ($engine.IndexOf('$PSCmdlet.ShouldProcess') -lt $engine.IndexOf('Get-M365OutputPath')) 'Dry-run guard must precede reports.'
Assert-SARTest (-not $engine.Contains('Set-PnP') -and -not $engine.Contains('Add-PnP') -and -not $engine.Contains('Remove-PnP')) 'Read-only scanner must not modify permissions.'
Write-Host 'SharePoint report scanner helper tests passed. Synthetic data only; no tenant calls.' -ForegroundColor Green
