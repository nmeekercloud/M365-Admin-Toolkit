#Requires -Version 7.4
# Definitions only. Password values are never written to toolkit log/report helpers.
function New-ToolkitTemporaryPassword {
    [CmdletBinding()]
    [OutputType([securestring])]
    param([ValidateRange(16,128)][int]$Length=24)
    $sets=@('ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghijkmnopqrstuvwxyz','23456789','!@#%*-_=+?')
    $alphabet=$sets -join ''
    $buffer=[char[]]::new($Length)
    $secret=[Security.SecureString]::new()
    try {
        for ($i=0; $i -lt $Length; $i++) {
            $pool=if ($i -lt $sets.Count) { $sets[$i] } else { $alphabet }
            $buffer[$i]=$pool[[Security.Cryptography.RandomNumberGenerator]::GetInt32($pool.Length)]
        }
        for ($i=$Length-1; $i -gt 0; $i--) {
            $j=[Security.Cryptography.RandomNumberGenerator]::GetInt32($i+1)
            $temp=$buffer[$i]; $buffer[$i]=$buffer[$j]; $buffer[$j]=$temp
        }
        foreach ($character in $buffer) { $secret.AppendChar($character) }
        $secret.MakeReadOnly()
        return $secret
    }
    catch { $secret.Dispose(); throw }
    finally { [Array]::Clear($buffer,0,$buffer.Length) }
}
function Select-ToolkitPasswordMode {
    param([securestring]$SuppliedPassword,[switch]$GeneratePassword)
    if ($GeneratePassword -and $SuppliedPassword) { throw 'Use either -GeneratePassword or -TemporaryPassword, not both.' }
    if ($SuppliedPassword) { return 'Manual' }
    if ($GeneratePassword) { return 'Generate' }
    while ($true) {
        Write-Host '[1] Generate a random password (default)  [2] Enter manually  [0] Cancel'
        $choice=([string](Read-Host 'Password option [1]')).Trim()
        switch ($choice) {
            '' { return 'Generate' }
            '1' { return 'Generate' }
            '2' { return 'Manual' }
            '0' { throw [OperationCanceledException]::new('Account creation cancelled before password generation.') }
            default { Write-Host 'Choose 1, 2, or 0.' -ForegroundColor Yellow }
        }
    }
}
function Read-ToolkitPasswordChangeChoice {
    while ($true) {
        $choice=([string](Read-Host 'Require password change at first sign-in? [Y/n]')).Trim()
        if (-not $choice -or $choice -match '^(?i)y(es)?$') { return $true }
        if ($choice -match '^(?i)n(o)?$') { return $false }
        if ($choice -eq ':cancel') { throw [OperationCanceledException]::new('Account creation cancelled.') }
        Write-Host 'Enter Y or N; Enter accepts Yes. Use :cancel to cancel.' -ForegroundColor Yellow
    }
}
function New-ToolkitPasswordMaterial {
    param([Parameter(Mandatory)][ValidateSet('Generate','Manual')][string]$Mode,[securestring]$SuppliedPassword)
    if ($Mode -eq 'Generate') {
        return [pscustomobject]@{Password=(New-ToolkitTemporaryPassword);Generated=$true;Owned=$true}
    }
    $candidate=$SuppliedPassword; $owned=$false
    while (-not $candidate -or $candidate.Length -lt 8) {
        if ($candidate) { Write-Host 'Enter at least eight characters; tenant policy may require more.' -ForegroundColor Yellow }
        if ($owned -and $candidate) { $candidate.Dispose() }
        $candidate=Read-Host 'Password (hidden; Enter cancels)' -AsSecureString
        $owned=$true
        if (-not $candidate -or $candidate.Length -eq 0) {
            if ($candidate) { $candidate.Dispose() }
            throw [OperationCanceledException]::new('Password entry cancelled.')
        }
    }
    return [pscustomobject]@{Password=$candidate;Generated=$false;Owned=$owned}
}
function Show-ToolkitGeneratedPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][securestring]$Password,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UserPrincipalName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UserId,
        [switch]$AccountCreated,
        [scriptblock]$Writer
    )
    if (-not $AccountCreated) { throw 'Generated passwords may only be revealed after confirmed account creation.' }
    if (-not $Writer) { $Writer={param($line) $Host.UI.WriteLine([string]$line)} }
    $null=& $Writer 'Generated password: record it securely now. Console recording/transcription can capture this display.'
    $null=& $Writer ('Account: '+$UserPrincipalName+' ['+$UserId+']')
    $ptr=[IntPtr]::Zero; $plain=$null
    try {
        $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        $null=& $Writer ('Password: '+$plain)
    }
    finally {
        $plain=$null
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
    $null=& $Writer 'The toolkit does not save this password in its reports, backups, or log files.'
}
