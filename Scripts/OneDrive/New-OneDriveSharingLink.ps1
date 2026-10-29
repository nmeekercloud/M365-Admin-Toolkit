#Requires -Version 7.4
<#
.SYNOPSIS
Create/retrieve an expiring Organization/Anyone View/Edit link for one existing OneDrive item.
.DESCRIPTION
No automatic invitations, admin grants, provisioning or inherited-permission removal.
Link URL shown/returned only with explicit ShowLink or console approval; never saved in reports.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$UserPrincipalName,[string]$ItemPath,[string]$ItemId,
 [ValidateSet('Organization','Anonymous')][string]$Scope='Organization',
 [ValidateSet('View','Edit')][string]$LinkType='View',
 [datetimeoffset]$ExpiresUtc,[switch]$ShowLink,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Noninteractive export requires both ExportDirectory and ReportName.'}

. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveOutput.ps1')
if ($ItemPath -and $ItemId) {throw 'Choose ItemPath or ItemId.'}
if (-not $UserPrincipalName) {
 if ($NoInteractive) {throw 'UserPrincipalName required.'}
 $UserPrincipalName=([string](Read-Host 'OneDrive owner UPN (Enter cancels)')).Trim();if (-not $UserPrincipalName) {return}
}
if (-not $ItemPath -and -not $ItemId) {
 if ($NoInteractive) {throw 'ItemPath or ItemId required.'}
 $ItemPath=([string](Read-Host 'File/folder path INSIDE OneDrive Documents, e.g. HR/Handbook.docx (Enter cancels)')).Trim();if (-not $ItemPath) {return}
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Tools/Toolkit.OneDriveSharingStorage.Helpers.ps1')
if ($ItemPath) {$ItemPath=ConvertTo-OD34RelativePath $ItemPath}
if (-not $NoInteractive) {
 if (-not $PSBoundParameters.ContainsKey('Scope')) {
  $choice=([string](Read-Host 'Link audience [1] Organization (default) [2] ANYONE with the link')).Trim()
  if ($choice -notin @('','1','2')) {throw 'Invalid audience.'};if ($choice -eq '2') {$Scope='Anonymous'}
 }
 if (-not $PSBoundParameters.ContainsKey('LinkType')) {
  $choice=([string](Read-Host 'Permission [1] View (default) [2] Edit')).Trim()
  if ($choice -notin @('','1','2')) {throw 'Invalid permission.'};if ($choice -eq '2') {$LinkType='Edit'}
 }
}
if (-not $PSBoundParameters.ContainsKey('ExpiresUtc')) {
 $days=7
 if (-not $NoInteractive) {
  $value=([string](Read-Host 'Expiration in days [7], range 1-365')).Trim()
  if ($value -and (-not [int]::TryParse($value,[ref]$days) -or $days -lt 1 -or $days -gt 365)) {throw 'Choose 1 through 365 days.'}
 }
 $ExpiresUtc=[datetimeoffset]::UtcNow.AddDays($days)
}
$body=New-OD34LinkBody -Scope $Scope -LinkType $LinkType -ExpiresUtc $ExpiresUtc
$taskId='onedrive.new-onedrivesharinglink'
$tenant=Initialize-OD34Task $root $taskId Changes
$owner=Get-ODPUser $UserPrincipalName
$personal=Resolve-OD34PersonalSite $tenant $owner
$drive=Get-OD34Drive $personal
$item=Get-OD34Item -DriveId $drive['id'] -ItemPath $ItemPath -ItemId $ItemId
$before=@(Get-OD34Permissions -DriveId $drive['id'] -ItemId $item['id'])
$kind=if ($item.Contains('folder') -and $null -ne $item['folder']) {'Folder'} else {'File'}
$plan=[pscustomobject]@{OwnerUPN=$owner['userPrincipalName'];OwnerId=$owner['id'];OneDrive=$personal.Url;DriveId=$drive['id'];ItemId=$item['id'];ItemName=$item['name'];ItemWebUrl=$item['webUrl'];Kind=$kind;Audience=$Scope;Permission=$LinkType;ExpiresUtc=$body.expirationDateTime;RetainInheritedPermissions=$true}
$plan | Format-List | Out-Host
Write-Host 'A View link does not reduce access someone already has. No email/invitations sent. Existing equivalent app links may be returned instead of a new link.' -ForegroundColor Yellow
if ($Scope -eq 'Anonymous') {Write-Host 'ANYONE LINK: possession may grant access without sign-in, including outside the tenant. Tenant/site policy may forbid this.' -ForegroundColor Yellow}
if (-not $WhatIfPreference -and -not (Confirm-M365Action -Action ('Create/retrieve '+$Scope+' '+$LinkType+' sharing link; expires '+$body.expirationDateTime) -Target @($personal.Url,'Owner '+$owner['userPrincipalName']+' ['+$owner['id']+']',$item['name']+' | item '+$item['id']+' | drive '+$drive['id']) -Impact High)) {return}
if (-not $PSCmdlet.ShouldProcess(($item['name']+' on '+$personal.Url),('Create/retrieve '+$Scope+' '+$LinkType+' link'))) {
 Write-Host 'WhatIf/declined: no createLink request, backup or result file.'
 if ($PassThru) {[pscustomobject]@{Status='Planned';Plan=$plan}}
 return
}
# Revalidate owner/site/drive/item identities after approval; do not follow a renamed/moved target silently.
$null=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('User.Read.All','Sites.Read.All','Files.ReadWrite.All') -TaskId $taskId -TaskName 'Verify OneDrive sharing plan' -NoPrompt
$ownerNow=Get-ODPUser $owner['id'];$siteNow=Resolve-OD34PersonalSite $tenant $ownerNow;$driveNow=Get-OD34Drive $siteNow
if ([string]$ownerNow['id'] -ine [string]$owner['id'] -or [string]$ownerNow['userPrincipalName'] -ine [string]$owner['userPrincipalName'] -or $siteNow.Url -ine $personal.Url -or [string]$driveNow['id'] -cne [string]$drive['id']) {throw 'Owner/site/drive identity changed; rebuild sharing plan.'}
$itemNow=Get-OD34Item -DriveId $drive['id'] -ItemId $item['id']
if ([string]$itemNow['id'] -cne [string]$item['id'] -or [string]$itemNow['name'] -cne [string]$item['name'] -or [string]$itemNow['webUrl'] -cne [string]$item['webUrl']) {throw 'Item identity/path changed; rebuild sharing plan.'}
$null=New-OD34LinkBody -Scope $Scope -LinkType $LinkType -ExpiresUtc $ExpiresUtc
$backup=Get-M365OutputPath -Type Backups -FileName ('OneDriveLink-Before-'+[guid]::NewGuid().ToString('N')+'.json')
@{TenantId=$tenant.TenantId;Plan=$plan;PermissionSummary=$before;Note='Summary only; not complete restore data. Bearer sharing URLs omitted.'} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $backup -Encoding utf8 -ErrorAction Stop
$result=[pscustomobject]@{Status='Unverified';OwnerUPN=$owner['userPrincipalName'];OneDrive=$personal.Url;DriveId=$drive['id'];ItemId=$item['id'];PermissionId='';Scope=$Scope;Type=$LinkType;RequestedExpiration=$body.expirationDateTime;ObservedExpiration='';Backup=$backup;Detail=''}
$linkUrl=$null
try {
 $uri='https://graph.microsoft.com/v1.0/drives/'+[uri]::EscapeDataString([string]$drive['id'])+'/items/'+[uri]::EscapeDataString([string]$item['id'])+'/createLink'
 $permission=Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Compress) -ContentType 'application/json' -OutputType Hashtable -ErrorAction Stop
 $result.PermissionId=[string]$permission['id']
 if (-not $result.PermissionId) {throw 'Create-link response missing permission ID.'}
 $verifyUri=$uri.Replace('/createLink','/permissions/'+[uri]::EscapeDataString($result.PermissionId))+'?$select=id,link,roles,expirationDateTime'
 $verified=Invoke-MgGraphRequest -Method GET -Uri $verifyUri -OutputType Hashtable -ErrorAction Stop
 $link=Get-ODPValue $verified 'link'
 if ([string]$verified['id'] -cne $result.PermissionId -or [string](Get-ODPValue $link 'scope') -ine $body.scope -or [string](Get-ODPValue $link 'type') -ine $body.type) {throw 'Returned link scope/type/ID not verified.'}
 $expiryText=[string](Get-ODPValue $verified 'expirationDateTime');$result.ObservedExpiration=$expiryText
 $observed=[datetimeoffset]::MinValue
 if (-not [datetimeoffset]::TryParse($expiryText,[ref]$observed) -or [Math]::Abs(($observed.ToUniversalTime()-[datetimeoffset]::Parse($body.expirationDateTime)).TotalSeconds) -gt 1) {throw 'Server did not confirm requested expiration; existing-link reuse or policy may differ. No automatic alteration/retry.'}
 $linkUrl=[string](Get-ODPValue $link 'webUrl');$validUrl=$null
 if (-not [uri]::TryCreate($linkUrl,[UriKind]::Absolute,[ref]$validUrl) -or $validUrl.Scheme -ne 'https') {throw 'Verified permission lacks a valid HTTPS sharing URL.'}
 $result.Status='VerifiedLinkReturned';$result.Detail='Link ID/scope/type/expiration observed. May be reused; no recipient redemption test or new-link guarantee.'
} catch {
 $result.Status='Unverified';$result.Detail='Creation or verification failed/uncertain. No task-level POST retry; inspect current item sharing before rerunning. Error type: '+$_.Exception.GetType().Name
 $linkUrl=$null
 # Do not log raw responses/errors that may contain sharing secrets.
 Write-Warning $result.Detail
}
$export=Invoke-OD18Output -Tables @{'Outcome.csv'=@($result)} -Columns @{'Outcome.csv'=@('Status','OwnerUPN','OneDrive','DriveId','ItemId','PermissionId','Scope','Type','RequestedExpiration','ObservedExpiration','Backup','Detail')} -Manifest @{Task='onedrive.new-onedrivesharinglink';TenantId=$tenant.TenantId;Status='OutcomeSummary';Outcome=$result.Status;Notes=@('Bearer sharing URLs are excluded from export.','VerifiedLinkReturned is not a new-link guarantee or redemption test.','Required pre-change summary backup remains separate.')} -ExportDirectory $ExportDirectory -ReportName $ReportName -NoInteractive:$NoInteractive -PreviewOnly:$WhatIfPreference
Write-Host ('Result export: '+$export.Status)
if ($linkUrl -and -not $ShowLink -and -not $NoInteractive) {$ShowLink=([string](Read-Host 'Display sharing URL here? It may be captured by terminal history/transcripts. [y/N]')) -match '^(?i)y(es)?$'}
if ($linkUrl -and $ShowLink) {Write-Host 'Sharing URL (treat as sensitive):';Write-Host $linkUrl}
Write-M365Log -Message ('OneDrive sharing link outcome: '+$result.Status+'; scope '+$Scope+'; type '+$LinkType+'. Bearer URL not logged.') -Level Info -Quiet
if ($PassThru) {
 if ($ShowLink -and $linkUrl) {$result | Add-Member -NotePropertyName SharingUrl -NotePropertyValue $linkUrl}
 $result
}
$linkUrl=$null
