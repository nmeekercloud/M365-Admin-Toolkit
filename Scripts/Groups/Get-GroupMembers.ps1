#Requires -Version 7.4
<#
.SYNOPSIS
Resolve a group by name, mail or object ID and view its direct Graph members.
.DESCRIPTION
Read-only. Complete pagination. Nested groups are shown, not expanded.
Graph v1.0 may omit service principals; no complete effective-access claim.
Hidden-membership groups are not supported in this task version.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$GroupIdentity,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[switch]$ExportCsv)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ($ExportCsv -or $ExportDirectory -or $ReportName) -and -not ($ExportDirectory -and $ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName; ExportCsv alone no longer chooses an automatic path.' }
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Get-Module M365Toolkit.Core)) {
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop
}
. (Join-Path $root 'Tools/Toolkit.GroupMembers.Helpers.ps1')
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'groups.get-groupmembers'
$tenant=Assert-M365Connection -Service Graph -GraphScopes @('Group.Read.All','User.ReadBasic.All') -TaskId 'groups.get-groupmembers' -TaskName 'View group members'
if ([string](Get-MgContext -ErrorAction Stop).Environment -ne 'Global') { throw 'Only the global Graph endpoint is supported in this task version.' }
if (-not $GroupIdentity) {
    if ($NoInteractive) { throw 'GroupIdentity is required with NoInteractive.' }
    $GroupIdentity=([string](Read-Host 'Group name, email or object ID (Enter cancels)')).Trim()
    if (-not $GroupIdentity) { return }
}
$groupId=[guid]::Empty
$group=$null
$select='id,displayName,mail,visibility,groupTypes,mailEnabled,securityEnabled'
if ([guid]::TryParse($GroupIdentity,[ref]$groupId)) {
    $uri='https://graph.microsoft.com/v1.0/groups/{0}?$select={1}' -f $groupId.ToString('D'),$select
    $group=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable -ErrorAction Stop
    if ([string]$group['id'] -ine $groupId.ToString('D')) { throw 'Resolved group ID mismatch.' }
} else {
    $uri='https://graph.microsoft.com/v1.0/groups?$select='+$select+'&$top=999'
    Write-Host 'Finding groups...' -ForegroundColor Cyan
    $groups=@(Get-GMCollection -Uri $uri -ExpectedPath '/v1.0/groups' | Sort-Object { [string]$_['displayName'] },{ [string]$_['id'] })
    $matches=@(Select-GMGroupMatches -Groups $groups -Search $GroupIdentity)
    if ($NoInteractive) {
        $exact=@($groups | Where-Object { [string]$_['displayName'] -ieq $GroupIdentity -or [string]$_['mail'] -ieq $GroupIdentity })
        if ($exact.Count -ne 1) { throw 'No unique exact group name/email match. Use its object ID or interactive selection.' }
        $group=$exact[0]
    } else {
        while ($true) {
            if (-not $matches.Count) { Write-Host 'No matching Graph groups. Exchange dynamic distribution groups are not included.' -ForegroundColor Yellow }
            else {
                $display=@(for ($i=0;$i -lt $matches.Count;$i++) {
                    [pscustomobject]@{Number=($i+1);Name=[string]$matches[$i]['displayName'];Email=[string]$matches[$i]['mail'];Id=[string]$matches[$i]['id']}
                })
                $display | Format-Table -AutoSize -Wrap | Out-Host
            }
            $choice=([string](Read-Host 'Group number; S searches again; Enter cancels')).Trim()
            if (-not $choice) { return }
            if ($choice -ieq 'S') {
                $term=([string](Read-Host 'Search text (Enter lists all)')).Trim()
                $matches=@(Select-GMGroupMatches -Groups $groups -Search $term)
                continue
            }
            $n=0
            if ([int]::TryParse($choice,[ref]$n) -and $n -ge 1 -and $n -le $matches.Count) { $group=$matches[$n-1]; break }
            Write-Host 'Choose one of the displayed numbers, S, or Enter.' -ForegroundColor Yellow
        }
    }
}
if ($group -isnot [System.Collections.IDictionary]) { throw 'Invalid group response.' }
$resolved=[guid]::Empty
if (-not [guid]::TryParse([string]$group['id'],[ref]$resolved)) { throw 'Selected group has no valid object ID.' }
if ([string]$group['visibility'] -ieq 'HiddenMembership') {
    throw 'Hidden-membership groups require additional permission/role review. This version will not present an incomplete list as empty or request extra access mid-task.'
}
Write-Host ''
Write-Host ('Group: '+$group['displayName']+' <'+$group['mail']+'>') -ForegroundColor Cyan
Write-Host 'Direct members only. Nested groups are not expanded.'
Write-Host 'Coverage warning: Graph v1.0 can omit service principals; some object properties may be limited.' -ForegroundColor Yellow
$path='/v1.0/groups/'+$resolved.ToString('D')+'/members'
$members=@(Get-GMCollection -Uri ('https://graph.microsoft.com'+$path) -ExpectedPath $path)
$rows=@($members | ForEach-Object { ConvertTo-GMMemberRow -Member $_ -Group $group } | Sort-Object ObjectType,DisplayName,ObjectId)
Write-M365Log -Message ('Direct-member inventory read: '+$rows.Count+' objects returned.') -Level Info -Quiet
$initialExportRequested=[bool]$ExportCsv -or [bool]$ExportDirectory -or [bool]$ReportName
while ($true) {
    Write-Host ('Returned objects: '+$rows.Count) -ForegroundColor Cyan
    if ($rows.Count) {
        $display=@(for ($i=0;$i -lt $rows.Count;$i++) {
            [pscustomobject]@{Number=($i+1);Type=$rows[$i].ObjectType;Name=$rows[$i].DisplayName;UPN=$rows[$i].UserPrincipalName;Email=$rows[$i].Mail;Information=$rows[$i].Information}
        })
        Show-M365Results -InputObject $display -Title 'Direct group members' -NoPaging:$NoInteractive
    } else { Write-Host 'Graph returned no direct members. This is not proof of zero effective access.' -ForegroundColor Yellow }
    $exportRequested=$initialExportRequested; $initialExportRequested=$false; $action=''
    if (-not $NoInteractive) {
        Write-Host '[number] Details  [E] Export members  [0] Back'
        $action=([string](Read-Host 'Select [0]')).Trim()
        if ($action -ieq 'E') { $exportRequested=$true }
    }
    if ($exportRequested) {
        if ($WhatIfPreference) { Write-Host 'WhatIf: result export skipped; no report path created.' }
        elseif ($PSCmdlet.ShouldProcess('Chosen direct-members report bundle','Optionally export direct group members')) {
            . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
            $manifest=[ordered]@{
                TaskId='groups.get-groupmembers';TenantId=$tenant.TenantId
                GroupId=[string]$group['id'];GroupName=[string]$group['displayName']
                Status='CompletedWithKnownLimitations';FinishedUtc=[datetime]::UtcNow.ToString('o')
                ReturnedMemberRows=$rows.Count;Scope='Direct'
                LimitedInformationRows=@($rows | Where-Object Information -eq 'Limited information returned').Count
                Warnings=@('Nested groups are not expanded.','Graph v1.0 may omit service principals.','Returned counts do not prove effective access.','Some object properties may be limited.','Hidden-membership groups are blocked by this task.')
            }
            $columns=@('GroupName','GroupId','MembershipScope','ObjectType','DisplayName','UserPrincipalName','Mail','ObjectId','Information','Coverage')
            $exportResult=Export-ToolkitReportBundle -Tables @{'Members.csv'=$rows} -Manifest $manifest -Columns @{'Members.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
            Write-Host ('Export status: '+$exportResult.Status)
        }
    }
    if ($NoInteractive -or -not $action -or $action -eq '0') { break }
    if ($action -ieq 'E') { continue }
    $n=0
    if ([int]::TryParse($action,[ref]$n) -and $n -ge 1 -and $n -le $rows.Count) {
        $rows[$n-1] | Format-List | Out-Host
        Read-Host 'Press Enter to return to members' | Out-Null
    } else { Write-Host 'Choose a member number, E, or 0.' -ForegroundColor Yellow }
}
if ($PassThru) { $rows }
