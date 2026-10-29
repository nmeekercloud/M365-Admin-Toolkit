# Pester 5; local/synthetic tests only. No tenant calls or service SDK imports.
BeforeAll {
 $script:regRoot=Split-Path -Parent $PSScriptRoot
 . (Join-Path $script:regRoot 'Modules/M365Toolkit.Core/Private/DependencyCompatibility.ps1')
 . (Join-Path $script:regRoot 'Tools/Toolkit.SharePointAccessScanner.ps1')
}
Describe 'CSV scanner serialization regression' {
 BeforeEach {
  $script:csvFolder=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Path $script:csvFolder
  $script:csvContext=@{Folder=$script:csvFolder;OutputFailed=$false}
 }
 It 'appends the supplied object without losing the SiteUrl schema' {
  Initialize-SARCsv (Join-Path $script:csvFolder 'Grants.csv') @('SiteUrl','Object','Count')
  Write-SARRow -Context $script:csvContext -File 'Grants.csv' -Row ([pscustomobject]@{SiteUrl='https://contoso.sharepoint.com/sites/Test';Object='=BAD()';Count=0})
  $rows=@(Import-Csv -LiteralPath (Join-Path $script:csvFolder 'Grants.csv'))
  $rows.Count | Should -Be 1
  $rows[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/Test'
  $rows[0].Object | Should -Be "'=BAD()"
  $rows[0].Count | Should -Be '0'
  $script:csvContext.OutputFailed | Should -BeFalse
 }
 It 'retains the schema-mismatch failure rather than forcing mismatched output' {
  Initialize-SARCsv (Join-Path $script:csvFolder 'Grants.csv') @('SiteUrl','Object')
  { Write-SARRow -Context $script:csvContext -File 'Grants.csv' -Row ([pscustomobject]@{Wrong='field'}) } | Should -Throw
  $script:csvContext.OutputFailed | Should -BeTrue
 }
}
Describe 'Offline import regression contracts' {
 It 'does not execute the compatibility bootstrap at core import' {
  $p=Join-Path $script:regRoot 'Modules/M365Toolkit.Core/M365Toolkit.Core.psm1'
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  @($errors).Count | Should -Be 0
  @($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Initialize-ToolkitDependencyCompatibility'},$true)).Count | Should -Be 0
 }
 It 'keeps SDK status probes limited to already imported commands' {
  $p=Join-Path $script:regRoot 'Modules/M365Toolkit.Core/Private/ConnectionHelpers.ps1'
  $source=[IO.File]::ReadAllText($p)
  $source | Should -Match "Get-Command -Name 'Get-MgContext' -ListImported"
  $source | Should -Match "Get-Command -Name 'Get-ConnectionInformation' -ListImported"
 }
 It 'uses the same normalized version comparison for pinned module selection' {
  $p=Join-Path $script:regRoot 'Modules/M365Toolkit.Core/Private/TenantHelpers.ps1'
  $source=[IO.File]::ReadAllText($p)
  $source | Should -Match 'ConvertTo-ToolkitComparableVersion \$loaded.Version'
  $source | Should -Match 'ConvertTo-ToolkitComparableVersion \$_\.Version'
 }
 It 'keeps task-authentication module scopes inside runtime Pester blocks' {
  $p=Join-Path $script:regRoot 'Tests/Toolkit.TaskAuthentication.Tests.ps1'
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  @($errors).Count | Should -Be 0
  $scopes=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'InModuleScope'},$true))
  foreach ($scope in $scopes) {
   $parent=$scope.Parent;$run=$false
   while ($null -ne $parent) {
    if ($parent -is [Management.Automation.Language.CommandAst] -and $parent.GetCommandName() -in @('It','BeforeAll','BeforeEach','AfterAll','AfterEach')) {$run=$true;break}
    $parent=$parent.Parent
   }
   $run | Should -BeTrue
  }
 }
}
