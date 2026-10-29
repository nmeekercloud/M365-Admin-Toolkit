@{
    # PSScriptAnalyzer settings for M365-Admin-Toolkit.
    # Run locally:  Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # This is an interactive console application. Colored menus, banners and
        # prompts are the user interface, so Write-Host is intentional.
        # Pipeline data (reports, objects) is always returned with Write-Output.
        'PSAvoidUsingWriteHost'

        # Install-M365Dependencies / Test-M365Dependencies intentionally use plural
        # nouns because they operate on the whole dependency set.
        'PSUseSingularNouns'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.4')
        }
    }
}
