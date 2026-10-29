#Requires -Version 7.4
<#
.SYNOPSIS
Read-only Message Trace V2 report with bounded continuation and coverage metadata.
.DESCRIPTION
UTC date inputs; default last 48 hours. Supports one window up to 10 days within
90-day retention. Uses V2 continuation, not legacy page numbers. Exported coverage
states any result/request cap, query failure, or repeated cursor. No message changes.
.EXAMPLE
.\Get-MessageTraceReport.ps1 -SenderAddress user@contoso.com -StartDate '2026-10-19T00:00:00Z' -EndDate '2026-10-20T00:00:00Z'
.NOTES
Services: ExchangeOnline. GraphScopes: none. Impact: read-only.
#>
[CmdletBinding()]
param([string[]]$SenderAddress,[string[]]$RecipientAddress,[string]$MessageId,
      [guid]$MessageTraceId,[string[]]$Status,[datetimeoffset]$StartDate,[datetimeoffset]$EndDate,
      [ValidateRange(1,1000000)][int]$MaxResults=50000,[ValidateRange(1,1000)][int]$MaxRequests=30,
      [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ExchangeReports.ps1')
Initialize-ERTask
if (-not (Get-Command Get-MessageTraceV2 -ErrorAction SilentlyContinue)) { throw 'Get-MessageTraceV2 is unavailable in this Exchange session. Check the installed ExchangeOnlineManagement module and your RBAC role. No legacy fallback is used.' }
if ($PSBoundParameters.Count -eq 0) {
    $sender=([string](Read-Host 'Sender SMTP (blank = any)')).Trim()
    $recipient=([string](Read-Host 'Recipient SMTP (blank = any)')).Trim()
    if ($sender) { $SenderAddress=@($sender) }; if ($recipient) { $RecipientAddress=@($recipient) }
    while ($true) {
        $choice=([string](Read-Host '[1] Last 48 hours (default) [2] Last 24 hours [3] Custom UTC range [0] Cancel')).Trim()
        if ($choice -eq '0') { return }
        if ($choice -in @('','1','2')) {
            $EndDate=[datetimeoffset]::UtcNow
            $StartDate=$EndDate.AddHours($(if ($choice -eq '2') {-24} else {-48}))
            break
        }
        if ($choice -eq '3') {
            try {
                $StartDate=[datetimeoffset]::ParseExact((Read-Host 'UTC start: yyyy-MM-dd HH:mm'),'yyyy-MM-dd HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal)
                $EndDate=[datetimeoffset]::ParseExact((Read-Host 'UTC end: yyyy-MM-dd HH:mm'),'yyyy-MM-dd HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal)
                Assert-ERTraceWindow $StartDate $EndDate
                break
            } catch { Write-Warning $_.Exception.Message; continue }
        }
        Write-Warning 'Choose 1, 2, 3, or 0.'
    }
} else {
    if (-not $PSBoundParameters.ContainsKey('EndDate')) { $EndDate=[datetimeoffset]::UtcNow }
    if (-not $PSBoundParameters.ContainsKey('StartDate')) { $StartDate=$EndDate.AddHours(-48) }
}
Assert-ERTraceWindow $StartDate $EndDate
$query=@{StartDate=$StartDate.UtcDateTime;EndDate=$EndDate.UtcDateTime}
if ($SenderAddress) { $query.SenderAddress=$SenderAddress }
if ($RecipientAddress) { $query.RecipientAddress=$RecipientAddress }
if ($MessageId) { $query.MessageId=$MessageId }
if ($PSBoundParameters.ContainsKey('MessageTraceId')) { $query.MessageTraceId=$MessageTraceId }
if ($Status) { $query.Status=$Status }
Write-Host "Read-only trace: $($StartDate.UtcDateTime.ToString('u')) through $($EndDate.UtcDateTime.ToString('u')); MaxResults=$MaxResults; MaxRequests=$MaxRequests"
$result=Get-ERTraceData -Query $query -MaxResults $MaxResults -MaxRequests $MaxRequests
$metadata=[pscustomobject]@{Task='MessageTraceV2';Complete=$result.Complete;Issue=$result.Issue;StartUtc=$StartDate.UtcDateTime.ToString('o');EndUtc=$EndDate.UtcDateTime.ToString('o');Filters=$query;Rows=$result.Rows.Count;Requests=$result.Requests;MaxResults=$MaxResults;MaxRequests=$MaxRequests;Limitations='Service-reported trace results; not message content or a historical/compliance archive. Continuation is bounded. No event-detail queries in this baseline.'}
Show-M365Results -InputObject @($result.Rows | Select-Object Received,SenderAddress,RecipientAddress,Status,Subject) -Title 'Message Trace V2 results' -NoPaging:$NoInteractive
$metadata | Format-List | Out-Host
Write-Host "Rows retrieved: $($result.Rows.Count); complete=$($result.Complete). Console viewing does not limit exported or returned rows."
if (-not $result.Complete) { Write-Warning ('PARTIAL / FAILED query: '+$result.Issue+'. Inspect coverage; do not treat these results as complete.') }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportBundle.ps1')
$manifest=[ordered]@{}
foreach ($property in $metadata.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
$manifest['Status']=if ($metadata.Complete) {'CompletedWithinDeclaredScope'} else {'PartialCoverage'}
$manifest['FinishedUtc']=[datetime]::UtcNow.ToString('o')
$columns=@('Received','SenderAddress','RecipientAddress','Subject','Status','MessageTraceId','MessageId','FromIP','ToIP','Size')
$export=Export-ToolkitReportBundle -Tables @{'MessageTrace.csv'=$result.Rows} -Manifest $manifest -Columns @{'MessageTrace.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
$paths=[pscustomobject]@{Csv=$null;Coverage=$null}
if ($export.Status -eq 'Saved') {
 $paths.Csv=Join-Path $export.ReportFolder 'MessageTrace.csv'
 $paths.Coverage=Join-Path $export.ReportFolder 'Run.json'
}
Write-Host ('Export status: '+$export.Status)
if ($PassThru) { [pscustomobject]@{Rows=$result.Rows;Metadata=$metadata;Paths=$paths;ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
