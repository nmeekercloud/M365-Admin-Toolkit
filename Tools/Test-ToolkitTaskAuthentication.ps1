#Requires -Version 7.4
[CmdletBinding()]
param([string]$ToolkitPath=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ToolkitPath=(Resolve-Path -LiteralPath $ToolkitPath).Path
if (Get-Module M365Toolkit.Core) { throw 'Validate in a fresh PowerShell window with the toolkit closed.' }
try {
    Import-Module (Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
    $module=Get-Module M365Toolkit.Core
    $TenantDomain=$null
    . (Join-Path $ToolkitPath 'Tools/Toolkit.Catalog.ps1')
    . (Join-Path $ToolkitPath 'Tools/Toolkit.ConnectionProfiles.ps1')
    $catalog=@(Get-ToolkitCatalog -Root $ToolkitPath)
    $ready=@($catalog | ForEach-Object { $_.Tasks } | Where-Object Status -eq 'Ready')
    if (-not $ready.Count) { throw 'No Ready tasks found.' }
    foreach ($task in $ready) {
        $plan=Get-ToolkitTaskConnectionPlan -Task $task -Catalog $catalog
        foreach ($scope in $task.GraphScopes) { if ($scope -notin $plan.GraphScopes) { throw "Declared permission missing for $($task.Id): $scope" } }
        foreach ($service in $task.Services) { if ($service -notin $plan.Services) { throw "Declared service missing for $($task.Id): $service" } }
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($task.Path,[ref]$tokens,[ref]$errors)
        if (@($errors).Count) { throw "Task syntax error: $($task.Id)" }
        $commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Assert-M365Connection','Initialize-UMTask','Initialize-WFTask')},$true))
        foreach ($command in $commands) {
            $elements=@($command.CommandElements)
            for ($i=0; $i -lt $elements.Count; $i++) {
                $element=$elements[$i]
                if ($element -isnot [Management.Automation.Language.CommandParameterAst]) { continue }
                if ($element.ParameterName -eq 'Exchange' -and 'ExchangeOnline' -notin $plan.Services) { throw "Exchange not preflighted: $($task.Id)" }
                if ($element.ParameterName -notin @('Scopes','GraphScopes','Service')) { continue }
                if ($i+1 -ge $elements.Count) { throw "Invalid authentication argument: $($task.Id)" }
                try { $values=@($elements[$i+1].SafeGetValue()) } catch { continue }
                foreach ($value in $values) {
                    if ($element.ParameterName -eq 'Service') {
                        if ($value -notin $plan.Services) { throw "Nested service missing for $($task.Id): $value" }
                    } elseif ($value -notin $plan.GraphScopes) { throw "Nested scope missing for $($task.Id): $value" }
                }
            }
        }
        Write-Host ('PASS '+$task.Id+' | '+($plan.Services -join ', ')+' | '+$plan.GraphScopes.Count+' scopes') -ForegroundColor Green
    }
    $expected=@{
        'users.new-user'=@('User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
        'users.invoke-bulkusermanagement'=@('User.Read.All','User.ReadWrite.All','User.EnableDisableAccount.All','User.RevokeSessions.All')
        'users.disable-user'=@('User.Read.All','User.EnableDisableAccount.All','User.RevokeSessions.All','LicenseAssignment.ReadWrite.All')
    }
    foreach ($id in $expected.Keys) {
        $req=& $module {param($id) Get-ToolkitTaskAuthenticationRequirements -TaskId $id} $id
        foreach ($scope in $expected[$id]) { if ($scope -notin $req.GraphScopes) { throw "Workflow requirement missing: $id / $scope" } }
        if ($id -eq 'users.disable-user' -and ('ExchangeOnline' -notin $req.Services -or $req.TaskIds.Count -ne 7)) { throw 'Offboarding dependency preflight incomplete.' }
    }
    $license=& $module {Get-ToolkitTaskAuthenticationRequirements -TaskId 'users.remove-licenses'}
    if ('ExchangeOnline' -notin $license.Services) { throw 'License preservation Exchange preflight missing.' }
    $source=Get-Content -LiteralPath (Join-Path $ToolkitPath 'Modules/M365Toolkit.Core/Private/ConnectionHelpers.ps1') -Raw
    if ($source -notmatch "ContextScope\s*=\s*'Process'") { throw 'Expected process-scoped Graph authentication was not found.' }
    Write-Host ("Validated all $($ready.Count) Ready task plans. No tenant sign-in or tenant writes were performed.") -ForegroundColor Green
}
finally { if (Get-Module M365Toolkit.Core) { Remove-Module M365Toolkit.Core -Force } }
