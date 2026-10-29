BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Reports/Get-LicenseReport.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Assert-M365Connection { param($Service,$GraphScopes) }
 function Invoke-MgGraphRequest { [CmdletBinding()]param($Method,$Uri,$OutputType,$Headers) throw 'Unmocked Graph blocked' }
 function New-Phase8Sku { [pscustomobject]@{skuId='sku-1';skuPartNumber='=TEST';appliesTo='User';capabilityStatus='Enabled';prepaidUnits=[pscustomobject]@{enabled=10;warning=0;suspended=0;lockedOut=0};consumedUnits=3} }
 function New-Phase8User {
  [pscustomobject]@{id='user-1';displayName='User';userPrincipalName='user@contoso.com';accountEnabled=$true;userType='Member';assignedLicenses=@([pscustomobject]@{skuId='sku-1';disabledPlans=@()});licenseAssignmentStates=@([pscustomobject]@{skuId='sku-1';assignedByGroup=$null;state='Active';disabledPlans=@()})}
 }
}
Describe 'Phase 8 license report display-first export' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365Connection {}
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/subscribedSkus') { return [pscustomobject]@{value=@(New-Phase8Sku)} }
   if ($Uri -match '/users/') { return (New-Phase8User) }
   if ($Uri -match '/users\?') { return [pscustomobject]@{value=@(New-Phase8User)} }
   throw ('Unexpected Graph URI: '+$Uri)
  }
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Write-Warning {}
  Mock Read-Host { 'n' }
 }
 It 'displays inventory and assignments before asking to export' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 2 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  $r.Paths.Count | Should -Be 0
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -NoInteractive -PassThru
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 2 -ParameterFilter { $NoPaging }
 }
 It 'exports the three declared files preserving raw inventory and assignment data' {
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'licenses' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('LicenseAssignments.csv','LicenseInventory.csv','Run.json')
  (Import-Csv $r.Paths.Inventory).Product | Should -Be "'=TEST"
  $r.Inventory[0].Product | Should -Be '=TEST'
  $r.Inventory[0].EnabledMinusConsumed | Should -Be 7
  $r.Assignments[0].Source | Should -Be 'Direct'
  $r.Paths.Coverage | Should -Be (Join-Path $r.ReportFolder 'Run.json')
 }
 It 'inventory-only mode omits assignment retrieval display and export' {
  $r=& $entry -InventoryOnly -NoInteractive -ExportDirectory $TestDrive -ReportName 'inventory' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('LicenseInventory.csv','Run.json')
  $r.Metadata.AssignmentsRequested | Should -BeFalse
  $r.Assignments.Count | Should -Be 0
  Should -Invoke Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Uri -match '/users' }
  Should -Invoke Show-M365Results -Times 1
 }
 It 'selected-user mode uses the same single export choice without a directory preprompt' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 2 -Exactly; 'n' }
  $r=& $entry -UserPrincipalName 'user@contoso.com' -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  Should -Invoke Read-Host -Times 1 -Exactly
  $r.Metadata.UsersRead | Should -Be 1
  Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Uri -match '/users/user%40contoso.com\?' }
 }
 It 'keeps assignment sources direct group and unknown distinct' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/subscribedSkus') { return [pscustomobject]@{value=@(New-Phase8Sku)} }
   $u=New-Phase8User
   $u.licenseAssignmentStates=@([pscustomobject]@{skuId='sku-1';assignedByGroup=$null;state='Active'},[pscustomobject]@{skuId='sku-1';assignedByGroup='group-1';state='Active'},[pscustomobject]@{skuId='sku-1';state='Active'})
   [pscustomobject]@{value=@($u)}
  }
  $r=& $entry -NoInteractive -PassThru
  @($r.Assignments.Source | Sort-Object) | Should -Be @('Direct','Group','Unknown')
 }
 It 'retains partial coverage when inventory retrieval fails but assignments succeed' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/subscribedSkus') { throw 'Synthetic SKU read denial' }
   [pscustomobject]@{value=@(New-Phase8User)}
  }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'partial' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.Complete | Should -BeFalse
  $r.Manifest.Status | Should -Be 'PartialCoverage'
  $r.Assignments.Count | Should -Be 1
  (Get-Content $r.Paths.Coverage -Raw | ConvertFrom-Json).InventoryComplete | Should -BeFalse
 }
 It 'keeps retrieval status and rows when export fails' {
  $r=& $entry -NoInteractive -ExportDirectory 'relative' -ReportName 'invalid' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Metadata.Complete | Should -BeTrue
  $r.Assignments.Count | Should -Be 1
  $r.Paths.Count | Should -Be 0
 }
 It 'retains explicit headers for empty inventory and assignments' {
  Mock Invoke-MgGraphRequest { [pscustomobject]@{value=@()} }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  (Get-Content $r.Paths.Inventory -First 1) | Should -Be '"Product","SkuId","AppliesTo","CapabilityStatus","EnabledUnits","ConsumedUnits","EnabledMinusConsumed","WarningUnits","SuspendedUnits","LockedOutUnits"'
  (Get-Content $r.Paths.Assignments -First 1) | Should -Be '"UserId","DisplayName","UserPrincipalName","AccountEnabled","UserType","SkuId","Product","Source","AssignedByGroup","State","Error","DisabledPlans","LastUpdated"'
 }
 It 'preserves IncludeUnlicensed classification' {
  Mock Invoke-MgGraphRequest {
   if ($Uri -match '/subscribedSkus') { return [pscustomobject]@{value=@(New-Phase8Sku)} }
   $u=New-Phase8User;$u.assignedLicenses=@();$u.licenseAssignmentStates=@()
   [pscustomobject]@{value=@($u)}
  }
  $r=& $entry -IncludeUnlicensed -NoInteractive -PassThru
  $r.Assignments[0].Source | Should -Be 'Unlicensed'
 }
 It 'blocks incompatible inventory and selected-user arguments before authentication' {
  { & $entry -InventoryOnly -UserPrincipalName 'user@contoso.com' -NoInteractive } | Should -Throw '*cannot be combined*'
  Should -Invoke Assert-M365Connection -Times 0
 }
 It 'contains no legacy save prompts or exporters and keeps display before optional export' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Initialize-R3SaveChoice|Export-R3Csv|Export-R3Coverage|Get-M365OutputPath|\$saveReport|\$selectedMode'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
