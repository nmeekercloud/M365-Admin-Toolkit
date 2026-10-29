# Archive planning helpers. No connect/disconnect or tenant mutations here.
function Get-ODCurrentUser {
    param($Connection,[string]$ExpectedAccount)
    $ctx=Get-PnPContext -Connection $Connection -ErrorAction Stop
    $current=$ctx.Web.CurrentUser
    $ctx.Load($current); $ctx.ExecuteQuery()
    if ([string]$current.LoginName -notmatch ([regex]::Escape($ExpectedAccount)+'$')) { throw 'PnP source account differs from verified toolkit administrator.' }
    [pscustomobject]@{LoginName=[string]$current.LoginName;IsAdmin=[bool]$current.IsSiteAdmin}
}
function Get-ODInventory {
    param($Connection,[string]$LibraryId,[string]$Root)
    $rows=@(Get-PnPListItem -List $LibraryId -PageSize 500 -Fields 'FileRef','FileLeafRef','FSObjType','File_x0020_Size','Modified' -Connection $Connection -ErrorAction Stop)
    foreach ($row in $rows) {
        $path=[string]$row['FileRef']
        if (-not $path.StartsWith($Root.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative=$path.Substring($Root.TrimEnd('/').Length+1)
        if ($relative -eq 'Forms' -or $relative.StartsWith('Forms/',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $size=0L
        if ([int]$row['FSObjType'] -eq 0 -and $null -ne $row['File_x0020_Size']) { $size=[long]$row['File_x0020_Size'] }
        [pscustomobject]@{Path=$path;Relative=$relative;Folder=([int]$row['FSObjType'] -eq 1);Bytes=$size;Modified=[string]$row['Modified']}
    }
}
function Get-ODFingerprint {
    param([object[]]$Inventory)
    $text=(@($Inventory | Sort-Object Relative | ForEach-Object { $_.Relative+'|'+$_.Folder+'|'+$_.Bytes+'|'+$_.Modified }) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Read-ODValue {
    param([string]$Prompt)
    $value=([string](Read-Host ($Prompt+' (Enter cancels)'))).Trim()
    if (-not $value) { throw [OperationCanceledException]::new('Archive planning cancelled.') }
    $value
}
function Test-ODSameTenantUrl {
    param([string]$Url,[string]$Root,[switch]$OneDrive)
    $u=$null
    if (-not [uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'https' -or $u.Query -or $u.Fragment -or $u.UserInfo) { throw 'A plain HTTPS site URL is required.' }
    $hostName=([uri]$Root).Host
    if ($OneDrive) { $hostName=$hostName.Replace('.sharepoint.com','-my.sharepoint.com') }
    if ($u.Host -ine $hostName) { throw 'Site URL does not match the verified tenant host. Multi-geo/custom cloud hosts are not supported in this first integration.' }
}
function Get-ODLibrary {
    param($Connection,[string]$Id)
    Get-PnPList -Identity $Id -Includes RootFolder,BaseTemplate,Hidden -Connection $Connection -ErrorAction Stop
}
