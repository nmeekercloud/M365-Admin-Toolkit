# Internal state only. This is not a credential/token cache.
$script:ToolkitActiveTaskAuthentication=$null

function Get-ToolkitTaskAuthenticationRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [string[]]$Ancestors=@(),
        [hashtable]$Definitions,
        [hashtable]$Policy
    )
    if ($TaskId -notmatch '^[a-z][a-z0-9.-]*$') { throw "Invalid task ID: $TaskId" }
    if ($TaskId -in $Ancestors) { throw ('Authentication dependency cycle: '+(($Ancestors+@($TaskId)) -join ' -> ')) }
    if ($null -eq $Definitions) {
        $Definitions=@{}
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:ToolkitRoot 'Scripts') -Recurse -File -Filter '*.task.psd1')) {
            if ($file.LinkType) { throw "Linked task definition blocked: $($file.FullName)" }
            $def=Import-PowerShellDataFile -LiteralPath $file.FullName
            if (-not $def.ContainsKey('Id')) { throw "Missing task ID: $($file.FullName)" }
            $id=[string]$def.Id
            if ($Definitions.ContainsKey($id)) { throw "Duplicate task ID: $id" }
            $Definitions[$id]=$def
        }
    }
    if ($null -eq $Policy) {
        $Policy=Import-PowerShellDataFile -LiteralPath (Join-Path $script:ToolkitRoot 'Config/Task.Authentication.psd1')
        if ($Policy.SchemaVersion -ne 1) { throw 'Unsupported authentication policy schema.' }
    }
    if (-not $Definitions.ContainsKey($TaskId)) { throw "Authentication task definition missing: $TaskId" }
    $task=$Definitions[$TaskId]
    if ($task.Status -ne 'Ready') { throw "Authentication dependency is not Ready: $TaskId" }
    $services=@('Graph')+@($task.Services); $scopes=@($task.GraphScopes)
    $dependencies=@(); $included=@($TaskId)
    if ($task.ContainsKey('AuthenticationDependencies')) { $dependencies+=@($task.AuthenticationDependencies) }
    if ($Policy.Tasks.ContainsKey($TaskId)) {
        $extra=$Policy.Tasks[$TaskId]
        if ($extra.ContainsKey('Services')) { $services+=@($extra.Services) }
        if ($extra.ContainsKey('GraphScopes')) { $scopes+=@($extra.GraphScopes) }
        if ($extra.ContainsKey('Dependencies')) { $dependencies+=@($extra.Dependencies) }
    }
    foreach ($id in @($dependencies | Sort-Object -Unique)) {
        $child=Get-ToolkitTaskAuthenticationRequirements -TaskId $id -Ancestors ($Ancestors+@($TaskId)) -Definitions $Definitions -Policy $Policy
        $services+=@($child.Services); $scopes+=@($child.GraphScopes); $included+=@($child.TaskIds)
    }
    foreach ($service in $services) {
        if ($service -notin @('Graph','ExchangeOnline','SharePoint')) { throw "Unsupported task service: $service" }
    }
    [pscustomobject]@{
        TaskId=$TaskId; TaskIds=@($included | Sort-Object -Unique)
        Services=@($services | Where-Object { $_ } | Sort-Object -Unique)
        GraphScopes=@($scopes | Where-Object { $_ } | Sort-Object -Unique)
    }
}
