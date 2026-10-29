function OD-Test-IsOneDriveShortcutFailure {

    param(
        [string]$Message
    )

    if (
        [string]::IsNullOrWhiteSpace(
            $Message
        )
    ) {

        return $false

    }

    return (
        $Message -match '(?i)shortcut' -or
        $Message -match '(?i)remote\s*item' -or
        $Message -match '(?i)linked\s*folder'
    )

}

function OD-Test-IsSkippedShortcutPath {

    param(
        [string]$ServerRelativeUrl
    )

    if (
        [string]::IsNullOrWhiteSpace(
            $ServerRelativeUrl
        )
    ) {

        return $false

    }

    $Match = $script:ODSkippedShortcuts |
        Where-Object {
            $_.SourceUrl -eq $ServerRelativeUrl
        } |
        Select-Object -First 1

    return ($null -ne $Match)

}

function OD-Register-MoveError {

    param(

        [string]$Type,

        [string]$Name,

        [string]$SourceUrl,

        [string]$ErrorMessage

    )

    if (
        OD-Test-IsOneDriveShortcutFailure `
            -Message $ErrorMessage
    ) {

        $AlreadyRecorded = $script:ODSkippedShortcuts |
            Where-Object {
                $_.SourceUrl -eq $SourceUrl
            } |
            Select-Object -First 1

        if (-not $AlreadyRecorded) {

            $script:ODSkippedShortcuts.Add(

                [PSCustomObject]@{
                    Type      = $Type
                    Name      = $Name
                    SourceUrl = $SourceUrl
                    Error     = $ErrorMessage
                }

            )

        }

        Write-Host `
            "SKIPPED SHORTCUT: $Name" `
            -ForegroundColor Yellow

        Write-Host `
            "OneDrive shortcuts are not moved to the SharePoint archive and are not treated as failures." `
            -ForegroundColor DarkGray

        return $true

    }

    $script:ODMoveFailures.Add(

        [PSCustomObject]@{
            Type  = $Type
            Name  = $Name
            Error = $ErrorMessage
        }

    )

    Write-Host `
        "FAILED: $Name" `
        -ForegroundColor Red

    Write-Host `
        $ErrorMessage `
        -ForegroundColor Red

    return $false

}

function OD-Test-FolderContainsOnlySkippedShortcuts {

    param(

        $Folder,

        $SourceConnection

    )

    if (
        OD-Test-IsSkippedShortcutPath `
            -ServerRelativeUrl $Folder.ServerRelativeUrl
    ) {

        return $true

    }

    try {

        $Files = @(

            Get-PnPFolderItem `
                -Identity $Folder `
                -ItemType File `
                -Connection $SourceConnection

        )

        $Folders = @(

            Get-PnPFolderItem `
                -Identity $Folder `
                -ItemType Folder `
                -Connection $SourceConnection

        )

    }
    catch {

        return $false

    }

    if (
        $Files.Count -eq 0 -and
        $Folders.Count -eq 0
    ) {

        return $false

    }

    foreach ($File in $Files) {

        if (
            -not (
                OD-Test-IsSkippedShortcutPath `
                    -ServerRelativeUrl $File.ServerRelativeUrl
            )
        ) {

            return $false

        }

    }

    foreach ($ChildFolder in $Folders) {

        if (
            OD-Test-IsSkippedShortcutPath `
                -ServerRelativeUrl $ChildFolder.ServerRelativeUrl
        ) {

            continue

        }

        if (
            -not (
                OD-Test-FolderContainsOnlySkippedShortcuts `
                    -Folder $ChildFolder `
                    -SourceConnection $SourceConnection
            )
        ) {

            return $false

        }

    }

    return $true

}

function OD-Convert-ToAbsoluteUrl {

    param(

        [string]$Authority,

        [string]$ServerRelativeUrl

    )

    $BaseUri = [Uri](
        $Authority.TrimEnd('/') + "/"
    )

    return (
        [Uri]::new(
            $BaseUri,
            $ServerRelativeUrl
        )
    ).AbsoluteUri

}

# ============================================================
# PnP App Functions
# ============================================================

function OD-Get-CopyJobErrors {

    param(
        $Progress
    )

    $Errors = `
        [System.Collections.Generic.List[string]]::new()

    foreach ($Log in @($Progress.Logs)) {

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Log
            )
        ) {

            continue

        }

        try {

            $Parsed = `
                $Log |
                ConvertFrom-Json

            if (
                $Parsed.Event -match
                '(?i)error|fatal|failed|failure'
            ) {

                $Message = `
                    $Parsed.Message

                if (-not $Message) {
                    $Message = $Log
                }

                $Errors.Add(
                    [string]$Message
                )

            }

        }
        catch {

            if (
                $Log -match
                '(?i)"Event"\s*:\s*"[^"]*(error|fatal|failed|failure)'
            ) {

                $Errors.Add(
                    [string]$Log
                )

            }

        }

    }

    return $Errors

}

function OD-Invoke-SharePointMoveJob {

    param(

        [string]$SourceAbsoluteUrl,

        [string]$DestinationAbsoluteUrl,

        [int]$ConflictBehavior,

        $SourceConnection,

        [string]$DisplayName = "SharePoint item"

    )

    if ($script:ODJobUncertain) { throw 'An earlier archive job is uncertain. No further job submitted.' }

    $Context = Get-PnPContext `
        -Connection $SourceConnection

    $Options = New-Object `
        Microsoft.SharePoint.Client.CopyMigrationOptions

    $Options.IsMoveMode = $true

    $Options.IgnoreVersionHistory = $false

    $Options.AllowSchemaMismatch = $true

    $Options.NameConflictBehavior = `
        $ConflictBehavior

    # Do not allow SharePoint to silently discard versions simply
    # because the destination version limit is smaller.

    if (
        $Options.PSObject.Properties.Name -contains
        "AllowSmallerVersionLimitOnDestination"
    ) {

        $Options.AllowSmallerVersionLimitOnDestination = `
            $false

    }

    $SourceArray = [string[]]@(
        $SourceAbsoluteUrl
    )

    $Jobs = $Context.Site.CreateCopyJobs(
        $SourceArray,
        $DestinationAbsoluteUrl.TrimEnd('/'),
        $Options
    )

    $script:ODJobUncertain = $true
    $Context.ExecuteQuery()

    if (
        -not $Jobs -or
        $Jobs.Count -eq 0
    ) {

        throw `
            "SharePoint did not return a move job."

    }

    $Job = $Jobs[0]
    $script:ODActiveJob = $Job
    $script:ODActiveConnection = $SourceConnection

    $JobStart = Get-Date

    $LastHeartbeat = $JobStart

    $LastState = $null

    # There is intentionally no timeout here. Large OneDrive / SharePoint
    # move jobs can run for hours. The script will continue polling until
    # SharePoint reports that the job has finished or returns an actual error.

    while ($true) {

        $ProgressResult = `
            $Context.Site.GetCopyJobProgress(
                $Job
            )

        $Context.ExecuteQuery()

        $Progress = `
            $ProgressResult.Value

        $LastState = `
            $Progress.JobState

        if ($Progress.JobState -eq 0) {
            $script:ODJobUncertain = $false
            break
        }

        $Now = Get-Date

        $Elapsed = `
            $Now - $JobStart

        if ($Elapsed.TotalDays -ge 1) {

            $ElapsedText = `
                (
                    "{0}d {1:00}:{2:00}:{3:00}" -f `
                    [math]::Floor($Elapsed.TotalDays),
                    $Elapsed.Hours,
                    $Elapsed.Minutes,
                    $Elapsed.Seconds
                )

        }
        else {

            $ElapsedText = `
                (
                    "{0:00}:{1:00}:{2:00}" -f `
                    [math]::Floor($Elapsed.TotalHours),
                    $Elapsed.Minutes,
                    $Elapsed.Seconds
                )

        }

        Write-Progress `
            -Id 2 `
            -Activity "Current SharePoint move job" `
            -Status "$DisplayName | Elapsed: $ElapsedText | SharePoint job is still running..." `
            -PercentComplete -1

        # Write a heartbeat to the console/transcript every five minutes so
        # overnight jobs have a clear record showing that they were still alive.
        if (
            ($Now - $LastHeartbeat).TotalMinutes -ge 5
        ) {

            Write-Host `
                "[$($Now.ToString('yyyy-MM-dd HH:mm:ss'))] Still moving: $DisplayName (elapsed $ElapsedText)" `
                -ForegroundColor DarkGray

            $LastHeartbeat = $Now

        }

        Start-Sleep `
            -Seconds 3

    }

    Write-Progress `
        -Id 2 `
        -Activity "Current SharePoint move job" `
        -Completed

    $Errors = @(
        OD-Get-CopyJobErrors `
            -Progress $Progress
    )

    if ($Errors.Count -gt 0) {

        throw (
            $Errors -join " | "
        )

    }

    return $Progress

}

function OD-Test-SourceItemExists {

    param(

        [string]$Type,

        [string]$ServerRelativeUrl,

        $SourceConnection

    )

    try {

        if ($Type -eq "Folder") {

            $null = Get-PnPFolder `
                -Url $ServerRelativeUrl `
                -Connection $SourceConnection `
                -ErrorAction Stop

        }
        else {

            $null = Get-PnPFile `
                -Url $ServerRelativeUrl `
                -Connection $SourceConnection `
                -ErrorAction Stop

        }

        return $true

    }
    catch {
        if ($_.Exception.Message -match '(?i)file not found|folder not found|does not exist|404|0x80070002') { return $false }
        throw
    }

}

function OD-Wait-ForSourceRemoval {

    param(

        [string]$Type,

        [string]$ServerRelativeUrl,

        $SourceConnection

    )

    for (
        $i = 1;
        $i -le 20;
        $i++
    ) {

        if (
            -not (
                OD-Test-SourceItemExists `
                    -Type $Type `
                    -ServerRelativeUrl $ServerRelativeUrl `
                    -SourceConnection $SourceConnection
            )
        ) {

            return $true

        }

        Start-Sleep `
            -Seconds 3

    }

    return $false

}

function OD-Test-DestinationFolderExists {

    param(

        [string]$ServerRelativeUrl,

        $DestinationConnection

    )

    try {

        $Folder = Get-PnPFolder `
            -Url $ServerRelativeUrl `
            -Connection $DestinationConnection `
            -ErrorAction Stop

        return $Folder

    }
    catch {
        if ($_.Exception.Message -match '(?i)file not found|folder not found|does not exist|404|0x80070002') { return $null }
        throw
    }

}

function OD-Move-SingleSourceItem {

    param(

        [string]$Type,

        [string]$Name,

        [string]$SourceServerRelativeUrl,

        [string]$DestinationParentServerRelativeUrl,

        [int]$ConflictBehavior,

        [string]$SourceAuthority,

        [string]$DestinationAuthority,

        $SourceConnection

    )

    $SourceAbsoluteUrl = OD-Convert-ToAbsoluteUrl `
        -Authority $SourceAuthority `
        -ServerRelativeUrl $SourceServerRelativeUrl

    $DestinationAbsoluteUrl = OD-Convert-ToAbsoluteUrl `
        -Authority $DestinationAuthority `
        -ServerRelativeUrl $DestinationParentServerRelativeUrl

    Write-Host ""

    Write-Host `
        "Moving $($Type.ToLower()): $Name" `
        -ForegroundColor White

    OD-Invoke-SharePointMoveJob `
        -SourceAbsoluteUrl $SourceAbsoluteUrl `
        -DestinationAbsoluteUrl $DestinationAbsoluteUrl `
        -ConflictBehavior $ConflictBehavior `
        -SourceConnection $SourceConnection `
        -DisplayName ("{0}: {1}" -f $Type, $Name) |
        Out-Null

    $Removed = OD-Wait-ForSourceRemoval `
        -Type $Type `
        -ServerRelativeUrl $SourceServerRelativeUrl `
        -SourceConnection $SourceConnection

    if (-not $Removed) {

        throw `
            "SharePoint reported the move job complete, but the source item still exists."

    }

    $script:ODMovedOperations++

    Write-Host `
        "Moved successfully: $Name" `
        -ForegroundColor Green

}

function OD-Move-FolderWithMerge {

    param(

        $SourceFolder,

        [string]$SourceParentServerRelativeUrl,

        [string]$DestinationParentServerRelativeUrl,

        [int]$ConflictBehavior,

        [string]$SourceAuthority,

        [string]$DestinationAuthority,

        $SourceConnection,

        $DestinationConnection

    )

    $FolderName = `
        $SourceFolder.Name

    $DestinationFolderServerRelativeUrl = `
        "$($DestinationParentServerRelativeUrl.TrimEnd('/'))/$FolderName"

    $ExistingDestinationFolder = `
        OD-Test-DestinationFolderExists `
            -ServerRelativeUrl $DestinationFolderServerRelativeUrl `
            -DestinationConnection $DestinationConnection

    # ========================================================
    # If we are NOT in overwrite mode, or if no destination
    # folder exists, let SharePoint move the entire folder.
    # ========================================================

    if (
        $ConflictBehavior -ne 1 -or
        -not $ExistingDestinationFolder
    ) {

        try {

            OD-Move-SingleSourceItem `
                -Type "Folder" `
                -Name $FolderName `
                -SourceServerRelativeUrl $SourceFolder.ServerRelativeUrl `
                -DestinationParentServerRelativeUrl $DestinationParentServerRelativeUrl `
                -ConflictBehavior $ConflictBehavior `
                -SourceAuthority $SourceAuthority `
                -DestinationAuthority $DestinationAuthority `
                -SourceConnection $SourceConnection

        }
        catch {

            $null = OD-Register-MoveError `
                -Type "Folder" `
                -Name $FolderName `
                -SourceUrl $SourceFolder.ServerRelativeUrl `
                -ErrorMessage $_.Exception.Message

        }

        return

    }

    # ========================================================
    # OVERWRITE MODE + destination folder already exists.
    #
    # Merge into that folder instead of attempting to replace
    # the entire destination folder.
    # ========================================================

    Write-Host ""

    Write-Host `
        "Destination folder already exists. Merging: $FolderName" `
        -ForegroundColor Yellow

    $SourceFiles = @(

        Get-PnPFolderItem `
            -Identity $SourceFolder `
            -ItemType File `
            -Connection $SourceConnection

    )

    $SourceFolders = @(

        Get-PnPFolderItem `
            -Identity $SourceFolder `
            -ItemType Folder `
            -Connection $SourceConnection

    )

    # --------------------------------------------------------
    # Move files first
    # --------------------------------------------------------

    foreach ($File in $SourceFiles) {

        try {

            OD-Move-SingleSourceItem `
                -Type "File" `
                -Name $File.Name `
                -SourceServerRelativeUrl $File.ServerRelativeUrl `
                -DestinationParentServerRelativeUrl $DestinationFolderServerRelativeUrl `
                -ConflictBehavior 1 `
                -SourceAuthority $SourceAuthority `
                -DestinationAuthority $DestinationAuthority `
                -SourceConnection $SourceConnection

        }
        catch {

            $null = OD-Register-MoveError `
                -Type "File" `
                -Name $File.Name `
                -SourceUrl $File.ServerRelativeUrl `
                -ErrorMessage $_.Exception.Message

        }

    }

    # --------------------------------------------------------
    # Process child folders
    # --------------------------------------------------------

    foreach ($ChildFolder in $SourceFolders) {

        OD-Move-FolderWithMerge `
            -SourceFolder $ChildFolder `
            -SourceParentServerRelativeUrl $SourceFolder.ServerRelativeUrl `
            -DestinationParentServerRelativeUrl $DestinationFolderServerRelativeUrl `
            -ConflictBehavior 1 `
            -SourceAuthority $SourceAuthority `
            -DestinationAuthority $DestinationAuthority `
            -SourceConnection $SourceConnection `
            -DestinationConnection $DestinationConnection

    }

    # --------------------------------------------------------
    # Check whether source folder is now empty
    # --------------------------------------------------------

    $RemainingFiles = @(

        Get-PnPFolderItem `
            -Identity $SourceFolder `
            -ItemType File `
            -Connection $SourceConnection

    )

    $RemainingFolders = @(

        Get-PnPFolderItem `
            -Identity $SourceFolder `
            -ItemType Folder `
            -Connection $SourceConnection

    )

    if (
        $RemainingFiles.Count -eq 0 -and
        $RemainingFolders.Count -eq 0
    ) {

        try {

            Remove-PnPFolder `
                -Name $FolderName `
                -Folder $SourceParentServerRelativeUrl `
                -Recycle `
                -Force `
                -Connection $SourceConnection

            Write-Host `
                "Source folder empty and removed: $FolderName" `
                -ForegroundColor Green

        }
        catch {

            $script:ODMoveFailures.Add(

                [PSCustomObject]@{
                    Type  = "Folder Cleanup"
                    Name  = $SourceFolder.ServerRelativeUrl
                    Error = $_.Exception.Message
                }

            )

        }

    }
    else {

        $OnlySkippedShortcuts = `
            OD-Test-FolderContainsOnlySkippedShortcuts `
                -Folder $SourceFolder `
                -SourceConnection $SourceConnection

        if ($OnlySkippedShortcuts) {

            Write-Host `
                "Folder left in OneDrive because it contains only skipped shortcut(s): $FolderName" `
                -ForegroundColor Yellow

        }
        else {

            $script:ODMoveFailures.Add(

                [PSCustomObject]@{
                    Type  = "Folder"
                    Name  = $SourceFolder.ServerRelativeUrl
                    Error = "One or more non-shortcut child items failed to move, so the source folder was left in place."
                }

            )

            Write-Host `
                "Folder still contains item(s) that need attention: $FolderName" `
                -ForegroundColor Yellow

        }

    }

}

