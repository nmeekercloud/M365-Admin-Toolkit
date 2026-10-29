# Static inspection only. Never dot-source or execute target scripts.
function Get-ToolkitOutputAudit {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$RepositoryPath)
 $root=(Resolve-Path -LiteralPath $RepositoryPath).Path
 $inventory=[Collections.Generic.List[object]]::new()
 $persistence=[Collections.Generic.List[object]]::new()
 $review=[Collections.Generic.List[object]]::new()
 $files=@(foreach ($area in @('Scripts','Tools','Modules')) {
  $dir=Join-Path $root $area
  if (Test-Path -LiteralPath $dir -PathType Container) {Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}}
 })
 $start=Join-Path $root 'Start-M365Toolkit.ps1'
 if (Test-Path -LiteralPath $start -PathType Leaf) {$files+=Get-Item -LiteralPath $start}
 foreach ($file in $files) {
  $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  foreach ($error in @($errors)) {$review.Add([pscustomobject]@{Path=$relative;Line=$error.Extent.StartLineNumber;Category='ParseError';Priority='ActionRequired';Detail=$error.Message})}
  $commands=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true))
  $names=@($commands | ForEach-Object {$_.GetCommandName()} | Where-Object {$_})
  $routes=@($names | Where-Object {$_ -match '^(Show-M365Results|Export-M365Csv|Export-ToolkitReportBundle|Show-Toolkit.*Result|Invoke-OD18Output|Invoke-UT19Output|Write-UT19Results|Complete-UT19Step|Write-EX17Results|Complete-EX17Step|Show-EX17Output|Complete-OD18ArchiveStep|Invoke-SARReport)$'} | Sort-Object -Unique)
  $inventory.Add([pscustomobject]@{Path=$relative;Area=($relative -split '/')[0];ParseErrors=@($errors).Count;OutputRoutes=($routes -join '; ');LegacyWriterCalls=(@($names | Where-Object {$_ -in @('Export-ERReport','Export-R3Csv','Export-R3Coverage','Write-E12Results','Write-UMResults')}) -join '; ');FormatCommands=@($names | Where-Object {$_ -in @('Format-Table','Format-List')}).Count})
  foreach ($command in $commands) {
   $name=$command.GetCommandName()
   if ($name -notin @('Export-Csv','Set-Content','Add-Content','Out-File','New-Item','Move-Item','Copy-Item','Remove-Item','Get-M365OutputPath','Save-UMJson','Save-E12Backup','Export-ERReport','Export-R3Csv','Export-R3Coverage','Write-E12Results','Write-UMResults','Format-Table','Format-List')) {continue}
   $parent=$command.Parent;$fn=''
   while ($parent) {if ($parent -is [Management.Automation.Language.FunctionDefinitionAst]) {$fn=$parent.Name;break};$parent=$parent.Parent}
   $category='PersistenceReview';$priority='Review';$detail='Static command match; intent/reachability requires review.'
   if ($name -in @('Format-Table','Format-List')) {$category='PreviewOrUiReview';$detail='May be intentional plan/detail/approval output; not automatically a defect.'}
   elseif ($name -in @('Save-UMJson','Save-E12Backup') -or $fn -in @('Save-UMJson','Save-E12Backup')) {$category='SnapshotOrJournal';$priority='Inventory';$detail='Preserve pending policy review; may be required safety snapshot or operational journal.'}
   elseif ($fn -in @('Export-ERReport','Export-R3Csv','Export-R3Coverage','Write-E12Results')) {$category='LegacyHelperDefinition';$detail='Legacy helper body retained; a match is not proof of an active call path.'}
   elseif ($name -in @('Export-ERReport','Export-R3Csv','Export-R3Coverage','Write-E12Results','Write-UMResults')) {$category='LegacyCallSite';$detail='Check whether an active workflow still reaches this older output route.'}
   elseif ($relative -match '^Tools/(Invoke-ToolkitOutputAudit|Invoke-ToolkitOutputRegression)\.ps1$') {$category='AuditDiagnostics';$priority='Inventory';$detail='Developer audit/test diagnostics, not automatic tenant report output.'}
   elseif ($name -eq 'Get-M365OutputPath') {
    if ($command.Extent.Text -match '-Type\s+Backups') {$category='SnapshotPath';$priority='Inventory';$detail='Required backup path retained.'}
    elseif ($command.Extent.Text -match '-Type\s+Reports' -and $relative -like 'Scripts/*') {$category='DirectReportPath';$priority='ActionRequired';$detail='Direct report-path allocation in an entrypoint needs review; not proof of an unapproved write.'}
   }
   elseif ($relative -like 'Modules/*') {$category='CorePersistenceReview';$detail='Review approval/path guards in the owning core function.'}
   $row=[pscustomobject]@{Path=$relative;Line=$command.Extent.StartLineNumber;Function=$fn;Command=$name;Category=$category;Priority=$priority}
   $persistence.Add($row)
   if ($priority -ne 'Inventory') {$review.Add([pscustomobject]@{Path=$relative;Line=$row.Line;Category=$category;Priority=$priority;Detail=$detail})}
  }
  $methods=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Member.Value -in @('WriteAllText','WriteAllLines','WriteAllBytes','AppendAllText','AppendAllLines')},$true))
  foreach ($method in $methods) {$review.Add([pscustomobject]@{Path=$relative;Line=$method.Extent.StartLineNumber;Category='DotNetWriteReview';Priority='Review';Detail='Direct .NET write method; statically inspect destination and approval guards.'})}
 }
 $scriptDir=Join-Path $root 'Scripts'
 if (Test-Path -LiteralPath $scriptDir) {
  foreach ($file in @(Get-ChildItem -LiteralPath $scriptDir -Recurse -Filter '*.task.psd1' -File)) {
   $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
   try {
    $definition=Import-PowerShellDataFile -LiteralPath $file.FullName
    if ($definition.Status -eq 'Ready') {
     if (-not $definition.Script) {throw 'Ready task has no Script.'}
     $target=[IO.Path]::GetFullPath((Join-Path $file.DirectoryName ([string]$definition.Script)))
     if (-not $target.StartsWith($root.TrimEnd([char[]]'\/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Ready task script resolves outside repository.'}
     if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {throw 'Ready task script is missing.'}
    }
   } catch {$review.Add([pscustomobject]@{Path=$relative;Line=0;Category='TaskDefinition';Priority='ActionRequired';Detail=$_.Exception.Message})}
  }
 }
 foreach ($area in @('Scripts','Tools','Modules')) {
  $dir=Join-Path $root $area
  if (-not (Test-Path -LiteralPath $dir)) {continue}
  foreach ($file in @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {$_.Name -match '\.backup[-.]|\.bak$'})) {
   $review.Add([pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/');Line=0;Category='RepositoryBackupArtifact';Priority='Review';Detail='Check whether obsolete backup copies should be removed from version control; nothing deleted automatically.'})
  }
 }
 $testDir=Join-Path $root 'Tests'
 if (Test-Path -LiteralPath $testDir) {
  foreach ($file in @(Get-ChildItem -LiteralPath $testDir -Recurse -Filter '*.Tests.ps1' -File)) {
   if ($file.Name -match 'OutputPhase|OutputStandardization\.Phase1|OutputAudit\.Tests') {continue}
   if ([IO.File]::ReadAllText($file.FullName) -match 'Get-M365OutputPath|Export-ERReport|Export-R3Csv|Export-R3Coverage|Write-E12Results|Initialize-R3SaveChoice|\.partial') {
    $review.Add([pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/');Line=0;Category='LegacyTestExpectationReview';Priority='Review';Detail='Older test mentions migrated output mechanisms; inspect assertions before updating or running. No tests removed or weakened.'})
   }
  }
 }
 [pscustomobject]@{Inventory=$inventory.ToArray();Persistence=$persistence.ToArray();Review=$review.ToArray();Summary=[pscustomobject]@{ScannedSourceFiles=$inventory.Count;ParseErrors=@($review.ToArray() | Where-Object Category -eq 'ParseError').Count;ActionRequired=@($review.ToArray() | Where-Object Priority -eq 'ActionRequired').Count;ReviewFindings=@($review.ToArray() | Where-Object Priority -eq 'Review').Count;Status='ReviewRequired';Limitations='Static inventory, not data-flow/reachability analysis or live validation. Matches are candidates, not automatic defects. No completion certification.'}}
}
function Write-ToolkitOutputAudit {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string]$OutputDirectory)
 $root=(Resolve-Path -LiteralPath $RepositoryPath).Path
 . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
 $dest=Resolve-ToolkitReportBundlePath -Path $OutputDirectory
 if (Test-Path -LiteralPath $dest) {throw 'Audit destination already exists; refusing overwrite.'}
 $result=Get-ToolkitOutputAudit -RepositoryPath $root
 $null=New-Item -ItemType Directory -Path $dest -ErrorAction Stop
 foreach ($name in @('Inventory','Persistence','Review')) {
  $rows=@($result.$name)
  if ($rows.Count) {$rows | Export-Csv -LiteralPath (Join-Path $dest ($name+'.csv')) -NoTypeInformation -Encoding utf8}
  else {
   $headers=switch ($name) {'Inventory' {'Path,Area,ParseErrors,OutputRoutes,LegacyWriterCalls,FormatCommands'} 'Persistence' {'Path,Line,Function,Command,Category,Priority'} 'Review' {'Path,Line,Category,Priority,Detail'}}
   Set-Content -LiteralPath (Join-Path $dest ($name+'.csv')) -Value $headers -Encoding utf8
  }
 }
 $result.Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dest 'AuditSummary.json') -Encoding utf8
 $result.Summary
}
