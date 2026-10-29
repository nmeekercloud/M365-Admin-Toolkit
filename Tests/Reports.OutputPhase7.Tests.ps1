BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Reports/Export-ContactList.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Assert-M365Connection { param($Service,$GraphScopes) }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType,$Headers) throw 'Unmocked Graph blocked' }
}
Describe 'Phase 7 All Users display-first export' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365Connection {}
  Mock Invoke-MgGraphRequest {
   [pscustomobject]@{value=@(
    [pscustomobject]@{id='member';displayName='=Member';mail='';userPrincipalName='member@contoso.com';accountEnabled=$false;userType='Member';businessPhones=@('111','222')},
    [pscustomobject]@{id='guest';displayName='Guest';mail='guest@example.com';userPrincipalName='guest_example.com#EXT#@contoso.com';accountEnabled=$true;userType='Guest'}
   )}
  }
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Write-Warning {}
  Mock Read-Host { 'n' }
 }
 It 'retrieves and displays before asking to save without creating directories when declined' {
  Mock Read-Host {
   Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
   Should -Invoke Show-M365Results -Times 1 -Exactly
   'n'
  }
  Mock New-Item { throw 'Unexpected directory write' }
  $r=& $entry -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  $r.Csv | Should -BeNullOrEmpty
  $r.Coverage | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory write' }
  $r=& $entry -NoInteractive -PassThru
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
 }
 It 'retains guests disabled users blank mail and joined phones' {
  $r=& $entry -NoInteractive -PassThru
  $r.Rows.Count | Should -Be 2
  $member=@($r.Rows | Where-Object UserId -eq 'member')[0]
  $member.Mail | Should -BeNullOrEmpty
  $member.AccountEnabled | Should -BeFalse
  $member.BusinessPhones | Should -Be '111; 222'
  @($r.Rows | Where-Object UserType -eq 'Guest').Count | Should -Be 1
 }
 It 'exports only AllUsers.csv and Run.json and preserves raw values' {
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'users' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('AllUsers.csv','Run.json')
  @((Import-Csv $r.Csv) | Where-Object UserId -eq 'member')[0].DisplayName | Should -Be "'=Member"
  @($r.Rows | Where-Object UserId -eq 'member')[0].DisplayName | Should -Be '=Member'
  $r.Coverage | Should -Be (Join-Path $r.ReportFolder 'Run.json')
  (Get-Content $r.Coverage -Raw | ConvertFrom-Json).Complete | Should -BeTrue
 }
 It 'retains all export and passthrough rows when the viewer returns early' {
  Mock Invoke-MgGraphRequest { [pscustomobject]@{value=@(1..75 | ForEach-Object { [pscustomobject]@{id=[string]$_;displayName=('User '+$_);userPrincipalName=('user'+$_+'@contoso.com');userType='Member';accountEnabled=$true} })} }
  Mock Show-M365Results {}
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'many' -PassThru
  $r.Rows.Count | Should -Be 75
  @(Import-Csv $r.Csv).Count | Should -Be 75
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { @($InputObject).Count -eq 75 }
 }
 It 'preserves partial retrieval status independently of saved export' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match 'skiptoken') { throw 'Synthetic next-page denial' }
   [pscustomobject]@{value=@([pscustomobject]@{id='partial';displayName='Partial';userPrincipalName='partial@contoso.com'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/users?$skiptoken=offline'}
  }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'partial' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.Complete | Should -BeFalse
  $r.Rows.Count | Should -Be 1
  $r.Manifest.Status | Should -Be 'PartialCoverage'
  (Get-Content $r.Coverage -Raw | ConvertFrom-Json).Complete | Should -BeFalse
 }
 It 'preserves headers for a completed empty query' {
  Mock Invoke-MgGraphRequest { [pscustomobject]@{value=@()} }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Rows.Count | Should -Be 0
  (Get-Content $r.Csv -First 1) | Should -Be '"DisplayName","GivenName","Surname","Mail","UserPrincipalName","JobTitle","Department","CompanyName","OfficeLocation","BusinessPhones","MobilePhone","AccountEnabled","UserType","UserId"'
 }
 It 'keeps retrieval success and rows when export fails' {
  $r=& $entry -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Metadata.Complete | Should -BeTrue
  $r.Rows.Count | Should -Be 2
  $r.Csv | Should -BeNullOrEmpty
 }
 It 'refuses to overwrite existing bundles' {
  $folder=Join-Path $TestDrive 'existing';$null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'removes the legacy save-before-retrieval and pager paths' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Initialize-R3SaveChoice|Export-R3Csv|Export-R3Coverage|\$pageSize|Get-M365OutputPath'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
