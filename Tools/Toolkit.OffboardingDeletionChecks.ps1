function Assert-WF7BPrerequisites {
 [CmdletBinding()]
 param([AllowEmptyCollection()][string[]]$RequiredStepIds=@(),[object[]]$PriorResults=@(),[switch]$WhatIfMode)
 $required=@($RequiredStepIds | Select-Object -Unique)
 if ($required.Count -ne $RequiredStepIds.Count) { throw 'Duplicate deletion prerequisite.' }
 if (@($required | Where-Object { $_ -notin @('BlockAccess','Forwarding','AutoReply','Delegation','ArchiveOneDrive','RemoveLicenses') }).Count) { throw 'Invalid deletion prerequisite.' }
 if (@($PriorResults).Count -ne $required.Count) { throw 'Prerequisite result count mismatch; deletion blocked.' }
 foreach ($id in $required) {
  $matches=@($PriorResults | Where-Object { $_.Step -eq $id })
  if ($matches.Count -ne 1) { throw ('Missing or duplicate prerequisite: '+$id) }
  if ($matches[0].Result -ne 'Success' -and -not ($WhatIfMode -and $matches[0].Result -eq 'Planned')) { throw ('Prerequisite not successful: '+$id) }
 }
}
function Get-WF7BAuthIdentity {
 [CmdletBinding()]
 param()
 $c=Get-MgContext -ErrorAction Stop
 $tenant=[guid]::Empty; $client=[guid]::Empty
 if (-not $c -or [string]$c.AuthType -ne 'Delegated' -or
     -not [guid]::TryParse([string]$c.TenantId,[ref]$tenant) -or $tenant -eq [guid]::Empty -or
     -not [guid]::TryParse([string]$c.ClientId,[ref]$client) -or $client -eq [guid]::Empty -or
     -not $c.Account -or @($c.Scopes).Count -eq 0 -or -not $c.Environment) {
  throw 'A complete delegated Graph identity is required; deletion blocked.'
 }
 [pscustomobject]@{TenantId=$tenant.ToString('D');ClientId=$client.ToString('D');Account=[string]$c.Account;
   Environment=[string]$c.Environment;Scopes=@($c.Scopes);Flow=[string]$c.TokenCredentialType}
}
function Assert-WF7BAuthIdentity {
 [CmdletBinding()]
 param([Parameter(Mandatory)]$Expected)
 $actual=Get-WF7BAuthIdentity
 foreach ($name in @('TenantId','ClientId','Account','Environment')) {
  if ([string]$actual.$name -ine [string]$Expected.$name) { throw "Graph identity changed ($name); deletion blocked. Rebuild the plan." }
 }
 foreach ($scope in $Expected.Scopes) {
  if ($scope -notin $actual.Scopes) { throw 'Graph scope lost; deletion blocked.' }
 }
 if ($Expected.Flow -eq 'InteractiveBrowser' -and $actual.Flow -ne 'InteractiveBrowser') {
  throw 'Interactive authentication changed to another flow; deletion blocked.'
 }
}
function Invoke-WF7BDeleteOnce {
 [CmdletBinding()]
 param([Parameter(Mandatory)][guid]$UserId,
       [Parameter(Mandatory)][scriptblock]$BeforeDelete,
       [scriptblock]$AfterDelete)
 if ($UserId -eq [guid]::Empty) { throw 'Empty deletion target ID; request not sent.' }
 $stage='ValidateUri'; $restore=$false; $requestStarted=$false
 try {
  $uri=[uri]('https://graph.microsoft.com/v1.0/users/{0}' -f $UserId.ToString('D'))
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'graph.microsoft.com') { throw 'Invalid Graph deletion endpoint.' }
  $stage='CaptureAuthIdentity'; $identity=Get-WF7BAuthIdentity
  $stage='ReadRetryContext'
  $context=Get-MgRequestContext -ErrorAction Stop
  if ($null -eq $context.MaxRetry) { throw 'Could not read SDK retry configuration.' }
  $oldRetry=[int]$context.MaxRetry
  $stage='DisableSdkRetries'; $restore=$true
  $null=Set-MgRequestContext -MaxRetry 0 -Confirm:$false -ErrorAction Stop
  if ((Get-MgRequestContext -ErrorAction Stop).MaxRetry -ne 0) { throw 'Could not disable SDK retries.' }
  $stage='AuthenticationReadCheck'
  try {
   $me=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName' -OutputType PSObject -ErrorAction Stop
  } catch {
   # Recovery is permitted only before DELETE and only for the observed URI failure.
   $e=$_.Exception; $uriFailure=$false
   while ($null -ne $e) {
    if ($e -is [System.UriFormatException]) { $uriFailure=$true; break }
    $e=$e.InnerException
   }
   if (-not $uriFailure -or $identity.Flow -ne 'InteractiveBrowser') { throw }
   Assert-WF7BAuthIdentity -Expected $identity
   # One automatic interactive reconnect; existing workflow approval is revalidated below.
   Write-M365Log -Message 'Refreshing Graph sign-in before deletion; no DELETE request has been sent.' -Level Info
   $stage='InteractiveReconnect'
   # Reinitialize through the public SDK API with the original cloud/client/scopes.
   # No disconnect, broker/cache clearing, option changes, or device-code fallback.
   Connect-MgGraph -TenantId $identity.TenantId -ClientId $identity.ClientId -Environment $identity.Environment -Scopes $identity.Scopes -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Host
   Assert-WF7BAuthIdentity -Expected $identity
   $stage='VerifyRetryContextAfterReconnect'
   if ((Get-MgRequestContext -ErrorAction Stop).MaxRetry -ne 0) { throw 'Reconnect changed retry policy; deletion blocked.' }
   $stage='AuthenticationReadCheckAfterReconnect'
   # One read retry only. This catch does NOT encompass DELETE.
   $me=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName' -OutputType PSObject -ErrorAction Stop
  }
  $stage='VerifyAuthenticatedIdentity'
  Assert-WF7BAuthIdentity -Expected $identity
  if (-not $me.id -or [string]$me.userPrincipalName -ine $identity.Account) { throw 'Graph /me does not match approved account; deletion blocked.' }
  $org=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id' -OutputType PSObject -ErrorAction Stop
  $organizations=@($org.value)
  if ($organizations.Count -ne 1 -or [string]$organizations[0].id -ine $identity.TenantId) { throw 'Graph organization does not match original tenant; deletion blocked.' }
  $stage='FinalApprovalAndTargetCheck'
  if ((& $BeforeDelete) -ne $true) { throw 'Final target/approval check did not approve deletion.' }
  Assert-WF7BAuthIdentity -Expected $identity
  if ((Get-MgRequestContext -ErrorAction Stop).MaxRetry -ne 0) { throw 'Retry policy changed before DELETE; deletion blocked.' }
  $stage='DeleteRequest'; $requestStarted=$true
  $null=Invoke-MgGraphRequest -Method DELETE -Uri $uri.AbsoluteUri -ErrorAction Stop
  if ($AfterDelete) {
   $stage='DeletedUserVerification'
   try { & $AfterDelete }
   catch {
    # A post-DELETE read/reporting failure must never be labeled DELETE failure.
    [pscustomobject]@{Status='VerificationIncomplete';Verified=$false;ReadAttempts=0;Detail=('DELETE returned without an exception; verification callback failed: '+$_.Exception.Message+' Do not retry deletion. Inspect active/deleted users.')}
   }
  }
 } catch {
  $status=if ($requestStarted) { 'Request may have been sent; verify active/deleted users.' } else { 'Delete request was not reached.' }
  throw ('Stage '+$stage+': '+$_.Exception.Message+' '+$status)
 } finally {
  if ($restore) {
   try { $null=Set-MgRequestContext -MaxRetry $oldRetry -Confirm:$false -ErrorAction Stop }
   catch { Write-Warning 'Could not restore Graph retry configuration. Close this toolkit session before further operations.' }
  }
 }
}

function Get-WF7BProperty {
 param([object]$Object,[string]$Name)
 if ($null -eq $Object) { return $null }
 if ($Object -is [System.Collections.IDictionary]) {
  if ($Object.Contains($Name)) { return $Object[$Name] }
  return $null
 }
 $p=$Object.PSObject.Properties[$Name]
 if ($p) { return $p.Value }
 return $null
}
function Get-WF7BReadRetryInfo {
 param([Parameter(Mandatory)][Exception]$Exception)
 $code=0; $retryAfter=0; $e=$Exception
 while ($null -ne $e) {
  $response=Get-WF7BProperty $e 'Response'
  foreach ($candidate in @((Get-WF7BProperty $e 'ResponseStatusCode'),(Get-WF7BProperty $e 'StatusCode'),(Get-WF7BProperty $response 'StatusCode'))) {
   $parsed=0
   if ($null -ne $candidate) {
    try { $parsed=[int]$candidate; $code=$parsed; break } catch { }
   }
  }
  foreach ($headers in @((Get-WF7BProperty $response 'Headers'),(Get-WF7BProperty $e 'ResponseHeaders'))) {
   if ($null -eq $headers) { continue }
   $typed=Get-WF7BProperty $headers 'RetryAfter'
   $delta=Get-WF7BProperty $typed 'Delta'; $date=Get-WF7BProperty $typed 'Date'
   if ($null -ne $delta) { $retryAfter=[Math]::Max($retryAfter,[Math]::Ceiling($delta.TotalSeconds)) }
   if ($null -ne $date) { $retryAfter=[Math]::Max($retryAfter,[Math]::Ceiling(([datetimeoffset]$date-[datetimeoffset]::UtcNow).TotalSeconds)) }
   $raw=Get-WF7BProperty $headers 'Retry-After'
   if (-not $raw -and $headers.PSObject.Methods['TryGetValues']) {
    $values=$null
    if ($headers.TryGetValues('Retry-After',[ref]$values)) { $raw=@($values)[0] }
   }
   if ($raw) {
    $seconds=0; $when=[datetimeoffset]::MinValue
    if ([int]::TryParse([string]@($raw)[0],[ref]$seconds)) { $retryAfter=[Math]::Max($retryAfter,$seconds) }
    elseif ([datetimeoffset]::TryParse([string]@($raw)[0],[ref]$when)) { $retryAfter=[Math]::Max($retryAfter,[Math]::Ceiling(($when-[datetimeoffset]::UtcNow).TotalSeconds)) }
   }
  }
  $e=$e.InnerException
 }
 [pscustomobject]@{StatusCode=$code;RetryAfterSeconds=[int][Math]::Max(0,$retryAfter)}
}
function Test-WF7BDeletedUser {
 [CmdletBinding()]
 param([Parameter(Mandatory)][guid]$UserId)
 if ($UserId -eq [guid]::Empty) { throw 'Empty deleted-user verification ID.' }
 $detail='Deleted object not yet verified.'; $attempt=0
 for ($attempt=1; $attempt -le 4; $attempt++) {
  try {
   $deleted=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/directory/deletedItems/'+$UserId.ToString('D')) -OutputType Hashtable -ErrorAction Stop
   $returnedId=[string](Get-WF7BProperty $deleted 'id')
   $returnedType=[string](Get-WF7BProperty $deleted '@odata.type')
   if ($returnedId -ieq $UserId.ToString('D') -and $returnedType -eq '#microsoft.graph.user') {
    return [pscustomobject]@{Status='Success';Verified=$true;ReadAttempts=$attempt;Detail=('Verified in deleted users; ID '+$UserId+'. No permanent purge requested.')}
   }
   $detail='Deleted-user response did not contain the expected user object ID and type.'
   break
  } catch {
   $detail=$_.Exception.Message
   $retry=Get-WF7BReadRetryInfo -Exception $_.Exception
   # Authentication/URI errors, 401/403 and unknown failures are not transient reads.
   if ($retry.StatusCode -notin @(404,408,429,500,502,503,504)) { break }
   if ($attempt -ge 4) { break }
   $delay=[Math]::Max((3*[Math]::Pow(2,$attempt-1)),$retry.RetryAfterSeconds)
   if ($delay -gt 60) {
    $detail+=' Server retry delay exceeds this verification budget; inspect the account later.'
    break
   }
   Start-Sleep -Seconds ([int]$delay)
  }
 }
 [pscustomobject]@{Status='VerificationIncomplete';Verified=$false;ReadAttempts=$attempt;Detail=('DELETE returned without an exception; deleted-user verification incomplete for ID '+$UserId+': '+$detail+' Do not retry deletion. Inspect active/deleted users.')}
}
