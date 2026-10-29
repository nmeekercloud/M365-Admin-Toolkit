# Definitions only. No tenant changes on dot-source.
function Get-CGDirectGroups {
    param([Parameter(Mandatory)][string]$UserId)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($UserId,[ref]$id)) { throw 'Invalid user object ID.' }
    $path='/users/'+$id.ToString('D')+'/memberOf/microsoft.graph.group?$select=id'
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $all=[Collections.Generic.List[string]]::new()
    while ($path) {
        if (-not $seen.Add($path)) { throw 'Repeated membership pagination URL.' }
        if ($path.StartsWith('https://')) {
            $u=[uri]$path
            $expected='/v1.0/users/'+$id.ToString('D')+'/memberOf/microsoft.graph.group'
            if ($u.Host -ne 'graph.microsoft.com' -or $u.Scheme -ne 'https' -or $u.AbsolutePath -cne $expected -or $u.UserInfo -or $u.Fragment) { throw 'Unexpected membership pagination target.' }
        }
        $page=Invoke-UMGraph -Path $path
        if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value') -or $null -eq $page['value']) { throw 'Invalid direct-group response.' }
        foreach ($entry in @($page['value'])) {
            $groupId=[guid]::Empty
            if (-not [guid]::TryParse([string]$entry['id'],[ref]$groupId)) { throw 'Invalid group ID in membership response.' }
            if ($ids.Add($groupId.ToString('D'))) { $all.Add($groupId.ToString('D')) }
        }
        $path=[string]$page['@odata.nextLink']
    }
    $all.ToArray()
}
function Select-CGPlanIds {
    param([Parameter(Mandatory)][object[]]$Plan,[string]$Selection)
    if (-not $Selection) { return }
    $eligible=@($Plan | Where-Object Status -eq 'Eligible')
    if ($Selection.Trim() -ieq 'ALL') { foreach ($row in $eligible) { [string]$row.Id }; return }
    $tokens=@($Selection -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $tokens.Count) { throw 'Enter group numbers, ALL or Enter to cancel.' }
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result=[Collections.Generic.List[string]]::new()
    foreach ($token in $tokens) {
        $number=0
        if (-not [int]::TryParse($token,[ref]$number) -or $number -lt 1) { throw ('Invalid group number: '+$token) }
        $row=@($eligible | Where-Object Number -eq $number)
        if ($row.Count -ne 1) { throw ('Not an eligible group number: '+$token) }
        if ($selected.Add([string]$row[0].Id)) { $result.Add([string]$row[0].Id) }
    }
    $result.ToArray()
}
function ConvertTo-CGCsvSafeRow {
    param([object]$Row)
    $properties=[ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        $value=$p.Value
        if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
        $properties[$p.Name]=$value
    }
    [pscustomobject]$properties
}
