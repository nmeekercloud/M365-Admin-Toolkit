#Requires -Version 7.4
<#
.SYNOPSIS
Report tenant license inventory and per-user license assignment sources.
.DESCRIPTION
Read-only Graph report. Technical SKU names; no cost estimate. Assignment-state
rows distinguish direct, group and unknown sources without assuming missing data.
.EXAMPLE
.\Get-LicenseReport.ps1 -UserPrincipalName user@contoso.com -IncludeUnlicensed
.NOTES
Services: Graph. Scopes: User.Read.All, LicenseAssignment.Read.All. Read-only.
#>
[CmdletBinding()]
param([string[]]$UserPrincipalName,[switch]$InventoryOnly,[switch]$IncludeUnlicensed,[string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportsAuditing.ps1')
if ($InventoryOnly -and @($UserPrincipalName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'InventoryOnly and UserPrincipalName cannot be combined.' }
if (-not $NoInteractive -and -not ($PSBoundParameters.ContainsKey('UserPrincipalName') -or $PSBoundParameters.ContainsKey('InventoryOnly') -or $PSBoundParameters.ContainsKey('IncludeUnlicensed') -or $PSBoundParameters.ContainsKey('PassThru'))) {
    while ($true) {
        $choice=([string](Read-Host '[1] Inventory only [2] Inventory + all user assignments [3] Inventory + selected users [0] Cancel')).Trim()
        if ($choice -eq '0' -or -not $choice) { return }
        if ($choice -eq '1') { $InventoryOnly=$true; break }
        if ($choice -eq '2') { break }
        if ($choice -eq '3') {
            $text=([string](Read-Host 'User UPNs, comma-separated (blank cancels)')).Trim()
            if (-not $text) { return }
            $UserPrincipalName=@($text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); break
        }
        Write-Warning 'Choose 1, 2, 3, or 0.'
    }
}
Initialize-R3Task @('User.Read.All','LicenseAssignment.Read.All')
Write-Host 'Read-only license inventory; product names are technical SKU identifiers, not price/cost data.'
$skus=Get-R3Collection 'https://graph.microsoft.com/v1.0/subscribedSkus'
$map=Get-R3SkuMap $skus.Rows
$inventory=@(foreach ($sku in $skus.Rows) {
    $units=Get-R3Field $sku 'prepaidUnits'
    $enabled=Get-R3Field $units 'enabled'; $used=Get-R3Field $sku 'consumedUnits'
    $applies=[string](Get-R3Field $sku 'appliesTo')
    $balance=if ($null -ne $enabled -and $null -ne $used -and $applies -eq 'User') { [int64]$enabled-[int64]$used } else {$null}
    [pscustomobject]@{Product=[string](Get-R3Field $sku 'skuPartNumber');SkuId=[string](Get-R3Field $sku 'skuId');AppliesTo=$applies;CapabilityStatus=[string](Get-R3Field $sku 'capabilityStatus');EnabledUnits=$enabled;ConsumedUnits=$used;EnabledMinusConsumed=$balance;WarningUnits=Get-R3Field $units 'warning';SuspendedUnits=Get-R3Field $units 'suspended';LockedOutUnits=Get-R3Field $units 'lockedOut'}
})
$assignments=[System.Collections.Generic.List[object]]::new()
$userResult=[pscustomobject]@{Rows=@();Complete=$true;Issue='Not requested'}
if (-not $InventoryOnly) {
    $userResult=Get-R3Users -UserPrincipalName $UserPrincipalName -Select 'id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses,licenseAssignmentStates'
    foreach ($user in $userResult.Rows) { foreach ($row in @(Get-R3LicenseRows $user $map -IncludeUnlicensed:$IncludeUnlicensed)) { $assignments.Add($row) } }
}
$paths=[ordered]@{}
$metadata=[pscustomobject]@{Task='LicenseReport';Complete=($skus.Complete -and $userResult.Complete);InventoryComplete=$skus.Complete;InventoryIssue=$skus.Issue;AssignmentsRequested=(-not $InventoryOnly);UsersComplete=$userResult.Complete;UserIssue=$userResult.Issue;SelectedUsers=$UserPrincipalName;UsersRead=$userResult.Rows.Count;AssignmentRows=$assignments.Count;IncludeUnlicensed=[bool]$IncludeUnlicensed;Limitations='SKU technical names; no pricing; balance is enabled minus consumed, not guaranteed assignability; one user/SKU can have multiple source-state rows; absence of assignment states means unknown source.'}
Show-M365Results -InputObject @($inventory | Select-Object Product,CapabilityStatus,EnabledUnits,ConsumedUnits,EnabledMinusConsumed) -Title 'Tenant license inventory' -NoPaging:$NoInteractive
if (-not $InventoryOnly) {
 Show-M365Results -InputObject @($assignments.ToArray() | Select-Object DisplayName,UserPrincipalName,Product,Source,State,Error) -Title 'User license assignments' -NoPaging:$NoInteractive
}
$metadata | Format-List | Out-Host
Write-Host "Users read: $($userResult.Rows.Count); assignment rows: $($assignments.Count); complete=$($metadata.Complete)"
if (-not $metadata.Complete) { Write-Warning 'Partial report: one or more reads failed. Inspect metadata; saved Run.json retains coverage issues.' }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportBundle.ps1')
$tables=@{'LicenseInventory.csv'=$inventory}
$columns=@{'LicenseInventory.csv'=@('Product','SkuId','AppliesTo','CapabilityStatus','EnabledUnits','ConsumedUnits','EnabledMinusConsumed','WarningUnits','SuspendedUnits','LockedOutUnits')}
if (-not $InventoryOnly) {
 $tables['LicenseAssignments.csv']=$assignments.ToArray()
 $columns['LicenseAssignments.csv']=@('UserId','DisplayName','UserPrincipalName','AccountEnabled','UserType','SkuId','Product','Source','AssignedByGroup','State','Error','DisabledPlans','LastUpdated')
}
$manifest=[ordered]@{}
foreach ($property in $metadata.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
$manifest['Status']=if ($metadata.Complete) {'CompletedWithinDeclaredScope'} else {'PartialCoverage'}
$manifest['FinishedUtc']=[datetime]::UtcNow.ToString('o')
$export=Export-ToolkitReportBundle -Tables $tables -Manifest $manifest -Columns $columns -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
if ($export.Status -eq 'Saved') {
 $paths.Inventory=Join-Path $export.ReportFolder 'LicenseInventory.csv'
 if (-not $InventoryOnly) { $paths.Assignments=Join-Path $export.ReportFolder 'LicenseAssignments.csv' }
 $paths.Coverage=Join-Path $export.ReportFolder 'Run.json'
}
Write-Host ('Export status: '+$export.Status)
if ($PassThru) { [pscustomobject]@{Inventory=$inventory;Assignments=@($assignments.ToArray());Metadata=$metadata;Paths=$paths;ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
