<#
.SYNOPSIS
    Launches the Microsoft 365 Admin Toolkit interactive menu.

.DESCRIPTION
    Start here. The launcher:
      1. Makes sure it is running in PowerShell 7.6+ (relaunches in pwsh, or offers
         to install / update PowerShell 7 with WinGet if needed).
      2. Loads the M365Toolkit.Core module.
      3. Checks required modules and offers to install missing ones.
      4. Shows the main menu.

    IMPORTANT: The bootstrap section of this file must stay compatible with
    Windows PowerShell 5.1 so it can relaunch itself in PowerShell 7. Do not use
    PowerShell 7-only syntax (?:, ??, &&, ||, etc.) anywhere in this file.

.PARAMETER TenantDomain
    Select this tenant for the next task; startup does not sign in.

.PARAMETER SkipDependencyCheck
    Skip the module check at startup (faster when you know everything is installed).

.PARAMETER UseDeviceCode
    Use device code sign-in for all connections in this session.

.EXAMPLE
    .\Start-M365Toolkit.ps1

.EXAMPLE
    .\Start-M365Toolkit.ps1 -TenantDomain contoso.onmicrosoft.com
#>
[CmdletBinding()]
param(
    [Parameter()] [string] $TenantDomain,
    [Parameter()] [switch] $SkipDependencyCheck,
    [Parameter()] [switch] $UseDeviceCode
)

# =============================================================================
# region PowerShell 7 bootstrap (Windows PowerShell 5.1 compatible)
# =============================================================================

$ToolkitRoot = $PSScriptRoot
# Once this launcher is trusted and allowed to run, unblock its PowerShell files.
try {
    Get-ChildItem -LiteralPath $ToolkitRoot -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') } |
        ForEach-Object {
            Unblock-File -LiteralPath $_.FullName -ErrorAction Stop
        }
}
catch {
    Write-Host ''
    Write-Host ("Could not unblock toolkit files: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Unblock this trusted toolkit folder manually before continuing.'
    Read-Host 'Press Enter to exit' | Out-Null
    exit 1
}
$SettingsPath = Join-Path -Path $ToolkitRoot -ChildPath 'Config\Toolkit.Settings.psd1'
$MinimumPowerShellVersion = [version]'7.6.0'
try {
    $bootSettings = Import-PowerShellDataFile -Path $SettingsPath
    if ($bootSettings.ContainsKey('MinimumPowerShellVersion')) {
        $MinimumPowerShellVersion = [version]$bootSettings['MinimumPowerShellVersion']
    }
}
catch {
    Write-Host "Could not read $SettingsPath. Using minimum PowerShell $MinimumPowerShellVersion." -ForegroundColor Yellow
}

function Get-PowerShell7Info {
    <# Finds the newest stable PowerShell 7 in PATH and standard install locations. #>

    $candidates = @()

    $commands = @(Get-Command -Name 'pwsh.exe' -All -ErrorAction SilentlyContinue)
    foreach ($command in $commands) {
        if ($command.Source) {
            $candidates += $command.Source
        }
    }

    $programRoots = @(
        $env:ProgramW6432
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
    )

    foreach ($programRoot in ($programRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $candidates += Join-Path -Path $programRoot -ChildPath 'PowerShell\7\pwsh.exe'
    }

    $best = $null

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                continue
            }

            $versionText = & $candidate -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
            $probeExitCode = $LASTEXITCODE

            if ($probeExitCode -ne 0) {
                continue
            }

            $versionLine = $versionText | Select-Object -First 1
            if (-not $versionLine) {
                continue
            }

            $versionLine = ([string]$versionLine).Trim()

            if ($versionLine -match '-') {
                continue
            }

            $version = [version]$versionLine
            if ($version.Major -lt 7) {
                continue
            }

            if (-not $best -or $version -gt $best.Version) {
                $best = [pscustomobject]@{
                    Path    = $candidate
                    Version = $version
                }
            }
        }
        catch {
            Write-Verbose ("Could not read PowerShell version from '{0}': {1}" -f $candidate, $_.Exception.Message)
        }
    }

    return $best
}

function Get-WinGetPath {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($env:LOCALAPPDATA) {
        $path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Invoke-PowerShell7Relaunch {
    param([Parameter(Mandatory = $true)] [string] $PowerShellPath)

    if (-not $PSCommandPath) {
        Write-Host 'Run Start-M365Toolkit.ps1 as a saved file.' -ForegroundColor Red
        exit 1
    }

    $arguments = @('-NoLogo', '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($TenantDomain) { $arguments += @('-TenantDomain', $TenantDomain) }
    if ($SkipDependencyCheck) { $arguments += '-SkipDependencyCheck' }
    if ($UseDeviceCode) { $arguments += '-UseDeviceCode' }

        Write-Host ''
    Write-Host 'POWERSHELL 7 RELAUNCH REQUIRED' -ForegroundColor Yellow
    Write-Host ("Current PowerShell version: {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("Starting a new PowerShell 7 window using: {0}" -f $PowerShellPath)
    Write-Host ''
    Write-Host 'Continue working in the new PowerShell 7 window.' -ForegroundColor Cyan
    Write-Host 'No Microsoft 365 task changes have been performed by this relaunch.'
    Write-Host ''

    try {
        $null = Start-Process -FilePath $PowerShellPath `
            -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
            -ArgumentList $arguments `
            -PassThru `
            -ErrorAction Stop
    }
    catch {
        Write-Host ("Could not start PowerShell 7: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Read-Host 'Press Enter to exit' | Out-Null
        exit 1
    }

    Read-Host 'PowerShell 7 launch requested. Press Enter to close this original session' | Out-Null
    exit 0
}
function Invoke-ToolkitPowerShellUpgrade {
    param(
        [Parameter(Mandatory = $true)]
        [string] $WinGetPath
    )

    if (-not $PSCommandPath) {
        throw 'Run Start-M365Toolkit.ps1 as a saved file.'
    }

    # Use native Windows PowerShell, including when launched from x86 PowerShell.
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $windowsPowerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }

    if (-not (Test-Path -LiteralPath $windowsPowerShell)) {
        throw "Windows PowerShell was not found: $windowsPowerShell"
    }

    $payload = @{
        ParentProcessId = $PID
        ScriptPath      = $PSCommandPath
        MinimumVersion  = $MinimumPowerShellVersion.ToString()
        WinGetPath      = $WinGetPath
        TenantDomain    = $TenantDomain
        SkipDependencies = [bool]$SkipDependencyCheck
        UseDeviceCode   = [bool]$UseDeviceCode
    }

    $payloadJson = ConvertTo-Json -InputObject $payload -Compress
    $payloadBase64 = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($payloadJson)
    )

    # Reuse the same discovery function inside the independent helper.
    $discoveryFunction = "function Get-PowerShell7Info {`r`n" +
        ${function:Get-PowerShell7Info}.ToString() +
        "`r`n}`r`n"

    $helperBody = {
        $ErrorActionPreference = 'Stop'

        try {
            $payload = ConvertFrom-Json -InputObject (
                [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String($payloadBase64)
                )
            )

            $minimumVersion = [version]$payload.MinimumVersion

            Write-Host ''
            Write-Host 'POWERSHELL UPGRADE HELPER' -ForegroundColor Cyan
            Write-Host 'Waiting for the original toolkit process to exit...'

            $parent = Get-Process -Id ([int]$payload.ParentProcessId) -ErrorAction SilentlyContinue
            if ($parent) {
                Wait-Process -Id $parent.Id -Timeout 120 -ErrorAction Stop
            }

            $pwsh = Get-PowerShell7Info

            if (-not $pwsh -or $pwsh.Version -lt $minimumVersion) {
                $verb = 'install'
                if ($pwsh) {
                    $verb = 'upgrade'
                }

                Write-Host ''
                Write-Host ("Running WinGet {0} for Microsoft.PowerShell..." -f $verb) -ForegroundColor Cyan

                $wingetArguments = @(
                    $verb
                    '--id', 'Microsoft.PowerShell'
                    '--exact'
                    '--source', 'winget'
                    '--accept-source-agreements'
                    '--accept-package-agreements'
                )

                $wingetExecutable = [string]$payload.WinGetPath
                & $wingetExecutable @wingetArguments
                $wingetExitCode = $LASTEXITCODE

                # Verify the runtime rather than assuming WinGet succeeded.
                $pwsh = Get-PowerShell7Info

                if (-not $pwsh -or $pwsh.Version -lt $minimumVersion) {
                    if ($wingetExitCode -ne 0) {
                        throw (
                            'WinGet returned exit code {0}. PowerShell {1}+ could not be verified. Review the WinGet output above.' -f
                            $wingetExitCode, $minimumVersion
                        )
                    }

                    for ($attempt = 1; $attempt -le 15; $attempt++) {
                        Start-Sleep -Seconds 2
                        $pwsh = Get-PowerShell7Info

                        if ($pwsh -and $pwsh.Version -ge $minimumVersion) {
                            break
                        }
                    }
                }

                if (-not $pwsh -or $pwsh.Version -lt $minimumVersion) {
                    throw (
                        'WinGet completed, but PowerShell {0}+ could not be verified. A restart or manual installation check may be required.' -f
                        $minimumVersion
                    )
                }
            }

            $scriptPath = [string]$payload.ScriptPath

            $toolkitArguments = @(
                '-NoLogo'
                '-NoProfile'
                '-NoExit'
                '-ExecutionPolicy', 'Bypass'
                '-File', ('"{0}"' -f $scriptPath)
            )

            if ($payload.TenantDomain) {
                $toolkitArguments += @(
                    '-TenantDomain', ('"{0}"' -f $payload.TenantDomain)
                )
            }

            if ($payload.SkipDependencies) {
                $toolkitArguments += '-SkipDependencyCheck'
            }

            if ($payload.UseDeviceCode) {
                $toolkitArguments += '-UseDeviceCode'
            }

            Write-Host ''
            Write-Host ("PowerShell {0} verified: {1}" -f $pwsh.Version, $pwsh.Path) -ForegroundColor Green
            Write-Host 'Opening the toolkit in an elevated PowerShell 7 window...' -ForegroundColor Cyan

            $null = Start-Process -FilePath $pwsh.Path `
                -WorkingDirectory (Split-Path -Parent $scriptPath) `
                -ArgumentList $toolkitArguments `
                -Verb RunAs `
                -PassThru `
                -ErrorAction Stop
        }
        catch {
            Write-Host ''
            Write-Host ("PowerShell upgrade/relaunch failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
            Write-Host 'The toolkit has not continued into Microsoft 365 tasks.'
            Read-Host 'Press Enter to close this helper' | Out-Null
            exit 1
        }

        exit 0
    }

    $helperCode = "`$payloadBase64 = '$payloadBase64'`r`n"
    $helperCode += $discoveryFunction
    $helperCode += $helperBody.ToString()

    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($helperCode)
    )

    Write-Host ''
    Write-Host 'A Windows PowerShell upgrade helper will open as administrator.' -ForegroundColor Yellow
    Write-Host 'Approve the Windows UAC prompt if one appears.'
    Write-Host 'This original PowerShell session will exit so the helper can proceed.'
    Write-Host 'After a successful upgrade, the toolkit will reopen in PowerShell 7.'
    Write-Host ''

    try {
        $null = Start-Process -FilePath $windowsPowerShell `
            -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
            -ArgumentList @(
                '-NoLogo'
                '-NoProfile'
                '-ExecutionPolicy', 'Bypass'
                '-EncodedCommand', $encodedCommand
            ) `
            -Verb RunAs `
            -PassThru `
            -ErrorAction Stop
    }
    catch {
        Write-Host ("Could not start the upgrade helper: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Read-Host 'Press Enter to exit' | Out-Null
        exit 1
    }

    exit 0
}
# --- Windows only --------------------------------------------------------
$runningOnWindows = $true
if ($PSVersionTable.PSVersion.Major -ge 6) { $runningOnWindows = [bool]$IsWindows }
if (-not $runningOnWindows) {
    Write-Host 'The Microsoft 365 Admin Toolkit supports Windows only.' -ForegroundColor Red
    exit 1
}

# Require an x64 process before loading toolkit modules or connecting.
$currentArchitecture = [string](
    [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
)

if ($currentArchitecture -ne 'X64') {
    Write-Host ''
    Write-Host 'POWERSHELL X64 REQUIRED' -ForegroundColor Yellow
    Write-Host ("Current process architecture: {0}" -f $currentArchitecture)
    Write-Host ''
    Write-Host 'This toolkit must run in an x64 PowerShell process.'
    Write-Host 'Open PowerShell 7 without the "(x86)" label, then run the toolkit again.'
    Write-Host 'No Microsoft 365 task changes have been performed.'
    Read-Host 'Press Enter to exit' | Out-Null
    exit 1
}

# --- PowerShell version gate --------------------------------------------
if ($PSVersionTable.PSVersion.Major -ge 6) {
    # PowerShell 7: SemanticVersion (Major.Minor.Patch)
    $currentVersion = [version]('{0}.{1}.{2}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor, $PSVersionTable.PSVersion.Patch)
}
else {
    # Windows PowerShell 5.1: System.Version (Major.Minor.Build.Revision)
    $currentVersion = [version]('{0}.{1}.{2}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor, [Math]::Max(0, $PSVersionTable.PSVersion.Build))
}

if ($currentVersion -lt $MinimumPowerShellVersion) {
    Write-Host ''
    Write-Host ("The toolkit requires PowerShell {0} or later." -f $MinimumPowerShellVersion) -ForegroundColor Yellow
    Write-Host ("Current version: {0}" -f $PSVersionTable.PSVersion)

    $pwsh = Get-PowerShell7Info

    if ($pwsh -and $pwsh.Version -ge $MinimumPowerShellVersion) {
        Write-Host ''
        Write-Host ("PowerShell {0} found: {1}" -f $pwsh.Version, $pwsh.Path) -ForegroundColor Green
        Invoke-PowerShell7Relaunch -PowerShellPath $pwsh.Path
        exit 0
    }

    Write-Host ''
    $install = Read-Host (
        "PowerShell $MinimumPowerShellVersion+ is missing or outdated. Install/update using an elevated Windows PowerShell helper? [y/N]"
    )

    if ($install -notmatch '^(?i)(y|yes)$') {
        exit 1
    }

    $winget = Get-WinGetPath

    if (-not $winget) {
        Write-Host 'WinGet was not found. Install PowerShell 7 manually, then run the toolkit again.' -ForegroundColor Red
        Read-Host 'Press Enter to exit' | Out-Null
        exit 1
    }

    Invoke-ToolkitPowerShellUpgrade -WinGetPath $winget
}

# endregion
# =============================================================================
# From here on we are in PowerShell 7.6+.
# =============================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0


$corePath = Join-Path -Path $ToolkitRoot -ChildPath 'Modules\M365Toolkit.Core\M365Toolkit.Core.psd1'
try {
    Import-Module -Name $corePath -Force -ErrorAction Stop
}
catch {
    Write-Host "Failed to load the toolkit core module: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If you downloaded the toolkit as a ZIP, run: Get-ChildItem -Path '$ToolkitRoot' -Recurse | Unblock-File" -ForegroundColor Yellow
    exit 1
}

$core      = Get-Module -Name 'M365Toolkit.Core'
if ($UseDeviceCode) {
    & $core { $script:Settings.Authentication.UseDeviceCode = $true }
}
$version   = $core.Version.ToString()
$lineWidth = 45

# Activity logs are automatic in the standard toolkit data folder; report exports remain optional.
Set-M365FileLogging -NoInteractive

# Legacy automatic log cleanup is disabled (function retained for compatibility).
& $core { Remove-ToolkitExpiredLog }

Write-M365Log -Message ("Toolkit {0} started. PowerShell {1} on {2} by {3}." -f $version, $PSVersionTable.PSVersion, $env:COMPUTERNAME, $env:USERNAME) -Level Info -Quiet

# =============================================================================
# region Menu helpers
# =============================================================================

function Write-TenantBanner {
    $info = Get-M365TenantInfo
    Write-Host "Version: $version"
    if (-not $info) {
        Write-Host 'Tenant: ' -NoNewline
        Write-Host 'Not Connected' -ForegroundColor Yellow
        return
    }

    Write-Host 'Tenant: ' -NoNewline
    Write-Host ("{0} ({1})" -f $info.TenantName, $info.InitialDomain) -ForegroundColor Green
    Write-Host ("Account: {0}" -f $info.Account) -ForegroundColor DarkGray

    $status = @(Get-M365ConnectionStatus)
    Write-Host 'Services: ' -NoNewline
    foreach ($s in $status) {
        $label = switch ($s.Service) { 'Graph' { 'Graph' } 'ExchangeOnline' { 'Exchange' } default { 'SharePoint' } }
        if (-not $s.Connected) {
            Write-Host "$label [--]  " -NoNewline -ForegroundColor DarkGray
        }
        elseif ($s.TenantMatch -eq $false) {
            Write-Host "$label [WRONG TENANT]  " -NoNewline -ForegroundColor Red
        }
        else {
            Write-Host "$label [ON]  " -NoNewline -ForegroundColor Green
        }
    }
    Write-Host ''
}

. (Join-Path $ToolkitRoot 'Tools/Toolkit.Catalog.ps1')
. (Join-Path $ToolkitRoot 'Tools/Toolkit.NumericMenus.ps1')
. (Join-Path $ToolkitRoot 'Tools/Toolkit.ConnectionProfiles.ps1')
. (Join-Path $ToolkitRoot 'Tools/Toolkit.Exit.ps1')
$catalog=@(Get-ToolkitCatalog -Root $ToolkitRoot)

function Invoke-ToolkitToolsMenu {
    while ($true) {
        Show-M365Header -Title 'TOOLKIT TOOLS'
        Write-Host '[1] Refresh Menus'
        Write-Host '[2] Check / Install Dependencies'
        Write-Host '[3] Open Log Folder'
        Write-Host '[4] Validate Categories and Tasks'
        Write-Host '[5] Create New Category'
        Write-Host '[6] Create New Task'
        Write-Host '[7] Tenant / Connection Options'
        Write-Host '[8] Show Authentication Diagnostics'
        Write-Host '[0] Back'
        $choice=Read-M365Choice -Prompt 'Select an option' -Valid @('0','1','2','3','4','5','6','7','8')
        try {
            switch ($choice) {
                '0' { return }
                '7' { $null=Select-ToolkitConnectionProfile }
                '8' { & (Join-Path $ToolkitRoot 'Tools/Show-ToolkitAuthDiagnostics.ps1') -ToolkitPath $ToolkitRoot }
                '1' {
                    $updated=@(Get-ToolkitCatalog -Root $ToolkitRoot)
                    Set-Variable -Name catalog -Value $updated -Scope Script
                    $script:ToolkitProfilePrepared=$false
                    Write-Host 'Menus refreshed.' -ForegroundColor Green
                }
                '2' { $null=Install-M365Dependencies -IncludeOptional }
                '3' { Invoke-Item -LiteralPath (Get-M365LogPath -Folder) }
                '4' { & (Join-Path $ToolkitRoot 'Tools/Test-ToolkitCatalog.ps1') -ToolkitPath $ToolkitRoot }
                '5' {
                    $folder=([string](Read-Host 'Folder name (blank to cancel)')).Trim()
                    if (-not $folder) { continue }
                    $id=([string](Read-Host 'Category ID (lowercase, e.g. custom)')).Trim()
                    $name=([string](Read-Host 'Display name')).Trim()
                    & (Join-Path $ToolkitRoot 'Tools/New-ToolkitCategory.ps1') -Folder $folder -Id $id -Name $name -ToolkitPath $ToolkitRoot
                    $updated=@(Get-ToolkitCatalog -Root $ToolkitRoot)
                    Set-Variable -Name catalog -Value $updated -Scope Script
                    $script:ToolkitProfilePrepared=$false
                }
                '6' {
                    & (Join-Path $ToolkitRoot 'Tools/New-ToolkitTask.ps1') -ToolkitPath $ToolkitRoot
                    $updated=@(Get-ToolkitCatalog -Root $ToolkitRoot)
                    Set-Variable -Name catalog -Value $updated -Scope Script
                    $script:ToolkitProfilePrepared=$false
                }
            }
        }
        catch { Write-M365Log -Message $_.Exception.Message -Level Error }
        Wait-M365KeyPress
    }
}

function Invoke-CategoryMenu {
    param([Parameter(Mandatory)] $Category)
    if ($Category.PSObject.Properties['SubCategories']) {
        Invoke-ToolkitSubcategoryMenu -Category $Category
        return
    }
    $page=0
    while ($true) {
        Show-M365Header -Title $Category.Name.ToUpperInvariant()
        $tasks=@($Category.Tasks)
        $entries=@(Get-ToolkitTaskPageEntries -Tasks $tasks -Page $page)
        $pages=[Math]::Max(1,[int][Math]::Ceiling($tasks.Count/8.0))
        Write-Host ('Page {0} of {1}' -f ($page+1),$pages) -ForegroundColor DarkGray
        foreach ($entry in $entries) {
            if ($entry.Action -eq 'Task') {
                if ($entry.Task.Status -eq 'Ready') { Write-Host ('[{0}] {1}' -f $entry.Key,$entry.Label) }
                else { Write-Host ('[{0}] {1} [{2}]' -f $entry.Key,$entry.Label,$entry.Task.Status) -ForegroundColor DarkGray }
                Write-Host ('    '+$entry.Task.Description) -ForegroundColor DarkGray
            }
            else { Write-Host ('[{0}] {1}' -f $entry.Key,$entry.Label) }
        }
        Write-Host '[0] Back'
        $choice=Read-M365Choice -Prompt 'Select an option' -Valid (@('0')+@($entries.Key))
        if ($choice -eq '0') { return }
        $entry=@($entries | Where-Object Key -eq $choice)[0]
        if ($entry.Action -eq 'Next') { $page++; continue }
        if ($entry.Action -eq 'Previous') { $page--; continue }
        if ($entry.Task.Status -ne 'Ready') {
            Write-Host 'This task is not available yet.' -ForegroundColor Yellow
            Wait-M365KeyPress
            continue
        }
        try {
            Invoke-ToolkitPreparedTask -Task $entry.Task
        }
        catch { Write-M365Log -Message ('Task '+$entry.Task.Id+' failed: '+$_.Exception.Message) -Level Error }
        Wait-M365KeyPress
    }
}

if (-not $SkipDependencyCheck) {
    Show-M365Header -Title 'STARTUP DEPENDENCY CHECK'
    Write-Host 'Checking required PowerShell modules...' -ForegroundColor Cyan

    $issues = @(Test-M365Dependencies | Where-Object { $_.Status -ne 'OK' })
    if ($issues.Count -gt 0) {
        Write-Host ('Found {0} dependency issue(s). Reviewing installation options...' -f $issues.Count) -ForegroundColor Yellow
        $null = Install-M365Dependencies
        Wait-M365KeyPress
    }
    else {
        Write-M365Log -Message 'Dependency check passed: all required modules are installed and meet the configured version requirements.' -Level Success
        Start-Sleep -Milliseconds 750
    }
}
$null=Initialize-ToolkitConnectionProfile -Mode OnDemand -TargetTenant $TenantDomain
$running=$true; $disconnectBlocked=$false
while ($running) {
    Show-M365Header
    Write-TenantBanner
    $profileState='task-first; connect only when required'
    Write-Host ('Mode: '+$script:ToolkitConnectionMode+' - '+$profileState) -ForegroundColor Cyan
    if (-not (Get-M365TenantInfo) -and $script:ToolkitPreferredTenant) {
        Write-Host ('Selected tenant: '+$script:ToolkitPreferredTenant+' (not connected)') -ForegroundColor DarkGray
    }
    Write-Host ''
    $entries=@(Get-ToolkitMainMenuEntries -Catalog $catalog)
    Write-Host 'ADMINISTRATION' -ForegroundColor Cyan
    foreach ($entry in @($entries | Where-Object Action -eq 'Category')) { Write-Host ('[{0,2}] {1}' -f $entry.Key,$entry.Label) }
    Write-Host ''
    Write-Host 'CONNECTION & TOOLS' -ForegroundColor Cyan
    foreach ($entry in @($entries | Where-Object Action -ne 'Category')) { Write-Host ('[{0,2}] {1}' -f $entry.Key,$entry.Label) }
    Write-Host ' [0] Exit'
    try { $choice=Read-M365Choice -Prompt 'Select an option' -Valid (@('0')+@($entries.Key)) }
    catch { Write-Host $_.Exception.Message -ForegroundColor Yellow; break }
    try {
        if ($choice -eq '0') {
            try { $null=Invoke-ToolkitExitCleanup }
            finally { $running=$false }
            continue
        }
        $entry=@($entries | Where-Object Key -eq $choice)[0]
        if ($disconnectBlocked -and $entry.Action -in @('Category','Connect','Switch')) { throw 'Disconnect failed earlier. Close this PowerShell window and restart before further tenant work.' }
        switch ($entry.Action) {
            'Category' { Invoke-CategoryMenu -Category $entry.Category }
            'Connect' {
                $null=Select-ToolkitConnectionProfile
            }
            'Switch' {
                $domain=([string](Read-Host 'New tenant domain or ID (blank to cancel)')).Trim()
                if ($domain) {
                    $info=Get-M365TenantInfo
                    $oldTenant=if ($info) { $info.TenantName } else { 'current service sessions' }
                    if ((Read-Host "Disconnect from $oldTenant and select tenant '$domain'? [y/N]") -match '^(?i)y(es)?$') {
                        try { Disconnect-M365 -Service All }
                        catch { $disconnectBlocked=$true; throw }
                        $script:ToolkitProfilePrepared=$false
                        $script:ToolkitPreferredTenant=$domain
                        $null=Initialize-ToolkitConnectionProfile -Mode $script:ToolkitConnectionMode -TargetTenant $domain
                    }
                }
            }
            'Disconnect' {
                $info=Get-M365TenantInfo
                $target=if ($info) { $info.TenantName+' ('+$info.InitialDomain+')' } else { 'any remaining toolkit service sessions' }
                if ((Read-Host "Disconnect from ${target}? [y/N]") -match '^(?i)y(es)?$') {
                    try { Disconnect-M365 -Service All; $script:ToolkitProfilePrepared=$false }
                    catch { $disconnectBlocked=$true; throw }
                }
            }
            'Status' { Show-M365ConnectionStatus }
            'Tools' { Invoke-ToolkitToolsMenu }
        }
    }
    catch { Write-M365Log -Message $_.Exception.Message -Level Error; Wait-M365KeyPress }
}
