# In-memory workflow consent coordination, NOT a security boundary against local code.
function Get-WF6DSettingsText {
 param([System.Collections.IDictionary]$Settings)
 $ordered=[ordered]@{}
 foreach ($key in @($Settings.Keys | Sort-Object)) {
  $value=$Settings[$key]
  if ($value -is [datetime]) { $value=$value.ToString('o',[cultureinfo]::InvariantCulture) }
  $ordered[[string]$key]=$value
 }
 ConvertTo-Json -InputObject $ordered -Depth 12 -Compress
}
function Copy-WF6DSettings {
 param([hashtable]$Settings)
 [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($Settings))
}
function Test-WF6DApproval {
 param([object]$Approval,[object]$Tenant,[System.Collections.IDictionary]$User,
       [string]$Action,[System.Collections.IDictionary]$Bound,[string]$DelegateId='')
 if ($null -eq $Approval) { return $false }
 if ($Approval.Kind -ne 'Offboarding6D' -or $Approval.Approved -ne $true) { throw 'Invalid workflow approval. Stop and rebuild the plan.' }
 if (-not $Tenant.TenantId -or [string]$Approval.TenantId -ine [string]$Tenant.TenantId -or
     [string]$Approval.UserId -ine [string]$User['id'] -or
     [string]$Approval.UPN -ine [string]$User['userPrincipalName'] -or $Approval.Action -cne $Action) {
  throw 'Workflow approval tenant, target, or action mismatch. Stop and rebuild the plan.'
 }
 if ([datetime]::UtcNow -gt $Approval.ExpiresUtc) { throw 'Workflow approval expired. Stop and rebuild the plan.' }
 if ($Bound['PlanOnly']) { throw 'Execution approval cannot be used for planning.' }
 $actual=@{}
 foreach ($key in $Approval.Settings.Keys) {
  if (-not $Bound.ContainsKey($key)) { throw ('Approved setting missing: '+$key) }
  $actual[$key]=$Bound[$key]
 }
 $allowed=@('UserPrincipalName','PassThru','WhatIf','Confirm','WorkflowApproval')+@($Approval.Settings.Keys)
 if ($Action -eq 'DeleteUser') { $allowed+=@('PriorResults') }
 foreach ($key in $Bound.Keys) { if ($key -notin $allowed) { throw ('Unapproved execution argument: '+$key) } }
 if ((Get-WF6DSettingsText $actual) -cne $Approval.SettingsText) { throw 'Settings differ from approved plan. Stop and rebuild the plan.' }
 if ($Action -eq 'Delegation' -and (-not $DelegateId -or $DelegateId -ine $Approval.DelegateId)) { throw 'Resolved delegate changed since planning. Stop and rebuild the plan.' }
 Write-M365Log -Message ('Using workflow approval '+$Approval.PlanId+' for '+$Action+' on '+$User['id']) -Level Info
 return $true
}
