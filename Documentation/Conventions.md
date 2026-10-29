# Coding Conventions

These rules apply to every file in the toolkit. New and integrated scripts start from
[`Templates/Script-Template.ps1`](../Templates/Script-Template.ps1).

## Runtime

- PowerShell **7.4+** syntax in modules and scripts (`#Requires -Version 7.4` at the top of every script).
- **Exception:** `Start-M365Toolkit.ps1` must stay parseable by Windows PowerShell 5.1 so it
  can relaunch itself. No `?:`, `??`, `&&`, `||`, `-Parallel`, or other 7-only syntax there
  (a Pester test checks this).
- Windows only.

## Naming

- File name = function or script name, `Verb-Noun.ps1`, using **approved verbs** (`Get-Verb`).
- Core public functions use the `M365` noun prefix (`Connect-M365`, `Write-M365Log`) to avoid
  clashing with Microsoft and community modules.
- Core private helpers use the `Toolkit` noun prefix (`Get-ToolkitSetting`).
- Admin scripts don't need the prefix (`Copy-GroupMemberships.ps1`) but must not reuse real
  cmdlet names (for example, use `Get-MessageTraceReport`, not `Get-MessageTrace`).
- PascalCase for functions, parameters and public properties; camelCase for local variables.

## Structure of an admin script

1. Comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`
   (Services, Scopes, Impact).
2. `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = ...)]` for anything that changes data.
3. `$ErrorActionPreference = 'Stop'`.
4. Import Core only if it isn't already loaded.
5. `Assert-M365Connection` with only the services and **least-privilege** Graph scopes needed.
6. Parameters first, `Read-Host` prompts only as a fallback, so scripts work interactively and with parameters.
7. Build the full plan **before** changing anything (read-only phase).
8. `Confirm-M365Action` showing the tenant, action and targets.
9. Back up current state to `Get-M365OutputPath -Type Backups` before changes.
10. Wrap each individual change in `$PSCmdlet.ShouldProcess()` and log it with `-Level Change`.
11. Collect per-item results; one failure must not stop the remaining items.
12. Print a summary and return result objects.

## Tenant safety

- Never hard-code tenant names, domains, GUIDs, URLs, users, groups, or file paths.
- Get tenant details from `Get-M365TenantInfo`; SharePoint URLs from the session or Graph.
- SharePoint cmdlets always use `-Connection (Get-M365SharePointConnection ...)`.
- Don't call `Connect-MgGraph`, `Connect-ExchangeOnline`, or `Connect-PnPOnline` directly in
  scripts; use `Assert-M365Connection`.

## Impact levels for Confirm-M365Action

| Impact | Use for | Confirmation |
|---|---|---|
| Low | Reversible, single object, low risk | `y` |
| Medium | Normal admin changes | `y` |
| High | Destructive, bulk, security-relevant, hard to reverse | Type the tenant's initial domain |

## Output

- `Write-Host` only for interactive UI (menus, prompts, colored status).
- Data goes to the pipeline as `[pscustomobject]`, plus CSV in `Get-M365OutputPath`.
- `Write-M365Log` for anything that should appear in the audit trail.
- Never log tokens, passwords, or secrets (redaction is a safety net, not a substitute).

## Graph calls

- Prefer specific `Microsoft.Graph.*` cmdlets, or `Invoke-MgGraphRequest` with `-OutputType PSObject`.
- Always handle paging (`@odata.nextLink`).
- Use `$select` to request only needed properties. Escape the dollar sign in double-quoted
  strings (`` "?`$select=..." ``) or use single quotes.

## Formatting and quality

- 4-space indentation, CRLF line endings for `.ps1/.psm1/.psd1` (see `.editorconfig`).
- ASCII-only source files (avoids encoding issues in Windows PowerShell 5.1 and older consoles).
- Must pass `Invoke-ScriptAnalyzer -Settings .\PSScriptAnalyzerSettings.psd1` with no findings.
- `Write-Host` and plural nouns for `*-M365Dependencies` are the only excluded rules.
- Update GitHub Releases with every change; bump the version in the module manifest.

## Git workflow

- `main` is always runnable. Work in feature branches (`feature/copy-group-memberships`).
- One script integration per pull request; CI must pass.
- Commit messages: imperative mood (`Add Copy-GroupMemberships script`).
