#Requires -Version 7.4
<#
.SYNOPSIS
Move OneDrive content to SharePoint using the supplied CreateCopyJobs engine.
.DESCRIPTION
Read-only PlanOnly; workflow exact-argument approval; source inventory recheck;
server-side move; destination path/size and source-removal checks; owned grant cleanup.
This is a test integration, not a full fidelity/compliance backup guarantee.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [string]$UserPrincipalName,
    [switch]$PlanOnly,[switch]$PassThru,[object]$WorkflowApproval,
    [string]$SourceUrl,[string]$SourceLibraryId,[string]$SourceRoot,
    [string]$SourceFingerprint,[string]$DestinationSiteUrl,
    [bool]$CreateSite=$false,[string]$SiteTitle,
    [string]$DestinationLibraryId,[string]$DestinationLibraryRoot,
    [string]$DestinationFolder,[int]$ConflictBehavior=0,
    [string[]]$AccessUsers=@(),[bool]$GrantSourceAdmin=$false,
    [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive
)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ([bool]$ExportDirectory -xor [bool]$ReportName)) {throw 'Noninteractive export requires both ExportDirectory and ReportName.'}
if ($NoInteractive -and ($PlanOnly -or -not $UserPrincipalName -or -not $SourceFingerprint -or -not $SourceUrl -or -not $SourceLibraryId -or -not $SourceRoot -or -not $DestinationSiteUrl -or -not $DestinationLibraryId -or -not $DestinationLibraryRoot)) {throw 'NoInteractive archive execution requires a complete existing plan; interactive planning is not supported in NoInteractive mode.'}
if ($NoInteractive -and -not $WorkflowApproval -and -not $WhatIfPreference) {throw 'Unattended archive execution requires existing WorkflowApproval; use interactive execution for typed MOVE/OVERWRITE approval.'}
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveOutput.ps1')
. (Join-Path $PSScriptRoot '../Users/UserManagement.Common.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.UserWorkflows.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OffboardingApproval.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveArchive.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveArchive.Destination.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveArchive.SourceLibrary.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveArchive.AccountGuard.ps1')
. (Join-Path $PSScriptRoot '../../Tools/Toolkit.OneDriveArchive.Engine.ps1')
if (-not (Get-Module M365Toolkit.Core)) { Import-Module (Join-Path $PSScriptRoot '../../Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop }
$null=Assert-M365TaskAccess -AccessMode Changes -TaskId 'onedrive.backup-onedrive'
$null=Assert-M365Connection -Service @('Graph','SharePoint') -GraphScopes @('User.Read.All','Sites.Read.All') -TaskName 'Move OneDrive archive' -TaskId 'onedrive.backup-onedrive'
$tenant=Get-M365TenantInfo
if (-not $UserPrincipalName) { $UserPrincipalName=([string](Read-Host 'User UPN (Enter cancels)')).Trim() }
if (-not $UserPrincipalName) { return }
$user=Get-UMUser $UserPrincipalName
Assert-ODArchiveMember -User $user -Tenant $tenant
$admin=Get-M365SharePointConnection
$root=([string]$tenant.SharePointAdminUrl).Replace('-admin.sharepoint.com','.sharepoint.com').TrimEnd('/')
if ($ConflictBehavior -notin @(0,1)) { throw 'This first integration supports fail or overwrite/merge, not rename; rename cannot yet be matched reliably during destination verification.' }
if ($PlanOnly -and $WorkflowApproval) { throw 'Execution approval cannot be used for planning.' }
if ($PlanOnly) {
    try {
        $profile=Get-PnPUserProfileProperty -Account $user['userPrincipalName'] -Connection $admin -ErrorAction Stop
        $SourceUrl=([string]$profile.PersonalUrl).TrimEnd('/')
        if (-not $SourceUrl) { throw 'OneDrive URL was not returned. This integration does not provision an uncreated OneDrive.' }
        Test-ODSameTenantUrl -Url $SourceUrl -Root $root -OneDrive
        $source=Get-M365SharePointConnection -Url $SourceUrl
        try { $sourceUser=Get-ODCurrentUser -Connection $source -ExpectedAccount $tenant.Account }
        catch { throw ('Cannot establish the existing source access/admin state. No permission changes have been made. To avoid removing pre-existing permissions, this test build requires source site access before planning. '+$_.Exception.Message) }
        $GrantSourceAdmin=-not $sourceUser.IsAdmin
        $sourceList=@(Resolve-ODArchiveSourceLibrary -Connection $source -OneDriveUrl $SourceUrl -LibraryId $SourceLibraryId)
        if ($sourceList.Count -ne 1) { throw 'Source library selection did not return exactly one library. No move submitted.' }
        $SourceLibraryId=[string]$sourceList[0].Id
        $SourceRoot=[string]$sourceList[0].RootFolder.ServerRelativeUrl
        $inventory=@(Get-ODInventory -Connection $source -LibraryId $SourceLibraryId -Root $SourceRoot)
        $SourceFingerprint=Get-ODFingerprint -Inventory $inventory
        Write-Host '[1] Existing SharePoint site  [2] Create new archive site' -ForegroundColor Cyan
        $mode=Read-ODValue 'Destination selection'
        if ($mode -notin @('1','2')) { throw 'Choose 1 or 2. No changes made.' }
        $CreateSite=$mode -eq '2'
        if ($CreateSite) {
            $SiteTitle=Read-ODValue 'New site title'
            $slug=ConvertTo-ODArchiveSiteSlug -Title $SiteTitle
            $DestinationSiteUrl=$root+'/sites/'+$slug
            Write-Host ('Generated new site address: '+$DestinationSiteUrl) -ForegroundColor Cyan
            $existing=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop | Where-Object { ([string]$_.Url).TrimEnd('/') -ieq $DestinationSiteUrl })
            if ($existing.Count) { throw 'Generated destination URL already exists, possibly from an earlier failed run. Replan using Existing SharePoint site; no site will be silently reused or duplicated.' }
            $DestinationLibraryId='DEFAULT'
            $DestinationLibraryRoot='(new site default document library)'
        } else {
            $SiteTitle=''
            $DestinationSiteUrl=(Read-ODValue 'Destination SharePoint site URL').TrimEnd('/')
            Test-ODSameTenantUrl -Url $DestinationSiteUrl -Root $root
            $dest=Get-M365SharePointConnection -Url $DestinationSiteUrl
            $null=Get-PnPWeb -Connection $dest -ErrorAction Stop
            $libraries=@(Get-PnPList -Includes RootFolder,BaseTemplate,Hidden -Connection $dest -ErrorAction Stop | Where-Object { $_.BaseTemplate -eq 101 -and -not $_.Hidden } | Sort-Object Title)
            for ($i=0;$i -lt $libraries.Count;$i++) { Write-Host ('[{0}] {1}' -f ($i+1),$libraries[$i].Title) }
            $choice=Read-ODValue 'Destination library number'
            $n=0
            if (-not [int]::TryParse($choice,[ref]$n) -or $n -lt 1 -or $n -gt $libraries.Count) { throw 'Invalid destination library.' }
            $DestinationLibraryId=[string]$libraries[$n-1].Id
            $DestinationLibraryRoot=[string]$libraries[$n-1].RootFolder.ServerRelativeUrl
        }
        $DestinationFolder=([string](Read-Host 'Archive folder inside library (Enter uses library root)')).Trim().Trim('/')
        if ($DestinationFolder -and ($DestinationFolder -match '[\\:#%?*"<>|]' -or @($DestinationFolder -split '/' | Where-Object { $_ -in @('.','..') -or -not $_ }).Count -gt 0)) { throw 'Invalid or ambiguous folder path. Use plain folder names separated by /.' }
        Write-Host '[1] Fail on conflicts (default)  [2] Overwrite files / merge folders'
        $conflict=([string](Read-Host 'Conflict handling [1]')).Trim()
        if ($conflict -and $conflict -notin @('1','2')) { throw 'Invalid conflict selection.' }
        $ConflictBehavior=0; if ($conflict -eq '2') { $ConflictBehavior=1 }
        $AccessUsers=@(([string](Read-Host 'Grant destination SITE Edit access to these UPNs (comma separated; Enter skips)')) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        foreach ($access in $AccessUsers) { $null=Get-UMUser $access }
        $settings=@{
            SourceUrl=$SourceUrl;SourceLibraryId=$SourceLibraryId;SourceRoot=$SourceRoot
            SourceFingerprint=$SourceFingerprint;DestinationSiteUrl=$DestinationSiteUrl
            CreateSite=$CreateSite;SiteTitle=$SiteTitle;DestinationLibraryId=$DestinationLibraryId
            DestinationLibraryRoot=$DestinationLibraryRoot;DestinationFolder=$DestinationFolder
            ConflictBehavior=$ConflictBehavior;AccessUsers=[string[]]$AccessUsers;GrantSourceAdmin=$GrantSourceAdmin
        }
        $files=@($inventory | Where-Object { -not $_.Folder })
        $summary=('MOVE OneDrive: '+$SourceUrl+' -> '+$DestinationSiteUrl+' / '+$DestinationLibraryRoot+' / '+$DestinationFolder+'. Files: '+$files.Count+'. Conflict: '+$(if ($ConflictBehavior -eq 1) {'OVERWRITE / MERGE'} else {'FAIL'})+'. Source content leaves OneDrive. Shortcuts/unverified items stop subsequent workflow steps. Version history is requested, not independently certified. Temporary admin grant if listed will be removed only if added by this run.')
        [pscustomobject]@{PlanKind='OffboardingArchive';Settings=$settings;NoOp=($inventory.Count -eq 0);Summary=$summary}
        return
    } catch [OperationCanceledException] { Write-Host 'Archive planning cancelled.'; return }
}
# Standalone calls build exactly the same plan before confirming.
if (-not $SourceFingerprint) {
    if ($WorkflowApproval) { throw 'Approved archive settings missing; rebuild plan.' }
    $plan=@(& $PSCommandPath -UserPrincipalName $user['id'] -PlanOnly)
    if ($plan.Count -ne 1) { return }
    $args=@{UserPrincipalName=$user['id'];WhatIf=[bool]$WhatIfPreference;PassThru=[bool]$PassThru;ExportDirectory=$ExportDirectory;ReportName=$ReportName;NoInteractive=[bool]$NoInteractive}
    foreach ($key in $plan[0].Settings.Keys) { $args[$key]=$plan[0].Settings[$key] }
    & $PSCommandPath @args
    return
}
$approved=Test-WF6DApproval -Approval $WorkflowApproval -Tenant $tenant -User $user -Action ArchiveOneDrive -Bound $PSBoundParameters
if ($WorkflowApproval -and -not $approved) { throw 'Invalid archive workflow approval.' }
Test-ODSameTenantUrl -Url $SourceUrl -Root $root -OneDrive
Test-ODSameTenantUrl -Url $DestinationSiteUrl -Root $root
if (-not $approved -and -not $WhatIfPreference) {
    Write-Host ('MOVE '+$SourceUrl+' -> '+$DestinationSiteUrl+' / '+$DestinationFolder) -ForegroundColor Yellow
    Write-Host ('Conflict: '+$(if ($ConflictBehavior -eq 1) {'OVERWRITE / MERGE'} else {'FAIL'}))
    Write-Host 'Source content is removed by the move. Temporary grants/creation/access changes follow the supplied plan.'
    $word=if ($ConflictBehavior -eq 1) {'OVERWRITE'} else {'MOVE'}
    if (([string](Read-Host ('Type '+$word+' to execute; Enter cancels'))).Trim() -cne $word) { return }
    $ConfirmPreference='None'
}
if ($approved) { $ConfirmPreference='None' }
if (-not $PSCmdlet.ShouldProcess($user['userPrincipalName'],'Move OneDrive content to approved SharePoint destination')) {
    Complete-OD18ArchiveStep 'Move OneDrive archive' $user['userPrincipalName'] Planned -PassThru:$PassThru
    return
}
$script:ODMovedOperations=0
$script:ODMoveFailures=[Collections.Generic.List[object]]::new()
$script:ODSkippedShortcuts=[Collections.Generic.List[object]]::new()
$script:ODJobUncertain=$false
$script:ODActiveJob=$null
$source=$null; $grantUncertain=$false; $addedAdmin=$false; $cleanupFailed=$false; $operationError=$null; $status='Failed'; $detail=''
try {
    $source=Get-M365SharePointConnection -Url $SourceUrl
    $profile=Get-PnPUserProfileProperty -Account $user['userPrincipalName'] -Connection $admin -ErrorAction Stop
    if (([string]$profile.PersonalUrl).TrimEnd('/') -ine $SourceUrl.TrimEnd('/')) { throw 'Source OneDrive no longer matches selected user.' }
    $sourceUser=Get-ODCurrentUser -Connection $source -ExpectedAccount $tenant.Account
    $sourceList=Get-ODLibrary -Connection $source -Id $SourceLibraryId
    if ([string]$sourceList.RootFolder.ServerRelativeUrl -cne $SourceRoot) { throw 'Source library root changed.' }
    $before=@(Get-ODInventory -Connection $source -LibraryId $SourceLibraryId -Root $SourceRoot)
    if ((Get-ODFingerprint -Inventory $before) -cne $SourceFingerprint) { throw 'OneDrive contents changed since planning. Rebuild the plan.' }
    if (-not $sourceUser.IsAdmin) {
        if (-not $GrantSourceAdmin) { throw 'Source admin state changed; new approval required.' }
        $grantUncertain=$true
        Set-PnPTenantSite -Identity $SourceUrl -Owners $tenant.Account -Connection $admin -ErrorAction Stop
        $addedAdmin=$true
        $grantUncertain=$false
        $source=Get-M365SharePointConnection -Url $SourceUrl
        $current=Get-ODCurrentUser -Connection $source -ExpectedAccount $tenant.Account
        if (-not $current.IsAdmin) { throw 'Source admin grant not yet verified. No move submitted.' }
    }
    if ($CreateSite) {
        $existing=@(Get-PnPTenantSite -Connection $admin -ErrorAction Stop | Where-Object { ([string]$_.Url).TrimEnd('/') -ieq $DestinationSiteUrl })
        if ($existing.Count) { throw 'Destination appeared after planning; do not reuse without a new plan.' }
        $null=New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $SiteTitle -Url $DestinationSiteUrl -Owner $tenant.Account -Connection $admin -ErrorAction Stop
        $dest=$null
        for ($attempt=0;$attempt -lt 60;$attempt++) {
            try { $dest=Get-M365SharePointConnection -Url $DestinationSiteUrl; $null=Get-PnPWeb -Connection $dest -ErrorAction Stop; break }
            catch { $dest=$null; Start-Sleep -Seconds 10 }
        }
        if (-not $dest) { throw 'Site provisioning could not be verified. No move submitted.' }
        $destList=Resolve-ODArchiveNewDefaultLibrary -Connection $dest -ExpectedSiteUrl $DestinationSiteUrl
    } else {
        $dest=Get-M365SharePointConnection -Url $DestinationSiteUrl
        $destList=Get-ODLibrary -Connection $dest -Id $DestinationLibraryId
        if ([string]$destList.RootFolder.ServerRelativeUrl -cne $DestinationLibraryRoot) { throw 'Destination library root changed.' }
    }
    $destRoot=[string]$destList.RootFolder.ServerRelativeUrl
    $targetRoot=$destRoot.TrimEnd('/')
    if ($DestinationFolder) {
        $targetRoot+='/'+$DestinationFolder
        $web=Get-PnPWeb -Includes ServerRelativeUrl -Connection $dest -ErrorAction Stop
        $siteRelative=$targetRoot.Substring(([string]$web.ServerRelativeUrl).TrimEnd('/').Length).TrimStart('/')
        $null=Resolve-PnPFolder -SiteRelativePath $siteRelative -Connection $dest -ErrorAction Stop
    }
    if ($AccessUsers.Count) {
        $members=Get-PnPGroup -AssociatedMemberGroup -Connection $dest -ErrorAction Stop
        foreach ($access in $AccessUsers) { $null=Add-PnPGroupMember -LoginName $access -Group $members -Connection $dest -ErrorAction Stop }
    }
    $null=Save-UMJson -Value @{Source=$SourceUrl;Destination=$DestinationSiteUrl;Folder=$targetRoot;Inventory=$before} -Label 'OneDriveArchive-Before'
    $rootFolder=Get-PnPFolder -Url $SourceRoot -Connection $source -ErrorAction Stop
    $files=@(Get-PnPFolderItem -Identity $rootFolder -ItemType File -Connection $source -ErrorAction Stop)
    $folders=@(Get-PnPFolderItem -Identity $rootFolder -ItemType Folder -Connection $source -ErrorAction Stop | Where-Object { $_.Name -ne 'Forms' })
    $sourceAuthority=([uri]$SourceUrl).GetLeftPart([UriPartial]::Authority)
    $destAuthority=([uri]$DestinationSiteUrl).GetLeftPart([UriPartial]::Authority)
    foreach ($file in $files) {
        try {
            OD-Move-SingleSourceItem -Type File -Name $file.Name -SourceServerRelativeUrl $file.ServerRelativeUrl -DestinationParentServerRelativeUrl $targetRoot -ConflictBehavior $ConflictBehavior -SourceAuthority $sourceAuthority -DestinationAuthority $destAuthority -SourceConnection $source
        } catch { $null=OD-Register-MoveError -Type File -Name $file.Name -SourceUrl $file.ServerRelativeUrl -ErrorMessage $_.Exception.Message }
        if ($script:ODJobUncertain) { throw 'Move job outcome uncertain. Do not resubmit automatically; retain source access for investigation.' }
    }
    foreach ($folder in $folders) {
        OD-Move-FolderWithMerge -SourceFolder $folder -SourceParentServerRelativeUrl $SourceRoot -DestinationParentServerRelativeUrl $targetRoot -ConflictBehavior $ConflictBehavior -SourceAuthority $sourceAuthority -DestinationAuthority $destAuthority -SourceConnection $source -DestinationConnection $dest
        if ($script:ODJobUncertain) { throw 'Move job outcome uncertain. Do not resubmit automatically; retain source access for investigation.' }
    }
    $remaining=@(Get-ODInventory -Connection $source -LibraryId $SourceLibraryId -Root $SourceRoot)
    $after=@(Get-ODInventory -Connection $dest -LibraryId ([string]$destList.Id) -Root $targetRoot)
    $map=@{}
    foreach ($row in $after) { $map[$row.Relative.ToLowerInvariant()]=$row }
    $missing=@()
    foreach ($row in $before) {
        $key=$row.Relative.ToLowerInvariant()
        if (-not $map.ContainsKey($key) -or $map[$key].Folder -ne $row.Folder -or (-not $row.Folder -and $map[$key].Bytes -ne $row.Bytes)) { $missing+=,$row.Relative }
    }
    $report=@{MovedJobs=$script:ODMovedOperations;Skipped=@($script:ODSkippedShortcuts);Failures=@($script:ODMoveFailures);Remaining=$remaining;DestinationUnverified=$missing;Verification='Relative paths, item types, file sizes, source removal; not hashes/version/compliance certification'}
    $null=Save-UMJson -Value $report -Label 'OneDriveArchive-Result'
    if ($script:ODMoveFailures.Count -or $remaining.Count -or $missing.Count -or $script:ODSkippedShortcuts.Count) {
        $status='Partial'; $detail='Move incomplete or exclusions remain. Later workflow steps stopped. Review archive result report.'
    } else { $status='Success'; $detail='Move jobs completed; destination paths/sizes and empty source inventory verified. Version/permission/compliance fidelity is not independently certified.' }
} catch { $operationError=$_; $status='Failed'; $detail=$_.Exception.Message }
finally {
    if ($grantUncertain) { $cleanupFailed=$true; Write-Warning 'Source grant request outcome uncertain; administrator assignment must be inspected manually. No automatic removal of an unverified grant.' }
    if ($addedAdmin) {
        if ($script:ODJobUncertain) {
            $cleanupFailed=$true
            Write-Warning 'Temporary source admin access retained: move job may still be active. Cleanup is pending manual investigation.'
        } else {
            try {
                Remove-PnPSiteCollectionAdmin -Owners $tenant.Account -Connection $source -ErrorAction Stop
                $current=Get-ODCurrentUser -Connection $source -ExpectedAccount $tenant.Account
                if ($current.IsAdmin) { throw 'Admin removal not yet reflected.' }
            } catch { $cleanupFailed=$true; Write-Warning ('Temporary admin cleanup unverified: '+$_.Exception.Message) }
        }
    }
}
if ($cleanupFailed -and $status -eq 'Success') { $status='Partial' }
if ($cleanupFailed) { $detail+=' Temporary admin cleanup pending/unverified.' }
Complete-OD18ArchiveStep 'Move OneDrive archive' $user['userPrincipalName'] $status -Detail $detail -PassThru:$PassThru
if ($operationError -and -not $PassThru) { throw $operationError }
