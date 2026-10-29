# Shared helpers for the User Management testing add-on. No automatic tenant changes.
function Initialize-UMTask {
    param([string]$Root,[string]$TaskId,[string]$TaskName,[string[]]$Scopes)
    $manifest = Join-Path $Root '../../Modules/M365Toolkit.Core/M365Toolkit.Core.psd1'
    if (-not (Get-Module M365Toolkit.Core)) { Import-Module $manifest -Global -ErrorAction Stop }
    Assert-M365TaskAccess -AccessMode Changes -TaskId $TaskId
    $tenant = Assert-M365Connection -Service Graph -GraphScopes $Scopes -TaskName $TaskName -TaskId $TaskId
    if (-not $tenant -or -not $tenant.TenantId) { throw 'A verified tenant is required.' }
    return $tenant
}
function Invoke-UMGraph {
    param([ValidateSet('GET','POST','PATCH')][string]$Method='GET',[string]$Path,[hashtable]$Body)
    if ($Path -notmatch '^/' -and $Path -notmatch '^https://graph\.microsoft\.com/v1\.0/') {
        throw 'Unexpected Graph path.'
    }
    $uri = if ($Path.StartsWith('/')) { 'https://graph.microsoft.com/v1.0'+$Path } else { $Path }
    $args = @{ Method=$Method; Uri=$uri; OutputType='Hashtable'; ErrorAction='Stop' }
    if ($null -ne $Body) { $args.Body=$Body | ConvertTo-Json -Depth 15 -Compress; $args.ContentType='application/json' }
    Invoke-MgGraphRequest @args
}
function Get-UMCollection {
    param([string]$Path)
    $next=$Path
    while ($next) {
        $page=Invoke-UMGraph -Path $next
        if (-not $page.ContainsKey('value')) { throw 'Graph did not return a collection.' }
        foreach ($item in @($page['value'])) { $item }
        $next=[string]$page['@odata.nextLink']
    }
}
function Get-UMUser {
    param([string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'A user identity is required.' }
    $id=[uri]::EscapeDataString($Identity.Trim())
    Invoke-UMGraph -Path ('/users/'+$id+'?$select=id,displayName,userPrincipalName,userType,onPremisesSyncEnabled,accountEnabled,department,jobTitle,officeLocation,usageLocation,assignedLicenses')
}
function Assert-UMCloudMember {
    param([System.Collections.IDictionary]$User,[switch]$AllowSelf,[object]$Tenant)
    if ($User['userType'] -ne 'Member') { throw 'This release supports member accounts only, not guests.' }
    # Directory synchronization alone does not reject a tenant Member user.
    # Attribute authority, hybrid consistency and API permissions still apply per operation.
    if (-not $AllowSelf -and [string]$User['userPrincipalName'] -ieq [string]$Tenant.Account) {
        throw 'Changing the signed-in account through this task is blocked.'
    }
}
function Get-UMGroupReason {
    param([System.Collections.IDictionary]$Group)
    foreach ($key in @('id','groupTypes','mailEnabled','securityEnabled','isAssignableToRole','onPremisesSyncEnabled')) {
        if (-not $Group.Contains($key)) { return 'Incomplete group metadata; skipped safely' }
    }
    # Do not turn limited-information directory objects into eligible groups.
    if ([string]::IsNullOrWhiteSpace([string]$Group['id']) -or
        $null -eq $Group['groupTypes'] -or $Group['groupTypes'] -is [string] -or
        $Group['mailEnabled'] -isnot [bool] -or $Group['securityEnabled'] -isnot [bool]) {
        return 'Incomplete group metadata; skipped safely'
    }
    # Graph returns explicit null for ordinary groups as well as false. A missing
    # property remains blocked above; malformed/non-Boolean values stay blocked.
    $roleFlag=$Group['isAssignableToRole']
    if ($null -ne $roleFlag -and $roleFlag -isnot [bool]) { return 'Unverified role status; skipped safely' }
    if ($roleFlag -eq $true) { return 'Role-assignable group; excluded' }
    $syncFlag=$Group['onPremisesSyncEnabled']
    if ($null -ne $syncFlag -and $syncFlag -isnot [bool]) { return 'Unverified synchronization status; skipped safely' }
    if ($syncFlag -eq $true) { return 'Synchronized group' }
    if (@($Group['groupTypes']) -contains 'DynamicMembership') { return 'Dynamic membership group' }
    if (@($Group['groupTypes']) -contains 'Unified') { return '' }
    if ($Group['mailEnabled'] -eq $false -and $Group['securityEnabled'] -eq $true) { return '' }
    return 'Exchange-managed or unsupported group type'
}
function Get-UMGroup {
    param([string]$Id)
    $guid=[guid]::Empty
    if (-not [guid]::TryParse($Id,[ref]$guid)) { throw "Group ID is not a GUID: $Id" }
    Invoke-UMGraph -Path ('/groups/'+$guid.ToString()+'?$select=id,displayName,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,isAssignableToRole')
}
function Save-UMJson {
    param([object]$Value,[string]$Label,[ValidateSet('Backups','Reports')][string]$Type='Backups')
    $path=Get-M365OutputPath -Type $Type -FileName ($Label+'-'+[guid]::NewGuid().ToString('N')+'.json')
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
    Write-Host "Saved: $path"
    return $path
}
function Write-UMResults {
    param([object[]]$Results,[string]$Label,[switch]$NoInteractive,[string]$ExportPath)
    # Display and export are independent from the already-completed cloud operation.
    Show-M365Results -InputObject @($Results) -Title $Label -NoPaging:$NoInteractive
    $saved=Export-M365Csv -InputObject @($Results) -ReportName $Label -NoInteractive:$NoInteractive -Path $ExportPath -PassThru
    $failed=@($Results | Where-Object Result -eq 'Failed').Count
    $verificationIncomplete=@($Results | Where-Object Result -eq 'VerificationIncomplete').Count
    Write-M365Log -Message "$Label completed: $($Results.Count) results; $failed failed; $verificationIncomplete verification incomplete. Export: $($saved.Status)." -Level Info
}
function ConvertTo-UMList {
    param([string]$Text)
    @($Text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
}
function New-UMProfileBody {
    param([object]$Row)
    $body=@{}
    foreach ($key in @('DisplayName','Department','JobTitle','OfficeLocation')) {
        $property=$Row.PSObject.Properties[$key]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $apiKey=$key.Substring(0,1).ToLowerInvariant()+$key.Substring(1)
            $body[$apiKey]=([string]$property.Value).Trim()
        }
    }
    return $body
}
