# Definitions only. No network calls on dot-source.
function Get-BGMDirectGroups {
 param([Parameter(Mandatory)][string]$UserId)
 $id=[guid]::Empty
 if (-not [guid]::TryParse($UserId,[ref]$id)) { throw 'Invalid user object ID.' }
 $expected='/v1.0/users/'+$id.ToString('D')+'/memberOf/microsoft.graph.group'
 $path='/users/'+$id.ToString('D')+'/memberOf/microsoft.graph.group?$select=id'
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $all=[Collections.Generic.List[string]]::new()
 while ($path) {
  if (-not $seen.Add($path)) { throw 'Repeated membership pagination URL.' }
  if ($path.StartsWith('https://')) {
   $u=[uri]$path
   if ($u.Scheme -ne 'https' -or $u.Host -ne 'graph.microsoft.com' -or $u.AbsolutePath -cne $expected -or $u.UserInfo -or $u.Fragment) { throw 'Unexpected membership pagination target.' }
  } elseif ($path -notlike '/users/*') { throw 'Unexpected membership URL.' }
  $page=Invoke-UMGraph -Path $path
  if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value') -or $null -eq $page['value']) { throw 'Invalid direct-group response.' }
  foreach ($entry in @($page['value'])) {
   $g=[guid]::Empty
   if (-not [guid]::TryParse([string]$entry['id'],[ref]$g)) { throw 'Invalid group ID in response.' }
   if ($ids.Add($g.ToString('D'))) { $all.Add($g.ToString('D')) }
  }
  $path=[string]$page['@odata.nextLink']
 }
 $all.ToArray()
}
function ConvertTo-BGMCsvSafeRow {
 param([object]$Row)
 $properties=[ordered]@{}
 foreach ($p in $Row.PSObject.Properties) {
  $value=$p.Value
  if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
  $properties[$p.Name]=$value
 }
 [pscustomobject]$properties
}

function Import-BGMCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath,[ValidateRange(1,10000)][int]$MaxRows=1000)
    $file=Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -ine '.csv') { throw 'Select a CSV file, not a folder or another file type.' }
    if ($file.Length -gt 10MB) { throw 'CSV exceeds the 10 MB safety limit.' }
    Add-Type -AssemblyName Microsoft.VisualBasic.Core -ErrorAction Stop
    $parser=[Microsoft.VisualBasic.FileIO.TextFieldParser]::new($file.FullName,[Text.UTF8Encoding]::new($false,$true),$true)
    $rows=[Collections.Generic.List[object]]::new()
    try {
        $parser.TextFieldType=[Microsoft.VisualBasic.FileIO.FieldType]::Delimited
        $parser.SetDelimiters([string[]]@(','))
        $parser.HasFieldsEnclosedInQuotes=$true
        $parser.TrimWhiteSpace=$false
        if ($parser.EndOfData) { throw 'CSV is empty.' }
        $headers=@($parser.ReadFields() | ForEach-Object { $_.Trim() })
        if ($headers.Count -ne 2 -or @($headers | Where-Object { $_ -ieq 'GroupId' }).Count -ne 1 -or @($headers | Where-Object { $_ -ieq 'UserPrincipalName' }).Count -ne 1) {
            throw 'CSV must have exactly GroupId and UserPrincipalName headers (comma-delimited).'
        }
        $groupIndex=if ($headers[0] -ieq 'GroupId') {0} else {1}
        $userIndex=1-$groupIndex
        $record=1
        while (-not $parser.EndOfData) {
            $record++
            $fields=$parser.ReadFields()
            if ($fields.Count -ne 2) { throw ('CSV record '+$record+' must contain exactly two fields.') }
            $id=[guid]::Empty
            if (-not [guid]::TryParse($fields[$groupIndex].Trim(),[ref]$id) -or $id -eq [guid]::Empty) { throw ('Invalid GroupId at CSV record '+$record) }
            $upn=$fields[$userIndex].Trim()
            if ($upn -notmatch '^[^@\s]+@[^@\s]+$' -or $upn.Length -gt 254) { throw ('Invalid UserPrincipalName at CSV record '+$record) }
            if ($rows.Count -ge $MaxRows) { throw ('CSV exceeds the '+$MaxRows+' row safety limit. Split the batch; no rows were submitted.') }
            $rows.Add([pscustomobject]@{Record=$record;GroupId=$id.ToString('D');UserPrincipalName=$upn})
        }
        if (-not $rows.Count) { throw 'CSV contains only headers. Add real group/user rows first.' }
    } finally { $parser.Close(); $parser.Dispose() }
    $rows.ToArray()
}
