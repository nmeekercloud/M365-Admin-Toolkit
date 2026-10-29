BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Reports/Get-UserAccessReport.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Assert-M365Connection { param($Service,$GraphScopes) }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType,$Headers) throw 'Unmocked Graph blocked' }
 function Get-Phase9Fixture {
  param([string]$Uri)
  if ($Uri -match '/subscribedSkus') { return [pscustomobject]@{value=@()} }
  if ($Uri -match '/transitiveMemberOf/') { return [pscustomobject]@{value=@([pscustomobject]@{id='direct';displayName='Direct'},[pscustomobject]@{id='indirect';displayName='Indirect'})} }
  if ($Uri -match '/memberOf/') { return [pscustomobject]@{value=@([pscustomobject]@{id='direct';displayName='Direct'})} }
  if ($Uri -match '/ownedObjects') { return [pscustomobject]@{value=@([pscustomobject]@{id='owner-only';displayName='Owned';'@odata.type'='#microsoft.graph.group'})} }
  if ($Uri -match '/roleManagement/') { return [pscustomobject]@{value=@([pscustomobject]@{id='role-assignment';roleDefinitionId='role';roleDefinition=[pscustomobject]@{displayName='Reader'};principalId='user-id';directoryScopeId='/'})} }
  if ($Uri -match '/users/') { return [pscustomobject]@{id='user-id';displayName='=User';userPrincipalName='user@contoso.com';mail='';accountEnabled=$true;userType='Member';assignedLicenses=@();licenseAssignmentStates=@()} }
  throw ('Unexpected URI: '+$Uri)
 }
}
Describe 'Phase 9 user directory baseline output' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365Connection {}
  Mock Invoke-MgGraphRequest { Get-Phase9Fixture -Uri $Uri }
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Write-Warning {}
  Mock Read-Host { 'n' }
 }
 It 'displays all five tables before one export choice and declining writes nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 5 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -UserPrincipalName 'user@contoso.com' -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  $r.Paths.Count | Should -Be 0
  Should -Invoke Read-Host -Times 1 -Exactly
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -PassThru
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 5 -ParameterFilter { $NoPaging }
 }
 It 'requires explicit users in noninteractive mode before authentication' {
  { & $entry -NoInteractive } | Should -Throw '*UserPrincipalName is required*'
  Should -Invoke Assert-M365Connection -Times 0
  Should -Invoke Read-Host -Times 0
 }
 It 'exports exactly five declared CSVs and Run.json with safe cells and raw passthrough' {
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'baseline' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('DirectoryRoles.csv','Groups.csv','Licenses.csv','Profiles.csv','Run.json','Segments.csv')
  (Import-Csv $r.Paths.Profiles).DisplayName | Should -Be "'=User"
  $r.Profiles[0].DisplayName | Should -Be '=User'
  $r.Paths.Coverage | Should -Be (Join-Path $r.ReportFolder 'Run.json')
  $r.Licenses[0].Source | Should -Be 'Unlicensed'
 }
 It 'keeps direct indirect and owner relationships distinct without claiming full effective access' {
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -PassThru
  @($r.Groups | Where-Object GroupId -eq 'direct')[0].Relationship | Should -Be 'DirectMember'
  @($r.Groups | Where-Object GroupId -eq 'indirect')[0].Relationship | Should -Be 'IndirectMember'
  @($r.Groups | Where-Object GroupId -eq 'owner-only')[0].Relationship | Should -Be 'Owner (not proof of membership)'
  $r.Metadata.IsFullEffectiveAccessAudit | Should -BeFalse
  $r.Metadata.Excluded | Should -Contain 'Group-derived directory role assignments'
 }
 It 'retains unknown directness and partial coverage when direct membership retrieval fails' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/memberOf/') { throw 'Synthetic direct membership denial' }
   Get-Phase9Fixture -Uri $Uri
  }
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'partial' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.CollectedSegmentsComplete | Should -BeFalse
  $r.Manifest.Status | Should -Be 'PartialCoverage'
  @($r.Groups | Where-Object GroupId -eq 'indirect')[0].Relationship | Should -Be 'TransitiveMember; directness unknown'
  (Get-Content $r.Paths.Coverage -Raw | ConvertFrom-Json).CollectedSegmentsComplete | Should -BeFalse
 }
 It 'records limited group metadata explicitly' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/memberOf/|/transitiveMemberOf/') { return [pscustomobject]@{value=@([pscustomobject]@{id='limited'})} }
   Get-Phase9Fixture -Uri $Uri
  }
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -PassThru
  @($r.Groups | Where-Object GroupId -eq 'limited')[0].MetadataLimited | Should -BeTrue
  $r.Metadata.CollectedSegmentsComplete | Should -BeFalse
  @($r.Segments | Where-Object Segment -eq 'Group metadata visibility').Count | Should -Be 1
 }
 It 'keeps collected rows and coverage when export fails' {
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Metadata.CollectedSegmentsComplete | Should -BeTrue
  $r.Profiles.Count | Should -Be 1
  $r.Paths.Count | Should -Be 0
 }
 It 'saves explicit headers and partial metadata when selected-user resolution fails' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/users/') { throw 'Synthetic user resolution denial' }
   Get-Phase9Fixture -Uri $Uri
  }
  $r=& $entry -UserPrincipalName 'missing@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'unresolved' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Profiles.Count | Should -Be 0
  (Get-Content $r.Paths.Profiles -First 1) | Should -Be '"UserId","DisplayName","UserPrincipalName","Mail","AccountEnabled","UserType"'
  $r.Manifest.Status | Should -Be 'PartialCoverage'
 }
 It 'refuses existing bundles without overwriting files' {
  $folder=Join-Path $TestDrive 'existing';$null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'uses read-only Graph operations and retains scoped directory role evidence' {
  $r=& $entry -UserPrincipalName 'user@contoso.com' -NoInteractive -PassThru
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -ne 'GET' }
  $r.DirectoryRoles[0].Source | Should -Be 'Direct principal roleAssignment; no group or PIM eligibility expansion'
  $r.DirectoryRoles[0].DirectoryScopeId | Should -Be '/'
 }
 It 'removes legacy save-before-display paths' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Initialize-R3SaveChoice|Export-R3Csv|Export-R3Coverage|Get-M365OutputPath|\$saveReport'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
