#Requires -Version 7.4
[CmdletBinding()]
param([string]$ToolkitPath=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $ToolkitPath 'Tools/Toolkit.ExchangeReports.ps1')
$script:Count=0
function Assert-ERTest { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAILED: $Message" }; $script:Count++ }
$rule=[pscustomobject]@{ForwardTo=@('external@example.net');ForwardAsAttachmentTo=@();RedirectTo=@();DeleteMessage=$true;MarkAsRead=$false;StopProcessingRules=$false;MoveToFolder=''}
$signals=@(Get-ERRuleSignals $rule)
Assert-ERTest ($signals.Count -eq 2 -and 'ForwardTo' -in $signals -and 'DeleteMessage' -in $signals) 'forwarding/delete review signals'
$rule.ForwardTo=@(); $rule.DeleteMessage=$false
Assert-ERTest (@(Get-ERRuleSignals $rule).Count -eq 0) 'no invented review signal'
$now=[datetimeoffset]::UtcNow
Assert-ERTraceWindow $now.AddHours(-2) $now
$failed=$false; try { Assert-ERTraceWindow $now $now.AddHours(-1) } catch { $failed=$true }
Assert-ERTest $failed 'reversed date range rejected'
$failed=$false; try { Assert-ERTraceWindow $now.AddDays(-11) $now } catch { $failed=$true }
Assert-ERTest $failed 'over-ten-day window rejected'
$failed=$false; try { Assert-ERTraceWindow $now.AddDays(-95) $now.AddDays(-94) } catch { $failed=$true }
Assert-ERTest $failed 'expired trace history rejected'
$t=$now.UtcDateTime.AddMinutes(-5)
$a=[pscustomobject]@{MessageTraceId='a';RecipientAddress='a@example.net';Received=$t}
$b=[pscustomobject]@{MessageTraceId='b';RecipientAddress='b@example.net';Received=$t.AddSeconds(-1)}
$c=[pscustomobject]@{MessageTraceId='c';RecipientAddress='c@example.net';Received=$t.AddSeconds(-2)}
$script:Pages=@{0=@($a,$b);1=@($b,$c);2=@()}; $script:Calls=0; $script:Captured=[System.Collections.Generic.List[object]]::new(); $script:FailAt=-1
function Get-MessageTraceV2 {
    [CmdletBinding()]
    param($StartDate,$EndDate,$ResultSize,$StartingRecipientAddress,$SenderAddress,$RecipientAddress,$MessageId,$MessageTraceId,$Status)
    $script:Captured.Add([pscustomobject]@{EndDate=$EndDate;Recipient=$StartingRecipientAddress})
    $index=$script:Calls; $script:Calls++
    if ($index -eq $script:FailAt) { throw 'synthetic service failure' }
    return $script:Pages[$index]
}
$query=@{StartDate=$now.UtcDateTime.AddHours(-1);EndDate=$now.UtcDateTime}
$result=Get-ERTraceData -Query $query -BatchSize 2 -DelayMilliseconds 0
Assert-ERTest ($result.Complete -and $result.Rows.Count -eq 3 -and $result.Requests -eq 3) 'overlapping batches deduplicate and finish'
Assert-ERTest ($script:Captured[1].Recipient -eq $b.RecipientAddress -and $script:Captured[1].EndDate -eq $b.Received) 'last response row supplies continuation'
Assert-ERTest (-not $query.ContainsKey('StartingRecipientAddress')) 'caller query not mutated'
$script:Calls=0
$result=Get-ERTraceData -Query $query -BatchSize 2 -MaxRequests 1 -DelayMilliseconds 0
Assert-ERTest (-not $result.Complete -and $result.Rows.Count -eq 2 -and $result.Issue -match 'MaxRequests') 'request cap marks partial'
$script:Calls=0
$result=Get-ERTraceData -Query $query -BatchSize 2 -MaxResults 1 -DelayMilliseconds 0
Assert-ERTest (-not $result.Complete -and $result.Rows.Count -eq 1 -and $result.Issue -match 'MaxResults') 'result cap marks partial'
$script:Calls=0; $script:FailAt=1
$result=Get-ERTraceData -Query $query -BatchSize 2 -DelayMilliseconds 0
Assert-ERTest (-not $result.Complete -and $result.Rows.Count -eq 2 -and $result.Issue -match 'synthetic service failure') 'query failure retains partial rows'
$script:Calls=0; $script:FailAt=-1; $script:Pages=@{0=@($a,$b);1=@($a,$b)}
$result=Get-ERTraceData -Query $query -BatchSize 2 -DelayMilliseconds 0
Assert-ERTest (-not $result.Complete -and $result.Issue -match 'no progress') 'stalled continuation stops'
$script:Calls=0; $script:Pages=@{0=@()}
$result=Get-ERTraceData -Query $query -BatchSize 2 -DelayMilliseconds 0
Assert-ERTest ($result.Complete -and $result.Rows.Count -eq 0) 'empty successful query is complete'
foreach ($stem in @('Search-InboxRules','Get-MessageTraceReport')) {
    $data=Import-PowerShellDataFile (Join-Path $ToolkitPath "Scripts/Exchange/$stem.task.psd1")
    Assert-ERTest ($data.Status -eq 'Ready' -and $data.AccessMode -eq 'ReadOnly' -and @($data.GraphScopes).Count -eq 0 -and $data.Services[0] -eq 'ExchangeOnline') "manifest $stem"
}
Write-Host "Exchange report helper checks passed: $script:Count. Synthetic data/fake reads only; no tenant calls."
