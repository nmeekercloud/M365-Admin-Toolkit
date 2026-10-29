#Requires -Version 7.4
<#
.SYNOPSIS
Export all current directory users, regardless of license or account status.
.DESCRIPTION
Includes members, guests, enabled and disabled accounts, and users without mail.
No license lookup or filtering. Not deleted users, groups, or contact objects.
Services: Graph. Scope: User.Read.All. Read-only. Display first; optional named export bundle.
#>
[CmdletBinding()]
param([string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportsAuditing.ps1')
$csv=$null; $coverage=$null
Initialize-R3Task @('User.Read.All')
Write-Host 'Exporting ALL current directory users: members and guests, enabled and disabled, licensed and unlicensed.' -ForegroundColor Cyan
Write-Host 'Users without an email address are included. No license lookup or filtering is performed.'
$users=Get-R3Users -Select 'id,displayName,givenName,surname,mail,userPrincipalName,jobTitle,department,companyName,officeLocation,businessPhones,mobilePhone,accountEnabled,userType'
$rows=@(foreach ($user in $users.Rows) {
    [pscustomobject]@{
        DisplayName=[string](Get-R3Field $user 'displayName')
        GivenName=[string](Get-R3Field $user 'givenName')
        Surname=[string](Get-R3Field $user 'surname')
        Mail=[string](Get-R3Field $user 'mail')
        UserPrincipalName=[string](Get-R3Field $user 'userPrincipalName')
        JobTitle=[string](Get-R3Field $user 'jobTitle')
        Department=[string](Get-R3Field $user 'department')
        CompanyName=[string](Get-R3Field $user 'companyName')
        OfficeLocation=[string](Get-R3Field $user 'officeLocation')
        BusinessPhones=(@(Get-R3Field $user 'businessPhones' @()) -join '; ')
        MobilePhone=[string](Get-R3Field $user 'mobilePhone')
        AccountEnabled=Get-R3Field $user 'accountEnabled'
        UserType=[string](Get-R3Field $user 'userType')
        UserId=[string](Get-R3Field $user 'id')
    }
})
$rows=@($rows | Sort-Object DisplayName,UserPrincipalName)
$columns=@('DisplayName','GivenName','Surname','Mail','UserPrincipalName','JobTitle','Department','CompanyName','OfficeLocation','BusinessPhones','MobilePhone','AccountEnabled','UserType','UserId')
$metadata=[pscustomobject]@{
    Task='AllUsersExport'
    Complete=$users.Complete
    Issue=$users.Issue
    UsersRead=$users.Rows.Count
    RowsExported=$rows.Count
    Scope='All current directory user objects; no account-status, user-type, mail, or license filtering'
    Limitations='Not deleted users, organizational contact objects, groups, mailbox permissions, or a license report. Mail remains blank when unavailable; UPN is not substituted for email.'
}
Show-M365Results -InputObject @($rows | Select-Object DisplayName,UserPrincipalName,Mail,AccountEnabled,UserType) -Title 'All current directory users' -NoPaging:$NoInteractive
$metadata | Format-List | Out-Host
Write-Host "Users read: $($users.Rows.Count); report rows: $($rows.Count). Viewing does not limit exported or returned rows."
if (-not $users.Complete) { Write-Warning ('INCOMPLETE user retrieval; not a complete tenant list. Issue: '+$users.Issue) }
elseif ($rows.Count -eq 0) { Write-Warning 'The completed query returned zero current users. Verify the connected tenant.' }
else { Write-Host 'All Users retrieval completed successfully.' -ForegroundColor Green }
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.ReportBundle.ps1')
$manifest=[ordered]@{}
foreach ($property in $metadata.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
$manifest['Status']=if ($users.Complete) {'CompletedWithinDeclaredScope'} else {'PartialCoverage'}
$manifest['FinishedUtc']=[datetime]::UtcNow.ToString('o')
$export=Export-ToolkitReportBundle -Tables @{'AllUsers.csv'=$rows} -Manifest $manifest -Columns @{'AllUsers.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
if ($export.Status -eq 'Saved') {
 $csv=Join-Path $export.ReportFolder 'AllUsers.csv'
 $coverage=Join-Path $export.ReportFolder 'Run.json'
}
Write-Host ('Export status: '+$export.Status)
if ($PassThru) { [pscustomobject]@{Rows=$rows;Metadata=$metadata;Csv=$csv;Coverage=$coverage;ReportFolder=$export.ReportFolder;ExportStatus=$export.Status;ExportError=$export.Error;Manifest=[pscustomobject]$manifest} }
