[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$PesterPath)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root=(Resolve-Path -LiteralPath $RepositoryPath).Path
. (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
$dest=Resolve-ToolkitReportBundlePath $OutputDirectory
if (Test-Path -LiteralPath $dest) {throw 'Regression destination exists; refusing overwrite.'}
$roster=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'OutputRegression.Roster.psd1')
foreach ($entry in $roster.Suites) {if (-not (Test-Path -LiteralPath (Join-Path $root ('Tests/'+$entry.Name)) -PathType Leaf)) {throw ('Missing test suite: '+$entry.Name)}}
$exe=Join-Path $PSHOME $(if ($IsWindows) {'pwsh.exe'} else {'pwsh'})
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {throw 'PowerShell child executable unavailable.'}
$null=New-Item -ItemType Directory -Path $dest -ErrorAction Stop
$summary=[Collections.Generic.List[object]]::new()
foreach ($entry in $roster.Suites) {
 $name=[string]$entry.Name;$tag=[IO.Path]::GetFileNameWithoutExtension($name)
 $json=Join-Path $dest ($tag+'.json');$log=Join-Path $dest ($tag+'.log')
 & $exe -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Invoke-ToolkitOutputRegression.Child.ps1') -TestPath (Join-Path $root ('Tests/'+$name)) -PesterPath $PesterPath -ResultPath $json *> $log
 $code=$LASTEXITCODE
 $r=if (Test-Path -LiteralPath $json) {Get-Content -LiteralPath $json -Raw | ConvertFrom-Json} else {[pscustomobject]@{Result='Error';Total=0;Passed=0;Failed=0;Skipped=0;NotRun=0;Failures=@();Error='Child process produced no result JSON.'}}
 $ok=($code -eq 0 -and $r.Result -eq 'Passed' -and $r.Total -eq $entry.Expected -and $r.Passed -eq $entry.Expected -and -not $r.Failed -and -not $r.Skipped -and -not $r.NotRun)
 $status=if ($ok) {'Passed'} else {'FAILED'}
 Write-Host ("{0}: {1} ({2}/{3})" -f $name,$status,$r.Passed,$entry.Expected)
 if (-not $ok) {
  if ($r.Error) {Write-Host $r.Error -ForegroundColor Yellow}
  foreach ($failure in @($r.Failures)) {Write-Host ($failure.Name+': '+$failure.Error) -ForegroundColor Yellow}
 }
 $summary.Add([pscustomobject]@{Suite=$name;Status=$status;Expected=$entry.Expected;Total=$r.Total;Passed=$r.Passed;Failed=$r.Failed;Skipped=$r.Skipped;NotRun=$r.NotRun;ExitCode=$code;Log=[IO.Path]::GetFileName($log)})
}
$summary.ToArray() | Export-Csv -LiteralPath (Join-Path $dest 'RegressionSummary.csv') -NoTypeInformation -Encoding utf8
$all=[pscustomobject]@{Suites=$summary.Count;Expected=($summary.ToArray() | Measure-Object Expected -Sum).Sum;Passed=($summary.ToArray() | Measure-Object Passed -Sum).Sum;FailedSuites=@($summary.ToArray() | Where-Object Status -ne 'Passed').Count;Scope='Curated output regression suites only; NOT the entire toolkit suite or live workflow validation';Isolation='One fresh non-profile, noninteractive PowerShell process per suite'}
$all | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dest 'RegressionSummary.json') -Encoding utf8
$all | Format-List | Out-Host
if ($all.FailedSuites) {throw ('Output regression failed in '+$all.FailedSuites+' suite(s). Logs: '+$dest)}
