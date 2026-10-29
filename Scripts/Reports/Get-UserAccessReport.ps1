#Requires -Version 7.4
<#
.SYNOPSIS
Report scoped directory access for selected users, with explicit coverage gaps.
.DESCRIPTION
Profile, assigned licenses, direct/transitive groups, owned groups and directly
assigned active directory role assignments. Not an effective-access certification.
No Exchange/SharePoint/OneDrive or workload-permission claims are made.
.EXAMPLE
.\Get-UserAccessReport.ps1 -UserPrincipalName user@contoso.com -PassThru
.NOTES
Services: Graph. Scopes: User.Read.All, Group.Read.All,
LicenseAssignment.Read.All, RoleManagement.Read.Directory. Read-only.
#>
[CmdletBinding()]
param([string[]]$UserPrincipalName,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportsAuditing.ps1')
if (-not @($UserPrincipalName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count) {
    if ($NoInteractive) { throw 'UserPrincipalName is required with NoInteractive.' }
    $text=([string](Read-Host 'User UPNs, comma-separated (blank cancels)')).Trim()
    if (-not $text) { return }
    $UserPrincipalName=@($text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
Initialize-R3Task @('User.Read.All','Group.Read.All','LicenseAssignment.Read.All','RoleManagement.Read.Directory')
Write-Host 'Read-only DIRECTORY baseline. Not a complete effective-access audit across Microsoft 365.'
$users=Get-R3Users -UserPrincipalName $UserPrincipalName -Select 'id,displayName,userPrincipalName,mail,accountEnabled,userType,assignedLicenses,licenseAssignmentStates'
$skus=Get-R3Collection 'https://graph.microsoft.com/v1.0/subscribedSkus'
$map=Get-R3SkuMap $skus.Rows
$profiles=[System.Collections.Generic.List[object]]::new()
$licenses=[System.Collections.Generic.List[object]]::new()
$groups=[System.Collections.Generic.List[object]]::new()
$roles=[System.Collections.Generic.List[object]]::new()
$segments=[System.Collections.Generic.List[object]]::new()
$segments.Add([pscustomobject]@{User='Selected users';Segment='User resolution';Complete=$users.Complete;Rows=$users.Rows.Count;Issue=$users.Issue})
$segments.Add([pscustomobject]@{User='Tenant';Segment='SKU inventory';Complete=$skus.Complete;Rows=$skus.Rows.Count;Issue=$skus.Issue})
foreach ($user in $users.Rows) {
    $id=[string](Get-R3Field $user 'id'); $upn=[string](Get-R3Field $user 'userPrincipalName')
    $base='https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($id)
    $profiles.Add([pscustomobject]@{UserId=$id;DisplayName=[string](Get-R3Field $user 'displayName');UserPrincipalName=$upn;Mail=[string](Get-R3Field $user 'mail');AccountEnabled=Get-R3Field $user 'accountEnabled';UserType=[string](Get-R3Field $user 'userType')})
    foreach ($row in @(Get-R3LicenseRows $user $map -IncludeUnlicensed)) { $licenses.Add($row) }
    $direct=Get-R3Collection ($base+'/memberOf/microsoft.graph.group?$count=true&$select=id,displayName,groupTypes,mailEnabled,securityEnabled,membershipRule,onPremisesSyncEnabled')
    $transitive=Get-R3Collection ($base+'/transitiveMemberOf/microsoft.graph.group?$count=true&$select=id,displayName,groupTypes,mailEnabled,securityEnabled,membershipRule,onPremisesSyncEnabled')
    $owned=Get-R3Collection ($base+'/ownedObjects')
    $directIds=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($g in $direct.Rows) { $null=$directIds.Add([string](Get-R3Field $g 'id')) }
    $emitted=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $limited=0
    foreach ($g in @($direct.Rows)+@($transitive.Rows)) {
        $groupId=[string](Get-R3Field $g 'id')
        if (-not $groupId -or -not $emitted.Add($groupId)) { continue }
        $name=[string](Get-R3Field $g 'displayName')
        if (-not $name) { $limited++ }
        $relation=if ($directIds.Contains($groupId)) {'DirectMember'} elseif ($direct.Complete) {'IndirectMember'} else {'TransitiveMember; directness unknown'}
        $groups.Add([pscustomobject]@{UserPrincipalName=$upn;GroupId=$groupId;GroupName=$name;Relationship=$relation;GroupTypes=(@(Get-R3Field $g 'groupTypes' @()) -join '; ');MailEnabled=Get-R3Field $g 'mailEnabled';SecurityEnabled=Get-R3Field $g 'securityEnabled';DynamicRule=[string](Get-R3Field $g 'membershipRule');OnPremisesSyncEnabled=Get-R3Field $g 'onPremisesSyncEnabled';MetadataLimited=(-not [bool]$name)})
    }
    foreach ($g in @($owned.Rows | Where-Object { (Get-R3Field $_ '@odata.type') -eq '#microsoft.graph.group' })) {
        $name=[string](Get-R3Field $g 'displayName'); if (-not $name) { $limited++ }
        $groups.Add([pscustomobject]@{UserPrincipalName=$upn;GroupId=[string](Get-R3Field $g 'id');GroupName=$name;Relationship='Owner (not proof of membership)';GroupTypes=(@(Get-R3Field $g 'groupTypes' @()) -join '; ');MailEnabled=Get-R3Field $g 'mailEnabled';SecurityEnabled=Get-R3Field $g 'securityEnabled';DynamicRule=[string](Get-R3Field $g 'membershipRule');OnPremisesSyncEnabled=Get-R3Field $g 'onPremisesSyncEnabled';MetadataLimited=(-not [bool]$name)})
    }
    $safeId=$id.Replace("'","''")
    $roleFilter=[uri]::EscapeDataString("principalId eq '$safeId'")
    $activeRoles=Get-R3Collection ('https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$filter='+$roleFilter+'&$expand=roleDefinition')
    foreach ($role in $activeRoles.Rows) {
        $definition=Get-R3Field $role 'roleDefinition'
        $roles.Add([pscustomobject]@{UserPrincipalName=$upn;AssignmentId=[string](Get-R3Field $role 'id');RoleDefinitionId=[string](Get-R3Field $role 'roleDefinitionId');RoleName=[string](Get-R3Field $definition 'displayName');PrincipalId=[string](Get-R3Field $role 'principalId');DirectoryScopeId=[string](Get-R3Field $role 'directoryScopeId');AppScopeId=[string](Get-R3Field $role 'appScopeId');Source='Direct principal roleAssignment; no group or PIM eligibility expansion'})
    }
    foreach ($entry in @(@('Direct groups',$direct),@('Transitive groups',$transitive),@('Owned groups',$owned),@('Direct active directory roles',$activeRoles))) {
        $segments.Add([pscustomobject]@{User=$upn;Segment=$entry[0];Complete=$entry[1].Complete;Rows=$entry[1].Rows.Count;Issue=$entry[1].Issue})
    }
    if ($limited) { $segments.Add([pscustomobject]@{User=$upn;Segment='Group metadata visibility';Complete=$false;Rows=$limited;Issue='Objects returned without display names; metadata visibility is limited.'}) }
}
$paths=[ordered]@{}
$metadata=[pscustomobject]@{Task='UserAccessReport';Coverage='Directory baseline only';CollectedSegmentsComplete=(@($segments.ToArray() | Where-Object { -not $_.Complete }).Count -eq 0);IsFullEffectiveAccessAudit=$false;Segments=@($segments.ToArray());Excluded=@('Hidden membership requiring additional access','Mailbox delegation and folder permissions','SharePoint/OneDrive sites, files, sharing links','Enterprise-app assignments and OAuth grants','PIM eligibility and role assignment schedule history','Group-derived directory role assignments','Azure RBAC, Intune and other workload roles');Notes='Membership/ownership are directory relationships, not proof of access to every resource. Transitive membership includes direct membership. Group owners need not be members.'}
Show-M365Results -InputObject $profiles.ToArray() -Title 'User profiles' -NoPaging:$NoInteractive
Show-M365Results -InputObject @($licenses.ToArray() | Select-Object UserPrincipalName,Product,Source,State,Error) -Title 'User licenses' -NoPaging:$NoInteractive
Show-M365Results -InputObject @($groups.ToArray() | Select-Object UserPrincipalName,GroupName,Relationship) -Title 'Group memberships and ownership' -NoPaging:$NoInteractive
Show-M365Results -InputObject @($roles.ToArray() | Select-Object UserPrincipalName,RoleName,DirectoryScopeId) -Title 'Direct active Entra roles' -NoPaging:$NoInteractive
Show-M365Results -InputObject $segments.ToArray() -Title 'Directory collection coverage' -NoPaging:$NoInteractive
$metadata | Format-List | Out-Host
Write-Warning 'This directory baseline is NOT a complete effective-access audit. Inspect coverage and exclusions; a saved Run.json retains them.'
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportBundle.ps1')
$tables=@{
 'Profiles.csv'=$profiles.ToArray();'Licenses.csv'=$licenses.ToArray()
 'Groups.csv'=$groups.ToArray();'DirectoryRoles.csv'=$roles.ToArray();'Segments.csv'=$segments.ToArray()
}
$columns=@{
 'Profiles.csv'=@('UserId','DisplayName','UserPrincipalName','Mail','AccountEnabled','UserType')
 'Licenses.csv'=@('UserId','DisplayName','UserPrincipalName','AccountEnabled','UserType','SkuId','Product','Source','AssignedByGroup','State','Error','DisabledPlans','LastUpdated')
 'Groups.csv'=@('UserPrincipalName','GroupId','GroupName','Relationship','GroupTypes','MailEnabled','SecurityEnabled','DynamicRule','OnPremisesSyncEnabled','MetadataLimited')
 'DirectoryRoles.csv'=@('UserPrincipalName','AssignmentId','RoleDefinitionId','RoleName','PrincipalId','DirectoryScopeId','AppScopeId','Source')
 'Segments.csv'=@('User','Segment','Complete','Rows','Issue')
}
$manifest=[ordered]@{}
foreach ($property in $metadata.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
$manifest['Status']=if ($metadata.CollectedSegmentsComplete) {'CompletedWithinDeclaredScope'} else {'PartialCoverage'}
$manifest['FinishedUtc']=[datetime]::UtcNow.ToString('o')
$export=Export-ToolkitReportBundle -Tables $tables -Manifest $manifest -Columns $columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
if ($export.Status -eq 'Saved') {
 $paths.Profiles=Join-Path $export.ReportFolder 'Profiles.csv'
 $paths.Licenses=Join-Path $export.ReportFolder 'Licenses.csv'
 $paths.Groups=Join-Path $export.ReportFolder 'Groups.csv'
 $paths.DirectoryRoles=Join-Path $export.ReportFolder 'DirectoryRoles.csv'
 $paths.Segments=Join-Path $export.ReportFolder 'Segments.csv'
 $paths.Coverage=Join-Path $export.ReportFolder 'Run.json'
}
Write-Host ('Export status: '+$export.Status)
if ($PassThru) { [pscustomobject]@{Profiles=@($profiles.ToArray());Licenses=@($licenses.ToArray());Groups=@($groups.ToArray());DirectoryRoles=@($roles.ToArray());Metadata=$metadata;Paths=$paths;Segments=@($segments.ToArray());ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
