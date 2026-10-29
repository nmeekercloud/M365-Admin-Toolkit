# Read-only group inventory helpers. Dot-sourcing performs no network calls.
function ConvertTo-GLGroupRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Group)
    $types=@($Group['groupTypes'])
    $mail=$Group['mailEnabled']; $security=$Group['securityEnabled']
    $kind='Unknown'
    if ('Unified' -in $types) { $kind='Microsoft 365' }
    elseif ($mail -eq $false -and $security -eq $true) { $kind='Security' }
    elseif ($mail -eq $true -and $security -eq $true) { $kind='Mail-enabled security' }
    elseif ($mail -eq $true -and $security -eq $false) { $kind='Distribution' }
    $origin='Cloud / not currently synced'
    if ($Group['onPremisesSyncEnabled'] -eq $true) { $origin='On-premises synced' }
    elseif ($Group['onPremisesLastSyncDateTime']) { $origin='Previously synced' }
    $role='Unknown'
    if ($Group['isAssignableToRole'] -eq $true) { $role='Yes' }
    elseif ($Group['isAssignableToRole'] -eq $false) { $role='No' }
    [pscustomobject]@{
        Id=[string]$Group['id']
        DisplayName=[string]$Group['displayName']
        Mail=[string]$Group['mail']
        GroupType=$kind
        MembershipMode=$(if ('DynamicMembership' -in $types) {'Dynamic'} else {'Assigned'})
        Origin=$origin
        TeamsEnabled=('Team' -in @($Group['resourceProvisioningOptions']))
        RoleAssignable=$role
        Visibility=[string]$Group['visibility']
        Description=[string]$Group['description']
        CreatedDateTime=[string]$Group['createdDateTime']
        LastSyncDateTime=[string]$Group['onPremisesLastSyncDateTime']
        MembershipRule=[string]$Group['membershipRule']
        RuleProcessingState=[string]$Group['membershipRuleProcessingState']
    }
}
function Get-GLInventory {
    [CmdletBinding()]
    param()
    $uri='https://graph.microsoft.com/v1.0/groups?$select=id,displayName,description,mail,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,onPremisesLastSyncDateTime,isAssignableToRole,visibility,resourceProvisioningOptions,createdDateTime,membershipRule,membershipRuleProcessingState&$top=999'
    $pages=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows=[Collections.Generic.List[object]]::new()
    while ($uri) {
        $parsed=$null
        if (-not [uri]::TryCreate($uri,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or $parsed.AbsolutePath -ne '/v1.0/groups' -or $parsed.UserInfo -or $parsed.Fragment) {
            throw 'Unexpected Graph pagination URL. No partial inventory will be returned.'
        }
        if (-not $pages.Add($uri)) { throw 'Repeated pagination URL. No partial inventory will be returned.' }
        $page=Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable -ErrorAction Stop
        if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value') -or $null -eq $page['value']) { throw 'Invalid group-list response; no partial inventory returned.' }
        foreach ($group in @($page['value'])) {
            if ($group -isnot [System.Collections.IDictionary]) { throw 'Invalid group object in response.' }
            $id=[guid]::Empty
            if (-not [guid]::TryParse([string]$group['id'],[ref]$id)) { throw 'Group response missing a valid immutable object ID.' }
            if ($ids.Add($id.ToString('D'))) { $rows.Add((ConvertTo-GLGroupRow -Group $group)) }
        }
        $uri=[string]$page['@odata.nextLink']
    }
    $rows.ToArray()
}
function Select-GLRows {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Rows=@(),[string]$Search='',
          [ValidateSet('All','Microsoft365','Security','MailEnabledSecurity','Distribution')][string]$GroupType='All',
          [ValidateSet('All','Assigned','Dynamic')][string]$Membership='All')
    $typeLabel=switch ($GroupType) {
        'Microsoft365' {'Microsoft 365'}
        'Security' {'Security'}
        'MailEnabledSecurity' {'Mail-enabled security'}
        'Distribution' {'Distribution'}
        default {''}
    }
    foreach ($row in $Rows) {
        if ($typeLabel -and $row.GroupType -ne $typeLabel) { continue }
        if ($Membership -ne 'All' -and $row.MembershipMode -ne $Membership) { continue }
        if ($Search) {
            $matched=$false
            foreach ($value in @($row.DisplayName,$row.Mail,$row.Id,$row.Description)) {
                if (([string]$value).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched=$true; break }
            }
            if (-not $matched) { continue }
        }
        $row
    }
}
function ConvertTo-GLCsvSafeRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Row)
    $values=[ordered]@{}
    foreach ($property in $Row.PSObject.Properties) {
        $value=$property.Value
        if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
        $values[$property.Name]=$value
    }
    [pscustomobject]$values
}
