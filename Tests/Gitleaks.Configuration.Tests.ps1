BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $config = Join-Path $root '.gitleaks.toml'
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'M365Toolkit.Core.Tests.ps1') -Raw
    $fixture = [regex]::Match($source, "\`$jwt\s*=\s*'([^']+)'").Groups[1].Value
    if (-not $fixture) { throw 'Missing JWT fixture.' }
    $scannerAvailable = [bool](Get-Command gitleaks -ErrorAction SilentlyContinue)
    function Invoke-FixtureScan {
        param([string]$RelativePath, [string]$Value, [string]$Configuration)
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = Join-Path $folder $RelativePath
        $null = New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force
        Set-Content -LiteralPath $file -Value $Value
        $report = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        & gitleaks dir $folder --config $Configuration --redact --report-format json --report-path $report 2>&1 | Out-Null
        $exit = $LASTEXITCODE
        if ($exit -notin @(0, 1) -or -not (Test-Path $report)) { throw 'Scanner execution failed.' }
        $findings = @(Get-Content -LiteralPath $report -Raw | ConvertFrom-Json | Where-Object { $_ })
        if ($exit -eq 1 -and $findings.Count -eq 0) { throw 'Scanner error without findings.' }
        return @($findings | Where-Object RuleID -eq 'jwt').Count
    }
}
Describe 'Narrow JWT fixture exception' {
    It 'retains built-in detection rules' {
        Get-Content -LiteralPath $config -Raw | Should -Match 'useDefault\s*=\s*true'
    }
    It 'ignores only the exact fixture in its test path' {
        if (-not $scannerAvailable) { Set-ItResult -Skipped -Because 'Gitleaks not installed'; return }
        Invoke-FixtureScan 'Tests/M365Toolkit.Core.Tests.ps1' $fixture $config | Should -Be 0
    }
    It 'still detects the same JWT outside the allowlisted path' {
        if (-not $scannerAvailable) { Set-ItResult -Skipped -Because 'Gitleaks not installed'; return }
        Invoke-FixtureScan 'Other.ps1' $fixture $config | Should -BeGreaterThan 0
    }
    It 'still detects a different JWT in the test path' {
        if (-not $scannerAvailable) { Set-ItResult -Skipped -Because 'Gitleaks not installed'; return }
        $changed = $fixture.Substring(0, $fixture.Length - 1) + 'V'
        Invoke-FixtureScan 'Tests/M365Toolkit.Core.Tests.ps1' $changed $config | Should -BeGreaterThan 0
    }
}
