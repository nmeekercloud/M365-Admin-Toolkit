BeforeAll {
 $root=Split-Path $PSScriptRoot -Parent
 $entry=Join-Path $root 'Scripts/Exchange/Get-MessageTraceReport.ps1'
 function Show-M365Results { param($InputObject,$Title,[switch]$NoPaging) }
 function Assert-M365Connection { param($Service) }
 function Get-MessageTraceV2 {
  [CmdletBinding()]
  param($StartDate,$EndDate,$ResultSize,$SenderAddress,$RecipientAddress,$MessageId,$MessageTraceId,$Status,$StartingRecipientAddress)
  throw 'Unmocked trace read blocked'
 }
 function New-Phase16Row {
  param([int]$Number=1)
  [pscustomobject]@{Received=[datetime]::UtcNow.AddHours(-1);SenderAddress='sender@contoso.com';RecipientAddress=('recipient'+$Number+'@contoso.com');Subject='=Example';Status='Delivered';MessageTraceId=('00000000-0000-4000-8000-'+$Number.ToString('000000000000'));MessageId=('message-'+$Number);FromIP='';ToIP='';Size=123}
 }
}
Describe 'Phase 16 Message Trace display-first export' {
 BeforeEach {
  Mock Get-Module { [pscustomobject]@{Name='M365Toolkit.Core'} } -ParameterFilter { $Name -eq 'M365Toolkit.Core' }
  Mock Assert-M365Connection {}
  Mock Get-MessageTraceV2 { New-Phase16Row }
  Mock Show-M365Results {}
  Mock Write-Host {}
  Mock Write-Warning {}
  Mock Start-Sleep {}
  Mock Read-Host { 'n' }
 }
 It 'displays trace data before offering export and declining writes nothing' {
  Mock Read-Host { Should -Invoke Show-M365Results -Times 1 -Exactly; 'n' }
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -PassThru
  $r.ExportStatus | Should -Be 'Declined'
  $r.Paths.Csv | Should -BeNullOrEmpty
  Should -Invoke New-Item -Times 0
 }
 It 'does not prompt or save by default in noninteractive mode' {
  Mock New-Item { throw 'Unexpected directory creation' }
  $r=& $entry -NoInteractive -PassThru
  $r.ExportStatus | Should -Be 'NotRequested'
  Should -Invoke Read-Host -Times 0
  Should -Invoke New-Item -Times 0
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { $NoPaging }
 }
 It 'exports only MessageTrace.csv and Run.json with safe cells and raw passthrough' {
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'trace' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  @((Get-ChildItem $r.ReportFolder -File).Name | Sort-Object) | Should -Be @('MessageTrace.csv','Run.json')
  (Import-Csv $r.Paths.Csv).Subject | Should -Be "'=Example"
  $r.Rows[0].Subject | Should -Be '=Example'
  $r.Paths.Coverage | Should -Be (Join-Path $r.ReportFolder 'Run.json')
 }
 It 'retains more than 100 rows for display export and passthrough' {
  Mock Get-MessageTraceV2 { 1..125 | ForEach-Object { New-Phase16Row -Number $_ } }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'many' -PassThru
  $r.Rows.Count | Should -Be 125
  @(Import-Csv $r.Paths.Csv).Count | Should -Be 125
  Should -Invoke Show-M365Results -Times 1 -ParameterFilter { @($InputObject).Count -eq 125 }
 }
 It 'retains partial metadata when MaxResults truncates a response' {
  Mock Get-MessageTraceV2 { New-Phase16Row -Number 1;New-Phase16Row -Number 2 }
  $r=& $entry -NoInteractive -MaxResults 1 -ExportDirectory $TestDrive -ReportName 'capped' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Rows.Count | Should -Be 1
  $r.Metadata.Complete | Should -BeFalse
  $r.Metadata.Issue | Should -Match 'MaxResults'
  $r.Manifest.Status | Should -Be 'PartialCoverage'
 }
 It 'retains query failures as incomplete even when an empty bundle saves' {
  Mock Get-MessageTraceV2 { throw 'Synthetic trace denial' }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'failed' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.Complete | Should -BeFalse
  $r.Manifest.Status | Should -Be 'PartialCoverage'
  $r.Metadata.Issue | Should -Match 'Synthetic trace denial'
 }
 It 'preserves completed empty headers and scope metadata' {
  Mock Get-MessageTraceV2 { @() }
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'empty' -PassThru
  $r.ExportStatus | Should -Be 'Saved'
  $r.Metadata.Complete | Should -BeTrue
  (Get-Content $r.Paths.Csv -First 1) | Should -Be '"Received","SenderAddress","RecipientAddress","Subject","Status","MessageTraceId","MessageId","FromIP","ToIP","Size"'
 }
 It 'keeps retrieval completeness and rows when export fails' {
  $r=& $entry -NoInteractive -ExportDirectory 'relative' -ReportName 'bad' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  $r.Metadata.Complete | Should -BeTrue
  $r.Rows.Count | Should -Be 1
  $r.Paths.Csv | Should -BeNullOrEmpty
 }
 It 'preserves explicit query filters and leaves omitted filters out of the query' {
  $r=& $entry -NoInteractive -SenderAddress 'sender@contoso.com' -RecipientAddress 'recipient@contoso.com' -Status 'Delivered' -MessageId 'wanted' -PassThru
  $r.Metadata.Filters.SenderAddress | Should -Contain 'sender@contoso.com'
  $r.Metadata.Filters.RecipientAddress | Should -Contain 'recipient@contoso.com'
  $r.Metadata.Filters.Status | Should -Contain 'Delivered'
  $r.Metadata.Filters.MessageId | Should -Be 'wanted'
  $default=& $entry -NoInteractive -PassThru
  $default.Metadata.Filters.ContainsKey('SenderAddress') | Should -BeFalse
  $default.Metadata.Filters.ContainsKey('RecipientAddress') | Should -BeFalse
  $default.Metadata.Filters.ContainsKey('Status') | Should -BeFalse
 }
 It 'retains default 48-hour UTC range and rejects invalid windows before trace requests' {
  $r=& $entry -NoInteractive -PassThru
  (([datetime]$r.Metadata.EndUtc)-([datetime]$r.Metadata.StartUtc)).TotalHours | Should -Be 48
  { & $entry -NoInteractive -StartDate ([datetimeoffset]::UtcNow.AddDays(-11)) -EndDate ([datetimeoffset]::UtcNow) } | Should -Throw '*10 days or less*'
  Should -Invoke Get-MessageTraceV2 -Times 1 -Exactly
 }
 It 'refuses existing bundles without overwriting their data' {
  $folder=Join-Path $TestDrive 'existing';$null=New-Item -ItemType Directory -Path $folder
  Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'original'
  $r=& $entry -NoInteractive -ExportDirectory $TestDrive -ReportName 'existing' -PassThru
  $r.ExportStatus | Should -Be 'ExportFailed'
  (Get-Content (Join-Path $folder 'keep.txt')) | Should -Be 'original'
 }
 It 'removes automatic export and the hardcoded 100-row display truncation' {
  $text=Get-Content $entry -Raw
  $text | Should -Not -Match 'Export-ERReport|Get-M365OutputPath|Export-Csv|Select-Object -First 100'
  $text.IndexOf('Show-M365Results') | Should -BeLessThan $text.IndexOf('$export=Export-ToolkitReportBundle')
 }
}
