function Get-ToolkitCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)
    $ids=@{}; $catalog=@()
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $Root 'Scripts') -Directory | Sort-Object Name)) {
        $def=Join-Path $dir.FullName 'Category.psd1'
        if (-not (Test-Path -LiteralPath $def)) { continue }
        if ($dir.LinkType -in @('SymbolicLink','Junction') -or (Get-Item -LiteralPath $def).LinkType -in @('SymbolicLink','Junction')) { throw 'Linked category directory/definition blocked.' }
        $c=Import-PowerShellDataFile -LiteralPath $def
        foreach ($field in @('Id','Name','Order')) { if (-not $c.ContainsKey($field)) { throw "Missing category field ${field}: $def" } }
        if ($c.Id -notmatch '^[a-z][a-z0-9.-]*$' -or $ids.ContainsKey($c.Id)) { throw "Invalid or duplicate ID: $($c.Id)" }
        $ids[$c.Id]=$true
        $tasks=@()
        foreach ($file in @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.task.psd1' -File)) {
            if ($file.LinkType -in @('SymbolicLink','Junction')) { throw 'Linked task definition blocked.' }
            $t=Import-PowerShellDataFile -LiteralPath $file.FullName
            foreach ($field in @('Id','Name','Description','Script','Order','Status','Services','GraphScopes')) { if (-not $t.ContainsKey($field)) { throw "Missing task field ${field}: $($file.Name)" } }
            if ($t.Id -notmatch '^[a-z][a-z0-9.-]*$' -or $ids.ContainsKey($t.Id)) { throw "Invalid or duplicate ID: $($t.Id)" }
            $ids[$t.Id]=$true
            if ($t.Status -notin @('Planned','Ready','Disabled')) { throw "Invalid status: $($t.Id)" }
            if ($t.Script -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*\.ps1$') { throw "Unsafe script filename: $($t.Id)" }
            if (@($t.Services).Count -eq 0) { throw "Services required: $($t.Id)" }
            foreach ($service in @($t.Services)) { if ($service -notin @('Graph','ExchangeOnline','SharePoint')) { throw "Invalid service: $service" } }
            $path=Join-Path $dir.FullName $t.Script
            if (Test-Path -LiteralPath $path) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Not a script file: $path" }
                if ((Get-Item -LiteralPath $path).LinkType -in @('SymbolicLink','Junction')) { throw 'Linked task script blocked.' }
                $tokens=$null; $errors=$null
                [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
                if (@($errors).Count) { throw "Script syntax error: $($t.Id): $($errors.Message -join '; ')" }
            }
            elseif ($t.Status -eq 'Ready') { throw "Ready task script missing: $($t.Id)" }
            $access=if ($t.ContainsKey('AccessMode')) { [string]$t.AccessMode } else { 'Changes' }
            $review=if ($t.ContainsKey('PermissionReview')) { [string]$t.PermissionReview } else { 'Unreviewed' }
            if ($access -notin @('ReadOnly','Changes') -or $review -notin @('Reviewed','Unreviewed')) { throw "Invalid task access/review metadata: $($t.Id)" }
            $tasks += [pscustomobject]@{AccessMode=$access;PermissionReview=$review;Id=$t.Id;Name=$t.Name;Description=$t.Description;Script=$t.Script;Path=$path;Order=[int]$t.Order;Status=$t.Status;Services=@($t.Services);GraphScopes=@($t.GraphScopes)}
        }
        $catalog += [pscustomobject]@{Id=$c.Id;Name=$c.Name;Order=[int]$c.Order;Key='';Folder=$dir.Name;Tasks=@($tasks | Sort-Object Order,Name,Id)}
    }
    $catalog=@($catalog | Sort-Object Order,Name,Id)
    for ($i=0; $i -lt $catalog.Count; $i++) { $catalog[$i].Key=[string]($i+1) }
    return $catalog
}
