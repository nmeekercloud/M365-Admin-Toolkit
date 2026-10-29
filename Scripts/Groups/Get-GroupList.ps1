#Requires -Version 7.4
<#
.SYNOPSIS
List/search Graph groups and identify type, membership and synchronization state.
.DESCRIPTION
Read-only Microsoft Graph requests with complete pagination. Dynamic Exchange
 distribution groups are not returned by Graph. No member/owner changes.
.PARAMETER Search
Literal case-insensitive text matched locally against name, mail, ID and description.
.PARAMETER NoInteractive
Do not show prompts. Displays results; PassThru additionally returns raw rows. Export requires an explicit directory and report name.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Search='',
    [ValidateSet('All','Microsoft365','Security','MailEnabledSecurity','Distribution')][string]$GroupType='All',
    [ValidateSet('All','Assigned','Dynamic')][string]$Membership='All',
    [string]$ExportDirectory,[string]$ReportName,[switch]$NoInteractive,[switch]$PassThru,[switch]$ExportCsv
)
$ErrorActionPreference='Stop'
if ($NoInteractive -and ($ExportCsv -or $ExportDirectory -or $ReportName) -and -not ($ExportDirectory -and $ReportName)) { throw 'Noninteractive export requires both ExportDirectory and ReportName; ExportCsv alone no longer chooses an automatic path.' }
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Get-Module M365Toolkit.Core)) {
    Import-Module (Join-Path $root 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -Global -ErrorAction Stop
}
. (Join-Path $root 'Tools/Toolkit.GroupList.Helpers.ps1')
$null=Assert-M365TaskAccess -AccessMode ReadOnly -TaskId 'groups.get-grouplist'
$tenant=Assert-M365Connection -Service Graph -GraphScopes @('Group.Read.All') -TaskId 'groups.get-grouplist' -TaskName 'List groups and group types'
$context=Get-MgContext -ErrorAction Stop
if ([string]$context.Environment -ne 'Global') { throw 'This first implementation targets the global Graph endpoint. Other cloud endpoints need a separate reviewed update.' }
if (-not $NoInteractive -and -not $PSBoundParameters.ContainsKey('Search')) {
    $Search=([string](Read-Host 'Search group name/email (Enter lists all)')).Trim()
}
Write-Host 'Reading groups...' -ForegroundColor Cyan
$inventory=@(Get-GLInventory | Sort-Object DisplayName,Id)
Write-M365Log -Message ('Group inventory read: '+$inventory.Count+' groups.') -Level Info -Quiet
$initialExportRequested=[bool]$ExportCsv -or [bool]$ExportDirectory -or [bool]$ReportName
while ($true) {
    $filtered=@(Select-GLRows -Rows $inventory -Search $Search -GroupType $GroupType -Membership $Membership)
    Write-Host ''
    Write-Host ('Tenant: '+$tenant.TenantName+' | Matches: '+$filtered.Count+' / '+$inventory.Count) -ForegroundColor Cyan
    Write-Host 'Graph inventory excludes Exchange dynamic distribution groups.' -ForegroundColor DarkGray
    if ($filtered.Count) {
        $display=@(for ($i=0;$i -lt $filtered.Count;$i++) {
            [pscustomobject]@{Number=($i+1);Name=$filtered[$i].DisplayName;Email=$filtered[$i].Mail;Type=$filtered[$i].GroupType;Membership=$filtered[$i].MembershipMode;Origin=$filtered[$i].Origin}
        })
        Show-M365Results -InputObject $display -Title 'Matching Graph groups' -NoPaging:$NoInteractive
    } else { Write-Host 'No matching groups.' -ForegroundColor Yellow }
    $exportRequested=$initialExportRequested
    $initialExportRequested=$false
    $action=''
    if (-not $NoInteractive) {
        Write-Host '[number] Details  [S] Search  [F] Filters  [E] Export matching rows  [0] Back'
        $action=([string](Read-Host 'Select [0]')).Trim()
        if ($action -ieq 'E') { $exportRequested=$true }
    }
    if ($exportRequested) {
        if ($WhatIfPreference) { Write-Host 'WhatIf: result export skipped; no report path created.' }
        elseif ($PSCmdlet.ShouldProcess('Chosen filtered group-inventory bundle','Optionally export group inventory')) {
            . (Join-Path $root 'Tools/Toolkit.ReportBundle.ps1')
            $manifest=[ordered]@{
                TaskId='groups.get-grouplist';TenantId=$tenant.TenantId
                Status='CompletedWithinDeclaredScope';FinishedUtc=[datetime]::UtcNow.ToString('o')
                InventoryRows=$inventory.Count;MatchingRows=$filtered.Count
                Search=$Search;GroupTypeFilter=$GroupType;MembershipFilter=$Membership
                Scope='Graph group inventory filtered locally; no member or effective-access enumeration'
                Warnings=@('Exchange dynamic distribution groups are excluded.','Group metadata is not an effective-access inventory.','Not a transactionally consistent tenant snapshot.')
            }
            $columns=@('Id','DisplayName','Mail','GroupType','MembershipMode','Origin','TeamsEnabled','RoleAssignable','Visibility','Description','CreatedDateTime','LastSyncDateTime','MembershipRule','RuleProcessingState')
            $exportResult=Export-ToolkitReportBundle -Tables @{'Groups.csv'=$filtered} -Manifest $manifest -Columns @{'Groups.csv'=$columns} -OutputDirectory $ExportDirectory -BundleName $ReportName -NoInteractive:$NoInteractive
            Write-Host ('Export status: '+$exportResult.Status)
        }
    }
    if ($NoInteractive -or -not $action -or $action -eq '0') { break }
    switch -Regex ($action) {
        '^(?i)S$' { $Search=([string](Read-Host 'Search text (Enter lists all within filters)')).Trim(); continue }
        '^(?i)F$' {
            Write-Host '[0] All  [1] Microsoft 365  [2] Security  [3] Mail-enabled security  [4] Distribution'
            $choice=([string](Read-Host 'Group type [0]')).Trim()
            $types=@{'0'='All';'1'='Microsoft365';'2'='Security';'3'='MailEnabledSecurity';'4'='Distribution'}
            if (-not $choice) { $choice='0' }
            if (-not $types.ContainsKey($choice)) { Write-Host 'Invalid type; filters unchanged.' -ForegroundColor Yellow; continue }
            $membershipChoice=([string](Read-Host 'Membership: A=All, D=Dynamic, S=Assigned [A]')).Trim()
            $modes=@{'A'='All';'D'='Dynamic';'S'='Assigned'}
            if (-not $membershipChoice) { $membershipChoice='A' }
            if (-not $modes.ContainsKey($membershipChoice.ToUpperInvariant())) { Write-Host 'Invalid membership mode; filters unchanged.' -ForegroundColor Yellow; continue }
            $GroupType=$types[$choice]; $Membership=$modes[$membershipChoice.ToUpperInvariant()]
            continue
        }
        '^(?i)E$' { continue }
        '^\d+$' {
            $number=0
            if ([int]::TryParse($action,[ref]$number) -and $number -ge 1 -and $number -le $filtered.Count) {
                $filtered[$number-1] | Format-List | Out-Host
                Read-Host 'Press Enter to return to the list' | Out-Null
            } else { Write-Host 'Choose a number from the displayed list.' -ForegroundColor Yellow }
        }
        default { Write-Host 'Choose a displayed number, S, F, E, or 0.' -ForegroundColor Yellow }
    }
}
if ($PassThru) { $filtered }
