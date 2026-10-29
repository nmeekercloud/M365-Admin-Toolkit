#Requires -Version 7.4
[CmdletBinding()]
param([string]$ToolkitPath=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $ToolkitPath 'Tools/Toolkit.ReportsAuditing.ps1')
$script:Checks=0
function Assert-R3Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAILED: $Message" }; $script:Checks++ }
Assert-R3Test ((Get-R3Field @{name='x'} name) -eq 'x') 'dictionary field'
Assert-R3Test ((Get-R3Field ([pscustomobject]@{name='y'}) name) -eq 'y') 'object field'
Assert-R3Test ((Get-R3Field @{} absent fallback) -eq 'fallback') 'missing field default'
foreach ($url in @('https://evil.example/v1.0/users','http://graph.microsoft.com/v1.0/users','https://graph.microsoft.com.evil.example/v1.0/users','https://u@graph.microsoft.com/v1.0/users','https://graph.microsoft.com:444/v1.0/users','https://graph.microsoft.com/beta/users')) {
    $threw=$false; try { $null=Assert-R3GraphUri $url } catch { $threw=$true }
    Assert-R3Test $threw 'unsafe Graph URL rejected'
}
$script:PageMap=@{}; $script:Calls=[System.Collections.Generic.List[object]]::new()
function Invoke-MgGraphRequest {
    [CmdletBinding()]
    param($Method,$Uri,$OutputType,$Headers)
    $script:Calls.Add([pscustomobject]@{Uri=$Uri;Headers=$Headers;Method=$Method})
    if (-not $script:PageMap.ContainsKey($Uri)) { throw 'synthetic missing response' }
    return $script:PageMap[$Uri]
}
$first='https://graph.microsoft.com/v1.0/users?$top=999'
$second='https://graph.microsoft.com/v1.0/users?$skiptoken=next'
$script:PageMap=@{}
$script:PageMap[$first]=@{value=@(@{id='one'});'@odata.nextLink'=$second}
$script:PageMap[$second]=@{value=@(@{id='two'})}
$r=Get-R3Collection $first
Assert-R3Test ($r.Complete -and $r.Rows.Count -eq 2 -and $r.Pages -eq 2) 'multi-page read'
$script:PageMap[$first]=@{value=@()}
$r=Get-R3Collection $first
Assert-R3Test ($r.Complete -and $r.Rows.Count -eq 0) 'empty value array accepted'
$script:PageMap[$first]=@{value=@(@{id='one'});'@odata.nextLink'=$first}
$r=Get-R3Collection $first
Assert-R3Test (-not $r.Complete -and $r.Rows.Count -eq 1 -and $r.Issue -match 'Repeated') 'cycle retains partial rows'
$script:PageMap[$first]=@{value=@(@{id='one'});'@odata.nextLink'='https://evil.example/v1.0/users'}
$r=Get-R3Collection $first
Assert-R3Test (-not $r.Complete -and $r.Rows.Count -eq 1) 'foreign nextLink never requested'
Assert-R3Test (@($script:Calls | Where-Object { $_.Uri -like 'https://evil.example*' }).Count -eq 0) 'no foreign-host SDK call'
$script:PageMap[$first]=@{value=@(@{id='one'});'@odata.nextLink'=$second}
$r=Get-R3Collection $first -MaxPages 1
Assert-R3Test (-not $r.Complete -and $r.Issue -match 'Page limit') 'page cap marked partial'
$cast='https://graph.microsoft.com/v1.0/users/user/transitiveMemberOf/microsoft.graph.group?$count=true&$select=id'
$script:PageMap[$cast]=@{value=@()}; $null=Get-R3Collection $cast
Assert-R3Test ($script:Calls[-1].Headers.ConsistencyLevel -eq 'eventual') 'membership cast uses advanced-query header'
$u=@{id='user';displayName='User';userPrincipalName='user@example.net';accountEnabled=$true;userType='Member';assignedLicenses=@(@{skuId='sku'});licenseAssignmentStates=@(@{skuId='sku';assignedByGroup=$null;state='Active';disabledPlans=@()},@{skuId='sku';assignedByGroup='group';state='Error';error='CountViolation';disabledPlans=@()})}
$map=@{sku='PRODUCT'}
$rows=@(Get-R3LicenseRows $u $map)
Assert-R3Test ($rows.Count -eq 2 -and 'Direct' -in $rows.Source -and 'Group' -in $rows.Source) 'license sources remain distinct'
Assert-R3Test (@($rows | Where-Object { $_.Source -eq 'Group' -and $_.Error -eq 'CountViolation' }).Count -eq 1) 'license error preserved'
$u.licenseAssignmentStates=@()
$rows=@(Get-R3LicenseRows $u $map)
Assert-R3Test ($rows.Count -eq 1 -and $rows[0].Source -eq 'Unknown') 'missing state not assumed direct'
$u.licenseAssignmentStates=@(@{skuId='sku';state='Active'})
$rows=@(Get-R3LicenseRows $u $map)
Assert-R3Test ($rows[0].Source -eq 'Unknown') 'missing assignedByGroup field not assumed direct'
$u.assignedLicenses=@(); $u.licenseAssignmentStates=@()
Assert-R3Test (@(Get-R3LicenseRows $u $map -IncludeUnlicensed).Count -eq 1) 'unlicensed row optional'
$c=@{id='user';displayName='User';userPrincipalName='user@example.net';mail='mail@example.net';accountEnabled=$true;userType='Member';businessPhones=@('123','456')}
$row=Get-R3ContactRow $c
Assert-R3Test ($row.EmailAddress -eq 'mail@example.net' -and $row.BusinessPhones -eq '123; 456') 'contact email and phone flattening'
$c.accountEnabled=$false
Assert-R3Test ($null -eq (Get-R3ContactRow $c)) 'disabled excluded by default'
Assert-R3Test ($null -ne (Get-R3ContactRow $c -IncludeDisabled)) 'disabled explicit inclusion'
$c.accountEnabled=$true; $c.userType='Guest'
Assert-R3Test ($null -eq (Get-R3ContactRow $c)) 'guests excluded by default'
$c.userType='Member'; $c.mail=''
Assert-R3Test ($null -eq (Get-R3ContactRow $c)) 'missing mail not silently replaced'
$row=Get-R3ContactRow $c -UseUpnFallback
Assert-R3Test ($row.EmailAddress -eq 'user@example.net' -and $row.EmailSource -match 'not verified') 'explicit UPN fallback labeled'
foreach ($stem in @('Get-LicenseReport','Get-UserAccessReport','Export-ContactList')) {
    $m=Import-PowerShellDataFile (Join-Path $ToolkitPath "Scripts/Reports/$stem.task.psd1")
    Assert-R3Test ($m.Status -eq 'Ready' -and $m.AccessMode -eq 'ReadOnly' -and @($m.Services).Count -eq 1 -and $m.Services[0] -eq 'Graph' -and $m.GraphScopes -contains 'User.Read.All') "manifest $stem"
}
Write-Host "Reports/Auditing isolated checks passed: $script:Checks. Synthetic Graph responses; no tenant calls or report writes."
