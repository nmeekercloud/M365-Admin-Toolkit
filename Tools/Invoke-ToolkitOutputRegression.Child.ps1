param([string]$TestPath,[string]$PesterPath,[string]$ResultPath)
$ErrorActionPreference='Stop'
try {
 Import-Module -Name $PesterPath -ErrorAction Stop
 $result=Invoke-Pester -Path $TestPath -Output Detailed -PassThru
 $failed=@($result.Tests | Where-Object Result -eq 'Failed' | ForEach-Object {[pscustomobject]@{Name=$_.ExpandedPath;Error=(@($_.ErrorRecord | ForEach-Object {$_.ToString()}) -join "`n")}})
 $summary=[pscustomobject]@{Result=[string]$result.Result;Total=$result.TotalCount;Passed=$result.PassedCount;Failed=$result.FailedCount;Skipped=$result.SkippedCount;NotRun=$result.NotRunCount;Failures=$failed;Error=''}
 $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding utf8
 if ($result.Result -ne 'Passed' -or $result.FailedCount -or $result.SkippedCount -or $result.NotRunCount -or -not $result.TotalCount) {exit 1}
} catch {
 [pscustomobject]@{Result='Error';Total=0;Passed=0;Failed=0;Skipped=0;NotRun=0;Failures=@();Error=$_.Exception.Message} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding utf8
 exit 1
}
