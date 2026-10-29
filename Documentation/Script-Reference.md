# Script Reference

## Core module functions (M365Toolkit.Core)

Load outside the launcher with:

```powershell
Import-Module .\Modules\M365Toolkit.Core\M365Toolkit.Core.psd1
```

Every function has full comment-based help: `Get-Help Connect-M365 -Full`.

### Connection

| Function | Purpose |
|---|---|
| `Connect-M365 [-TenantDomain] [-Service Graph,ExchangeOnline,SharePoint] [-GraphScopes] [-UseDeviceCode] [-DisableWAM]` | Connect and verify the tenant. Adds services or scopes to the current tenant; refuses a different tenant |
| `Disconnect-M365 [-Service All\|Graph\|ExchangeOnline\|SharePoint]` | Disconnect services; `All` clears the session |
| `Switch-M365Tenant [-TenantDomain] [-Service]` | Confirm, disconnect everything, verify, connect to the new tenant |
| `Assert-M365Connection [-Service] [-GraphScopes] [-NoPrompt]` | Used by scripts: ensures the required services and scopes are connected to the verified tenant |
| `Get-M365ConnectionStatus` | Live state per service, with a `TenantMatch` flag |
| `Show-M365ConnectionStatus` | Formatted status screen (menu option 9) |
| `Get-M365TenantInfo [-Refresh]` | Tenant name, ID, domains, account, connected services |
| `Get-M365SharePointConnection [-Url]` | PnP connection for the admin center or a tenant site (rejects other tenants' URLs) |

### Safeguards

| Function | Purpose |
|---|---|
| `Confirm-M365Action -Action -Target -Impact Low\|Medium\|High [-Force]` | Shows the tenant and targets and asks for confirmation; High requires typing the tenant domain |

### Logging and output

| Function | Purpose |
|---|---|
| `Write-M365Log -Message [-Level Debug\|Info\|Success\|Change\|Warning\|Error] [-Data] [-Quiet]` | Log to file and console |
| `Get-M365LogPath [-Folder]` | Current log file or log folder |
| `Get-M365OutputPath -Type Reports\|Exports\|Backups [-FileName]` | Tenant-scoped output folder or timestamped file path |

### Dependencies

| Function | Purpose |
|---|---|
| `Test-M365Dependencies [-IncludeOptional]` | Read-only module and PowerShell version report |
| `Install-M365Dependencies [-IncludeOptional] [-CheckOnly] [-Force] [-WhatIf]` | Install or update modules for the current user after confirmation |

### Console UI and info

| Function | Purpose |
|---|---|
| `Show-M365Header [-Title] [-NoClear]` | Banner |
| `Read-M365Choice -Valid` | Validated menu input |
| `Wait-M365KeyPress` | Pause |
| `Get-M365ToolkitInfo` | Version and paths |

## Admin scripts

Scripts are added one at a time. Until a script exists, its menu entry shows "not yet available".

| Menu | Script | Services | Status |
|---|---|---|---|
| Users | `Scripts/Users/New-User.ps1` | Graph | Planned |
| Users | `Scripts/Users/Disable-User.ps1` | Graph, Exchange | Planned |
| Users | `Scripts/Users/Copy-UserAccess.ps1` | Graph, Exchange | Planned |
| Users | `Scripts/Users/Invoke-BulkUserManagement.ps1` | Graph | Planned |
| Groups | `Scripts/Groups/Copy-GroupMemberships.ps1` | Graph | Backlog #2 |
| Groups | `Scripts/Groups/Add-BulkGroupMember.ps1` | Graph, Exchange | Backlog #4 |
| Groups | `Scripts/Groups/Export-GroupMemberships.ps1` | Graph | Planned |
| SharePoint | `Scripts/SharePoint/Export-SharePointStaffAccess.ps1` | Graph, SharePoint | Planned |
| SharePoint | `Scripts/SharePoint/Copy-SitePermissions.ps1` | Graph, SharePoint | Planned |
| SharePoint | `Scripts/SharePoint/Grant-BulkSiteAccess.ps1` | Graph, SharePoint | Backlog #5 |
| OneDrive | `Scripts/OneDrive/Backup-OneDrive.ps1` | Graph, SharePoint | Backlog #6 |
| Exchange | `Scripts/Exchange/Copy-MailboxPermissions.ps1` | Exchange | Planned |
| Exchange | `Scripts/Exchange/Invoke-SharedMailboxManagement.ps1` | Exchange | Planned |
| Exchange | `Scripts/Exchange/Search-InboxRules.ps1` | Exchange | Backlog #1 |
| Exchange | `Scripts/Exchange/Get-MessageTraceReport.ps1` | Exchange | Planned |
| Reports | `Scripts/Reports/Get-LicenseReport.ps1` | Graph | Planned |
| Reports | `Scripts/Reports/Get-UserAccessReport.ps1` | Graph, Exchange | Planned |
| Reports | `Scripts/Reports/Export-ContactList.ps1` | Graph | Backlog #3 |

## Adding a script

1. Copy `Templates/Script-Template.ps1` to `Scripts/<Category>/<Verb-Noun>.ps1`.
2. Make sure the entry in `Config/Menu.psd1` matches the file name.
3. Follow [Conventions.md](Conventions.md).
4. Run PSScriptAnalyzer and Pester, update GitHub Releases, and open a pull request.
