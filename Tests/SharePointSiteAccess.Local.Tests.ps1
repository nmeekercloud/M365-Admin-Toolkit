[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Tools/Toolkit.SharePointSiteAccess.Helpers.ps1')
function Assert-SATest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
Assert-SATest ((ConvertTo-SAUrl -Value 'https://contoso.sharepoint.com/sites/Test/' -AllowedHost 'contoso.sharepoint.com') -eq 'https://contoso.sharepoint.com/sites/Test') 'URL normalization failed.'
foreach ($bad in @('http://contoso.sharepoint.com/sites/Test','https://other.sharepoint.com/sites/Test','https://contoso.sharepoint.com/sites/Test?x=1','https://user@contoso.sharepoint.com/sites/Test','https://contoso.sharepoint.com:444/sites/Test')) {
 $failed=$false; try { $null=ConvertTo-SAUrl -Value $bad -AllowedHost 'contoso.sharepoint.com' } catch { $failed=$true }
 Assert-SATest $failed 'Unsafe URL should fail.'
}
$p=[pscustomobject]@{Id=1;PrincipalType='SecurityGroup';Title='Test group';LoginName='synthetic-claim'}
$row=ConvertTo-SAPrincipalRow -SiteUrl 'https://contoso.sharepoint.com/sites/Test' -SiteTitle Test -Principal $p -Origin RootWebAssignment -Roles Read
Assert-SATest ($row.PrincipalType -eq 'SecurityGroup' -and $row.Expansion -like '*Entra groups not expanded*') 'Unexpanded group scope missing.'
$safe=ConvertTo-SASafeCsv ([pscustomobject]@{Title='=BAD()';Count=1})
Assert-SATest ($safe.Title.StartsWith("'=") -and $safe.Count -eq 1) 'CSV safety failed.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('SATest-'+[guid]::NewGuid().ToString('N')+'.csv')
try {
 Initialize-SACsv -Path $temp -Columns @('Id','Title')
 Assert-SATest ([IO.File]::ReadAllText($temp).Trim() -eq '"Id","Title"') 'Header-only CSV invalid.'
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
$claims=@{tid='11111111-1111-4111-8111-111111111111';upn='test.user@contoso.com';exp=([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+600)}
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress))).TrimEnd('=').Replace('+','-').Replace('/','_')
$jwt='header.'+$encoded+'.synthetic-signature'
Assert-SATokenClaims -Token $jwt -TenantId $claims.tid -Account $claims.upn
$failed=$false; try { Assert-SATokenClaims -Token $jwt -TenantId '22222222-2222-4222-8222-222222222222' -Account $claims.upn } catch { $failed=$true }
Assert-SATest $failed 'Tenant mismatch must be blocked.'
$failed=$false; try { Assert-SATokenClaims -Token $jwt -TenantId $claims.tid -Account 'other@contoso.com' } catch { $failed=$true }
Assert-SATest $failed 'Account mismatch must be blocked.'
Write-Host 'SharePoint site access helper tests passed. Synthetic data only; no tenant calls.' -ForegroundColor Green
