BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 . (Join-Path $root 'Tools/Toolkit.BulkCsvTemplates.ps1')
 . (Join-Path $root 'Tools/Toolkit.BulkSharePointAccess.Helpers.ps1')
 . (Join-Path $root 'Tools/Toolkit.BulkGroupMembers.Helpers.ps1')
 $catalog=Import-PowerShellDataFile (Join-Path $root 'Config/BulkCsvTemplates.psd1')
}
Describe 'Bulk CSV template contract' {
 BeforeEach {
  Mock Write-Host {}
  $script:answers=[Collections.Generic.Queue[string]]::new()
  Mock Read-Host { if (-not $script:answers.Count) { throw 'Unexpected prompt' }; $script:answers.Dequeue() }
 }
 It 'ships header-only templates for all three registered bulk tasks' {
  $catalog.Count | Should -Be 3
  foreach ($kind in $catalog.Keys) {
   $d=$catalog[$kind]
   ([IO.File]::ReadAllText((Join-Path $root $d.Template))).Trim() | Should -BeExactly ($d.Columns -join ',')
   Test-Path (Join-Path $root $d.Script) -PathType Leaf | Should -BeTrue
  }
 }
 It 'SharePoint template header matches the strict importer and rejects blank data' {
  $file=Join-Path $root $catalog.SharePointAccess.Template
  { Import-BSACsv -LiteralPath $file } | Should -Throw '*headers only*'
  $work=Join-Path $TestDrive 'sharepoint-input.csv'
  [IO.File]::WriteAllText($work,([IO.File]::ReadAllText($file).Trim()+"`nhttps://contoso.sharepoint.com/sites/test,5,example@contoso.com`n"))
  $rows=@(Import-BSACsv -LiteralPath $work)
  $rows.Count | Should -Be 1
  $rows[0].SharePointGroupId | Should -Be 5
 }
 It 'GroupMembers template header matches the strict importer and rejects blank data' {
  $file=Join-Path $root $catalog.GroupMembers.Template
  { Import-BGMCsv -LiteralPath $file } | Should -Throw '*only headers*'
  $work=Join-Path $TestDrive 'groups-input.csv'
  [IO.File]::WriteAllText($work,([IO.File]::ReadAllText($file).Trim()+"`n11111111-2222-3333-4444-555555555555,example@contoso.com`n"))
  @(Import-BGMCsv -LiteralPath $work).Count | Should -Be 1
 }
 It 'retains the existing user template and allowed user columns' {
  $source=Get-Content (Join-Path $root $catalog.Users.Script) -Raw
  foreach ($name in $catalog.Users.Columns) { $source | Should -Match ([regex]::Escape("'"+$name+"'")) }
 }
 It 'Enter at the CSV prompt cancels without writing anything' {
  $script:answers.Enqueue('')
  Mock New-Item { throw 'Unapproved directory creation' }
  Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind SharePointAccess | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'shows the schema and template before returning a supplied input path' {
  $r=Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind SharePointAccess -CsvPath 'input.csv'
  $r | Should -Be 'input.csv'
  Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*SiteUrl,SharePointGroupId,UserPrincipalName*' }
  Should -Invoke Read-Host -Times 0
 }
 It 'noninteractive invocation requires an explicit populated input path' {
  { Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind GroupMembers -NoInteractive } | Should -Throw '*CsvPath is required*'
  Should -Invoke Read-Host -Times 0
 }
 It 'T saves only the header at the selected external location then returns to input' {
  $dest=Join-Path $TestDrive 'selected-template.csv'
  $script:answers.Enqueue('t'); $script:answers.Enqueue($dest); $script:answers.Enqueue('populated-input.csv')
  $r=Read-ToolkitBulkCsvPath -ToolkitRoot $root -Kind SharePointAccess
  $r | Should -Be 'populated-input.csv'
  ([IO.File]::ReadAllText($dest)).Trim() | Should -BeExactly 'SiteUrl,SharePointGroupId,UserPrincipalName'
  @(Import-Csv $dest).Count | Should -Be 0
 }
 It 'blank save destination cancels without creating files or folders' {
  $script:answers.Enqueue('')
  Mock New-Item { throw 'Unapproved directory creation' }
  (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users).Status | Should -Be 'Cancelled'
  Should -Invoke New-Item -Times 0
 }
 It 'declining overwrite preserves the existing file' {
  $dest=Join-Path $TestDrive 'keep.csv'; Set-Content $dest 'original'
  $script:answers.Enqueue('n')
  (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users -Path $dest).Status | Should -Be 'Cancelled'
  (Get-Content $dest -Raw).Trim() | Should -Be 'original'
 }
 It 'declining creation leaves the missing parent absent' {
  $dir=Join-Path $TestDrive 'not-created'
  $script:answers.Enqueue('n')
  (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind GroupMembers -Path (Join-Path $dir 'template.csv')).Status | Should -Be 'Cancelled'
  Test-Path $dir | Should -BeFalse
 }
 It 'blocks working-template saves inside the repository' {
  $dest=Join-Path $root 'should-not-write.csv'
  (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users -Path $dest -WarningAction SilentlyContinue).Status | Should -Be 'SaveFailed'
  Test-Path $dest | Should -BeFalse
 }
 It 'WhatIf does not create a template file' {
  $dest=Join-Path $TestDrive 'preview.csv'
  (Save-ToolkitBulkCsvTemplate -ToolkitRoot $root -Kind Users -Path $dest -WhatIf).Status | Should -Be 'Planned'
  Test-Path $dest | Should -BeFalse
 }
 It 'wires each task to its own template guidance before CSV import' {
  foreach ($kind in $catalog.Keys) {
   $source=Get-Content (Join-Path $root $catalog[$kind].Script) -Raw
   $guide=$source.IndexOf('Read-ToolkitBulkCsvPath',[StringComparison]::Ordinal)
   $parse=if ($kind -eq 'Users') { $source.IndexOf('$rows=@(Import-Csv',[StringComparison]::Ordinal) } elseif ($kind -eq 'GroupMembers') { $source.IndexOf('$inputRows=@(Import-BGMCsv',[StringComparison]::Ordinal) } else { $source.IndexOf('$inputRows=@(Import-BSACsv',[StringComparison]::Ordinal) }
   $guide | Should -BeGreaterThan -1
   $parse | Should -BeGreaterThan $guide
   $source | Should -Match ('-Kind '+$kind+'\b')
  }
 }
}
