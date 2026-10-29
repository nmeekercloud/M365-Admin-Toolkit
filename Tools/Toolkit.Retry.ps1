#Requires -Version 7.4
# Definitions only. Reusable per-step recovery, not a whole-script replay wrapper.
function Read-ToolkitRecoveryChoice {
    param([string]$Step,[switch]$Optional,[switch]$CanEdit)
    while ($true) {
        $options='[R] Retry/check again'
        if ($CanEdit) { $options+='  [E] Edit this step' }
        if ($Optional) { $options+='  [S] Skip this optional step' }
        $options+='  [C] Cancel remaining work'
        Write-Host $options -ForegroundColor Yellow
        $answer=([string](Read-Host ($Step+' [C]'))).Trim().ToUpperInvariant()
        if (-not $answer -or $answer -eq 'C') { return 'Cancel' }
        if ($answer -eq 'R') { return 'Retry' }
        if ($answer -eq 'E' -and $CanEdit) { return 'Edit' }
        if ($answer -eq 'S' -and $Optional) { return 'Skip' }
        Write-Host 'Choose one of the displayed letters.' -ForegroundColor Yellow
    }
}
function Invoke-ToolkitRecoverableStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [hashtable]$Context=@{},
        [scriptblock]$Probe,
        [scriptblock]$Edit,
        [scriptblock]$Check,
        [switch]$Optional,
        [switch]$RetryValidation,
        [switch]$Sensitive
    )
    $attempts=0
    while ($true) {
        # Authentication/tenant checks are OUTSIDE the recoverable catch. They
        # must stop safely; no reconnect or privilege expansion occurs here.
        if ($Check) { $null=& $Check $Context }
        try {
            if ($Probe -and [bool](& $Probe $Context)) {
                return [pscustomobject]@{Status='Success';Value=$null;Detail='Verified already applied';Attempts=$attempts}
            }
            $attempts++
            $value=& $Action $Context
            if ($Probe -and -not [bool](& $Probe $Context)) { throw 'The change was requested but is not yet verified. Retry checks the current state before another write.' }
            return [pscustomobject]@{Status='Success';Value=$value;Detail='Completed';Attempts=$attempts}
        }
        catch {
            if ($Sensitive) { $message='This step failed; potentially sensitive request details are suppressed.' }
            else { $message=$_.Exception.Message }
            Write-Host ($Name+': '+$message) -ForegroundColor Yellow
            if ($RetryValidation -and ($message -like 'Unavailable selection:*' -or $message -like 'Not a selection number:*' -or $message -eq 'Choose 0, 1, 2 or 3.')) { continue }
            while ($true) {
                $choice=Read-ToolkitRecoveryChoice -Step $Name -Optional:$Optional -CanEdit:([bool]$Edit)
                if ($choice -eq 'Skip') { return [pscustomobject]@{Status='Skipped';Value=$null;Detail=$message;Attempts=$attempts} }
                if ($choice -eq 'Cancel') { return [pscustomobject]@{Status='Cancelled';Value=$null;Detail=$message;Attempts=$attempts} }
                if ($choice -eq 'Retry') { break }
                if ($choice -eq 'Edit') {
                    try { $changed=[bool](& $Edit $Context) }
                    catch { Write-Host ('Edit not applied: '+$_.Exception.Message) -ForegroundColor Yellow; $changed=$false }
                    if ($changed) { break }
                }
            }
        }
    }
}
function Read-ToolkitValidatedValue {
    param([string]$Prompt,[scriptblock]$Validate,[string]$InitialValue,[switch]$UseInitial,[switch]$EmptyCancels)
    $value=$InitialValue
    $read=-not $UseInitial
    while ($true) {
        if ($read) { $value=([string](Read-Host ($Prompt+' (:cancel cancels)'))).Trim() }
        if ($value -eq ':cancel' -or ($EmptyCancels -and [string]::IsNullOrWhiteSpace($value))) { throw [OperationCanceledException]::new('Input cancelled. Completed steps have not been rolled back.') }
        $reason=[string](& $Validate $value)
        if ([string]::IsNullOrWhiteSpace($reason)) { return $value }
        Write-Host $reason -ForegroundColor Yellow
        $read=$true
    }
}
function Get-ToolkitHttpStatus {
    param([System.Management.Automation.ErrorRecord]$Record)
    $sources=@($Record.Exception)
    $response=$Record.Exception.PSObject.Properties['Response']
    if ($response -and $response.Value) { $sources+=@($response.Value) }
    foreach ($source in $sources) {
        foreach ($name in @('ResponseStatusCode','StatusCode','HttpStatusCode')) {
            $property=$source.PSObject.Properties[$name]
            if ($property -and $null -ne $property.Value) {
                try { return [int]$property.Value } catch { continue }
            }
        }
    }
    return 0
}
