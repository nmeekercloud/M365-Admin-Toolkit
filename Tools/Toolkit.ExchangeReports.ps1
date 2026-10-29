#Requires -Version 7.4
function Initialize-ERTask {
    if (-not (Get-Module M365Toolkit.Core)) {
        Import-Module (Join-Path $PSScriptRoot '../Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
    }
    $null=Assert-M365Connection -Service ExchangeOnline
}
function Invoke-ERRead {
    param([scriptblock]$Operation,[ValidateRange(1,5)][int]$Attempts=3)
    for ($i=1; $i -le $Attempts; $i++) {
        try { return (& $Operation) }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Warning "Read failed; retry $i/$Attempts : $($_.Exception.Message)"
            Start-Sleep -Seconds ([math]::Pow(2,$i))
        }
    }
}
function Get-ERRuleSignals {
    param($Rule)
    foreach ($field in @('ForwardTo','ForwardAsAttachmentTo','RedirectTo')) {
        if (@($Rule.$field | Where-Object { [string]$_ }).Count) { $field }
    }
    foreach ($field in @('DeleteMessage','MarkAsRead','StopProcessingRules')) {
        if ($Rule.$field -eq $true) { $field }
    }
    if ([string]$Rule.MoveToFolder) { 'MoveToFolder' }
}
function Assert-ERTraceWindow {
    param([datetimeoffset]$Start,[datetimeoffset]$End)
    $now=[datetimeoffset]::UtcNow
    if ($End -le $Start) { throw 'EndDate must be later than StartDate.' }
    if (($End-$Start).TotalDays -gt 10) { throw 'Use a window of 10 days or less.' }
    if ($Start -lt $now.AddDays(-90)) { throw 'StartDate must be within the last 90 days.' }
    if ($End -gt $now.AddMinutes(1)) { throw 'EndDate cannot be in the future.' }
}
function Get-ERTraceData {
    param([hashtable]$Query,[ValidateRange(1,1000000)][int]$MaxResults=50000,
          [ValidateRange(1,1000)][int]$MaxRequests=30,[ValidateRange(1,5000)][int]$BatchSize=5000,
          [ValidateRange(0,60000)][int]$DelayMilliseconds=3100)
    $rows=[System.Collections.Generic.List[object]]::new()
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $cursors=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $request=@{}; foreach ($key in $Query.Keys) { $request[$key]=$Query[$key] }
    $request.ResultSize=$BatchSize
    $requests=0; $complete=$false; $issue=''
    try {
        while ($requests -lt $MaxRequests) {
            if ($requests -and $DelayMilliseconds) { Start-Sleep -Milliseconds $DelayMilliseconds }
            # Count requests; a failed request preserves earlier collected rows.
            $requests++
            $batch=@(Get-MessageTraceV2 @request -ErrorAction Stop)
            if (-not $batch.Count) { $complete=$true; break }
            $added=0
            foreach ($row in $batch) {
                if (-not $row.MessageTraceId -or -not $row.RecipientAddress -or -not $row.Received) { throw 'Trace response lacks a required continuation/identity field.' }
                $key=([string]$row.MessageTraceId)+'|'+([string]$row.RecipientAddress)+'|'+([datetime]$row.Received).ToString('o')
                if ($seen.Add($key)) {
                    if ($rows.Count -ge $MaxResults) { $issue='MaxResults reached; narrow the filters or raise the limit.'; break }
                    $rows.Add($row); $added++
                }
            }
            if ($issue) { break }
            if ($batch.Count -lt $BatchSize) { $complete=$true; break }
            if ($rows.Count -ge $MaxResults) { $issue='MaxResults reached; completeness not established.'; break }
            if (-not $added) { throw 'Continuation made no progress; stopping rather than looping.' }
            # Preserve service order. Microsoft specifies values from the LAST response row.
            $last=$batch[-1]
            $cursorEnd=[datetime]$last.Received
            if ($cursorEnd.Kind -eq [DateTimeKind]::Unspecified) { $cursorEnd=[datetime]::SpecifyKind($cursorEnd,[DateTimeKind]::Utc) }
            $cursorEnd=$cursorEnd.ToUniversalTime()
            if ($cursorEnd -lt [datetime]$request.StartDate -or $cursorEnd -gt [datetime]$request.EndDate) { throw 'Continuation timestamp is outside the query window.' }
            $cursor=$cursorEnd.ToString('o')+'|'+[string]$last.RecipientAddress
            if (-not $cursors.Add($cursor)) { throw 'Repeated continuation cursor; completeness not established.' }
            $request.EndDate=$cursorEnd
            $request.StartingRecipientAddress=[string]$last.RecipientAddress
        }
        if (-not $complete -and -not $issue) { $issue='MaxRequests reached; completeness not established.' }
    } catch { $issue=$_.Exception.Message }
    [pscustomobject]@{Rows=@($rows.ToArray());Complete=$complete;Requests=$requests;Issue=$issue}
}
function Export-ERReport {
    param([object[]]$Rows,[string[]]$Columns,[string]$Label,$Metadata)
    $tag=$Label+'-'+[guid]::NewGuid().ToString('N')
    $csv=Get-M365OutputPath -Type Reports -FileName ($tag+'.csv')
    $json=Get-M365OutputPath -Type Reports -FileName ($tag+'-Coverage.json')
    $safe=@(foreach ($row in $Rows) {
        $record=[ordered]@{}
        foreach ($column in $Columns) {
            $value=$row.$column
            # Preserve values in pipeline objects; neutralize formula-like strings in CSV only.
            if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
            $record[$column]=$value
        }
        [pscustomobject]$record
    })
    if ($safe.Count) { $safe | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8 }
    else { ($Columns -join ',') | Set-Content -LiteralPath $csv -Encoding utf8 }
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json -Encoding utf8
    Write-M365Log -Message "Report: $csv ; coverage: $json" -Level Info
    [pscustomobject]@{Csv=$csv;Coverage=$json}
}
