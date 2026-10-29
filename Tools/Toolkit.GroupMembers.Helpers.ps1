# Group members: definitions only; no network calls on dot-source.
function Get-GMCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][string]$ExpectedPath)
    $pages=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $all=[Collections.Generic.List[object]]::new()
    while ($Uri) {
        $parsed=$null
        if (-not [uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or $parsed.AbsolutePath -cne $ExpectedPath -or $parsed.UserInfo -or $parsed.Fragment) {
            throw 'Unexpected Graph pagination URL; no partial results returned.'
        }
        if (-not $pages.Add($Uri)) { throw 'Repeated pagination URL; no partial results returned.' }
        $page=Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType Hashtable -ErrorAction Stop
        if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value') -or $null -eq $page['value']) { throw 'Invalid Graph collection response.' }
        foreach ($item in @($page['value'])) {
            if ($item -isnot [System.Collections.IDictionary]) { throw 'Invalid collection item.' }
            $id=[guid]::Empty
            if (-not [guid]::TryParse([string]$item['id'],[ref]$id)) { throw 'Collection item missing immutable object ID.' }
            if ($ids.Add($id.ToString('D'))) { $all.Add($item) }
        }
        $Uri=[string]$page['@odata.nextLink']
    }
    $all.ToArray()
}
function Select-GMGroupMatches {
    param([AllowEmptyCollection()][object[]]$Groups=@(),[string]$Search)
    foreach ($group in $Groups) {
        $matched=-not $Search
        foreach ($field in @('displayName','mail','id')) {
            if (([string]$group[$field]).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched=$true; break }
        }
        if ($matched) { $group }
    }
}
function ConvertTo-GMMemberRow {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Member,
          [Parameter(Mandatory)][System.Collections.IDictionary]$Group)
    $type=[string]$Member['@odata.type']
    $label=switch ($type) {
        '#microsoft.graph.user' {'User'}
        '#microsoft.graph.group' {'Group'}
        '#microsoft.graph.device' {'Device'}
        '#microsoft.graph.orgContact' {'Organizational contact'}
        '#microsoft.graph.servicePrincipal' {'Service principal'}
        default { if ($type) { $type } else { 'Unknown' } }
    }
    $limited=-not ([string]$Member['displayName'] -or [string]$Member['mail'] -or [string]$Member['userPrincipalName'])
    [pscustomobject]@{
        GroupName=[string]$Group['displayName']
        GroupId=[string]$Group['id']
        MembershipScope='Direct'
        ObjectType=$label
        DisplayName=[string]$Member['displayName']
        UserPrincipalName=[string]$Member['userPrincipalName']
        Mail=[string]$Member['mail']
        ObjectId=[string]$Member['id']
        Information=$(if ($limited) {'Limited information returned'} else {'Available properties shown'})
        Coverage='Graph v1.0; service principals may be omitted; not effective-access inventory'
    }
}
function ConvertTo-GMCsvSafeRow {
    param([Parameter(Mandatory)][object]$Row)
    $result=[ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        $value=$p.Value
        if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
        $result[$p.Name]=$value
    }
    [pscustomobject]$result
}
