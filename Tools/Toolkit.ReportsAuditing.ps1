#Requires -Version 7.4
# Dot-sourcing defines helpers only; no authentication, SDK imports or writes.
function Get-R3Field {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    } elseif ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}
function Test-R3Field {
    param($Object,[string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}
function Initialize-R3Task {
    param([string[]]$Scopes)
    if (-not (Get-Module M365Toolkit.Core)) {
        Import-Module (Join-Path $PSScriptRoot '../Modules/M365Toolkit.Core/M365Toolkit.Core.psd1') -ErrorAction Stop
    }
    $null=Assert-M365Connection -Service Graph -GraphScopes $Scopes
}
function Assert-R3GraphUri {
    param([string]$Uri)
    $parsed=$null
    if (-not [uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or $parsed.Port -ne 443 -or $parsed.UserInfo -or $parsed.Fragment -or $parsed.AbsolutePath -notmatch '^/v1\.0/') {
        throw 'Refusing a non-global-cloud Graph v1.0 URL.'
    }
    return $parsed.AbsoluteUri
}
function Invoke-R3Get {
    param([string]$Uri)
    $safe=Assert-R3GraphUri $Uri
    if (([uri]$safe).AbsolutePath -match '/(memberOf|transitiveMemberOf)/microsoft\.graph\.group$') {
        return (Invoke-MgGraphRequest -Method GET -Uri $safe -Headers @{ConsistencyLevel='eventual'} -OutputType PSObject -ErrorAction Stop)
    }
    return (Invoke-MgGraphRequest -Method GET -Uri $safe -OutputType PSObject -ErrorAction Stop)
}
function Get-R3Collection {
    param([string]$Uri,[ValidateRange(1,100000)][int]$MaxPages=2000)
    $rows=[System.Collections.Generic.List[object]]::new()
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $next=$Uri; $pages=0; $complete=$false; $issue=''
    try {
        while ($next) {
            if ($pages -ge $MaxPages) { throw 'Page limit reached; narrow the query.' }
            $safe=Assert-R3GraphUri $next
            if (-not $seen.Add($safe)) { throw 'Repeated Graph nextLink; stopping rather than looping.' }
            $page=Invoke-R3Get $safe
            $values=Get-R3Field $page 'value'
            if ($null -eq $page.value) { throw 'Graph collection response did not include a non-null value collection.' }
            foreach ($item in @($values)) { if ($null -ne $item) { $rows.Add($item) } }
            $pages++
            $next=[string](Get-R3Field $page '@odata.nextLink' '')
        }
        $complete=$true
    } catch { $issue=$_.Exception.Message }
    [pscustomobject]@{Rows=@($rows.ToArray());Complete=$complete;Pages=$pages;Issue=$issue}
}
function Get-R3Users {
    param([string[]]$UserPrincipalName,[string]$Select)
    $UserPrincipalName = @(
        $UserPrincipalName |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
    if ($UserPrincipalName.Count -eq 0) {
        return (Get-R3Collection (
            'https://graph.microsoft.com/v1.0/users?$top=999&$select=' + $Select
        ))
    }
    $rows=[System.Collections.Generic.List[object]]::new(); $errors=[System.Collections.Generic.List[string]]::new()
    $ids=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($upn in @($UserPrincipalName | Select-Object -Unique)) {
        try {
            $user=Invoke-R3Get ('https://graph.microsoft.com/v1.0/users/'+[uri]::EscapeDataString($upn.Trim())+'?$select='+$Select)
            $id=[string](Get-R3Field $user 'id')
            if (-not $id) { throw 'User response has no id.' }
            if ($ids.Add($id)) { $rows.Add($user) }
        } catch { $errors.Add("$upn : $($_.Exception.Message)") }
    }
    [pscustomobject]@{Rows=@($rows.ToArray());Complete=($errors.Count -eq 0);Pages=0;Issue=($errors -join '; ')}
}
function Get-R3SkuMap {
    param([object[]]$Skus)
    $map=@{}
    foreach ($sku in $Skus) {
        $id=[string](Get-R3Field $sku 'skuId')
        if ($id) { $map[$id]=[string](Get-R3Field $sku 'skuPartNumber' $id) }
    }
    return $map
}
function Get-R3LicenseRows {
    param($User,[hashtable]$SkuMap,[switch]$IncludeUnlicensed)
    $assigned=@(Get-R3Field $User 'assignedLicenses' @())
    $states=@(Get-R3Field $User 'licenseAssignmentStates' @())
    $skuIds=@(@($assigned | ForEach-Object { [string](Get-R3Field $_ 'skuId') })+@($states | ForEach-Object { [string](Get-R3Field $_ 'skuId') }) | Where-Object { $_ } | Sort-Object -Unique)
    if (-not $skuIds.Count -and $IncludeUnlicensed) { $skuIds=@('') }
    foreach ($skuId in $skuIds) {
        $matching=@($states | Where-Object { [string](Get-R3Field $_ 'skuId') -eq $skuId })
        if (-not $matching.Count) { $matching=@($null) }
        foreach ($state in $matching) {
            $group=[string](Get-R3Field $state 'assignedByGroup')
            $source=if (-not $skuId) {'Unlicensed'} elseif ($null -eq $state) {'Unknown'} elseif (-not (Test-R3Field $state 'assignedByGroup')) {'Unknown'} elseif ($group) {'Group'} else {'Direct'}
            $disabled=if ($null -ne $state) { @(Get-R3Field $state 'disabledPlans' @()) } else { @($assigned | Where-Object { [string](Get-R3Field $_ 'skuId') -eq $skuId } | ForEach-Object { Get-R3Field $_ 'disabledPlans' @() }) }
            [pscustomobject]@{UserId=[string](Get-R3Field $User 'id');DisplayName=[string](Get-R3Field $User 'displayName');UserPrincipalName=[string](Get-R3Field $User 'userPrincipalName');AccountEnabled=Get-R3Field $User 'accountEnabled';UserType=[string](Get-R3Field $User 'userType');SkuId=$skuId;Product=$(if ($SkuMap.ContainsKey($skuId)) {$SkuMap[$skuId]} else {$skuId});Source=$source;AssignedByGroup=$group;State=$(if ($state) {[string](Get-R3Field $state 'state')} elseif ($skuId) {'Unknown'} else {'Unlicensed'});Error=[string](Get-R3Field $state 'error');DisabledPlans=($disabled -join '; ');LastUpdated=[string](Get-R3Field $state 'lastUpdatedDateTime')}
        }
    }
}
function Get-R3ContactRow {
    param($User,[switch]$IncludeDisabled,[switch]$IncludeGuests,[switch]$UseUpnFallback)
    $enabled=Get-R3Field $User 'accountEnabled'
    $type=[string](Get-R3Field $User 'userType')
    if (-not $IncludeDisabled -and $enabled -ne $true) { return }
    if (-not $IncludeGuests -and $type -ne 'Member') { return }
    $email=[string](Get-R3Field $User 'mail'); $source='mail'
    if (-not $email -and $UseUpnFallback) { $email=[string](Get-R3Field $User 'userPrincipalName'); $source='userPrincipalName fallback; not verified deliverable' }
    if (-not $email) { return }
    [pscustomobject]@{DisplayName=[string](Get-R3Field $User 'displayName');GivenName=[string](Get-R3Field $User 'givenName');Surname=[string](Get-R3Field $User 'surname');EmailAddress=$email;EmailSource=$source;UserPrincipalName=[string](Get-R3Field $User 'userPrincipalName');JobTitle=[string](Get-R3Field $User 'jobTitle');Department=[string](Get-R3Field $User 'department');CompanyName=[string](Get-R3Field $User 'companyName');OfficeLocation=[string](Get-R3Field $User 'officeLocation');BusinessPhones=(@(Get-R3Field $User 'businessPhones' @()) -join '; ');MobilePhone=[string](Get-R3Field $User 'mobilePhone');AccountEnabled=$enabled;UserType=$type;UserId=[string](Get-R3Field $User 'id')}
}
function Export-R3Csv {
    param([object[]]$Rows,[string[]]$Columns,[string]$Label,[ValidateSet('Reports','Exports')][string]$Type='Reports')
    $path=Get-R3ChosenOutputPath -Label $Label
    $safe=@(foreach ($row in $Rows) {
        $record=[ordered]@{}
        foreach ($column in $Columns) {
            $value=Get-R3Field $row $column
            if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value="'"+$value }
            $record[$column]=$value
        }
        [pscustomobject]$record
    })
    if ($safe.Count) { $safe | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8 }
    else { ($Columns -join ',') | Set-Content -LiteralPath $path -Encoding utf8 }
    Write-M365Log -Message "Saved $($safe.Count) rows: $path" -Level Info
    return $path
}
function Test-R3NeedsDiagnostics {
    param($Metadata)
    # R3 CONDITIONAL DIAGNOSTICS
    # Explicit known completion fields only. A false effective-access flag is not
    # a collection failure: User Details intentionally is not a full access audit.
    if ($null -eq $Metadata) { return $true }
    $found=$false
    foreach ($name in @('Complete','CollectedSegmentsComplete','InventoryComplete','UsersComplete')) {
        if (Test-R3Field $Metadata $name) {
            $found=$true
            if ((Get-R3Field $Metadata $name) -ne $true) { return $true }
        }
    }
    foreach ($name in @('Issue','InventoryIssue','UserIssue')) {
        $issue=[string](Get-R3Field $Metadata $name '')
        if (-not [string]::IsNullOrWhiteSpace($issue) -and $issue -ne 'Not requested') { return $true }
    }
    foreach ($segment in @(Get-R3Field $Metadata 'Segments' @())) {
        if ($null -eq $segment) { continue }
        if ((Get-R3Field $segment 'Complete') -ne $true) { return $true }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-R3Field $segment 'Issue' ''))) { return $true }
    }
    return (-not $found)
}
function Export-R3Coverage {
    param($Metadata,[string]$Label,[ValidateSet('Reports','Exports')][string]$Type='Reports')
    if (-not (Test-R3NeedsDiagnostics $Metadata)) {
        Write-Host 'Report retrieval completed successfully; no diagnostic JSON needed.' -ForegroundColor Green
        return $null
    }
    Write-Warning 'Report retrieval is incomplete or has diagnostic issues. Saving diagnostic JSON beside the report files.'
    $path=Get-R3ChosenOutputPath -Label ($Label+'-Coverage') -Coverage
    if ((Test-Path -LiteralPath $path) -and (Read-Host "Overwrite diagnostic JSON '$path'? [y/N]") -notmatch '^(?i)y(es)?$') {
        Write-Warning 'Diagnostic JSON was not saved; the existing diagnostic file was left unchanged.'
        return $null
    }
    $Metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    Write-M365Log -Message "Coverage: $path" -Level Info
    return $path
}

# Report destination prompts. Definitions only; no actions at import.
function Initialize-R3SaveChoice {
    param([switch]$SingleCsv,[string]$Label='Report')
    $script:R3SaveChoice=$null
    if ($SingleCsv) {
        $suggested=$Label+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.csv'
        Write-Host "Suggested filename: $suggested"
        $answer=([string](Read-Host 'Save CSV as - enter full path including filename.csv (blank cancels saving)')).Trim().Trim('"')
        if (-not $answer) { return $false }
        if ([IO.Path]::GetExtension($answer) -ne '.csv') { $answer+='.csv' }
        $full=[IO.Path]::GetFullPath($answer)
        $folder=Split-Path $full -Parent
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "Destination folder does not exist: $folder" }
        $coverage=[IO.Path]::Combine($folder,([IO.Path]::GetFileNameWithoutExtension($full)+'-Coverage.json'))
        foreach ($file in @($full)) {
            if ((Test-Path -LiteralPath $file) -and (Read-Host "Overwrite '$file'? [y/N]") -notmatch '^(?i)y(es)?$') { return $false }
        }
        $script:R3SaveChoice=@{Csv=$full;Coverage=$coverage;Folder=$folder}
    }
    else {
        $answer=([string](Read-Host 'Output directory for report files (blank cancels saving)')).Trim().Trim('"')
        if (-not $answer) { return $false }
        $folder=[IO.Path]::GetFullPath($answer)
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "Destination folder does not exist: $folder" }
        $script:R3SaveChoice=@{Folder=$folder;RunId=((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
    }
    return $true
}
function Get-R3ChosenOutputPath {
    param([string]$Label,[switch]$Coverage)
    if (-not $script:R3SaveChoice) { throw 'No report destination selected. Refusing automatic export.' }
    if ($script:R3SaveChoice.ContainsKey('Csv')) {
        if ($Coverage) { return $script:R3SaveChoice.Coverage }
        return $script:R3SaveChoice.Csv
    }
    $extension=if ($Coverage) {'.json'} else {'.csv'}
    $name=$Label+'-'+$script:R3SaveChoice.RunId+$extension
    $path=Join-Path $script:R3SaveChoice.Folder $name
    if (Test-Path -LiteralPath $path) { throw "Refusing unexpected existing output file: $path" }
    return $path
}
