# Script Integration Backlog

Existing scripts received for review on 2026-10-15, with the work needed to make each one
generic and toolkit-compliant. Original scripts are **not** committed to this repository
because some contain customer-specific values.

Integration order is a suggestion, from simplest to most complex.

| # | Original script | Toolkit target | Generic today? | Effort |
|---|---|---|---|---|
| 1 | Exchange Inbox Rule Search Script.ps1 | `Scripts/Exchange/Search-InboxRules.ps1` | Yes | Small |
| 2 | Copy Entra User Groups Script.ps1 | `Scripts/Groups/Copy-GroupMemberships.ps1` | Yes | Small |
| 3 | MsGraph Script for Contact Export.ps1 | `Scripts/Reports/Export-ContactList.ps1` | No | Small |
| 4 | Bulk Add Users to List or Group.ps1 | `Scripts/Groups/Add-BulkGroupMember.ps1` | No | Medium |
| 5 | Bulk Add Sharepoint Admins.ps1 | `Scripts/SharePoint/Grant-BulkSiteAccess.ps1` | No | Medium |
| 6 | OneDrive to Sharepoint Archive Script.ps1 (4,741 lines) | `Scripts/OneDrive/Backup-OneDrive.ps1` | Mostly | Large |

## 1. Exchange Inbox Rule Search

- **Hard-coded values:** none.
- **Changes:**
  - Replace `Import-Module` / `Connect-ExchangeOnline` with `Assert-M365Connection -Service ExchangeOnline`.
  - Export results to CSV via `Get-M365OutputPath -Type Reports` (currently table output only).
  - Optional parameters: single mailbox, include non-suspicious rules, include disabled rules.
  - Read-only, so no confirmation needed.

## 2. Copy Entra User Groups

- **Hard-coded values:** none.
- **Changes:**
  - Replace `Connect-MgGraph` with `Assert-M365Connection -GraphScopes 'GroupMember.ReadWrite.All', 'User.Read.All'`.
  - Build the plan first: show the groups to add, skipping groups the target already belongs to.
  - Handle group types Graph can't change: dynamic groups, mail-enabled security groups and
    distribution lists (Exchange), and on-premises synced groups. Report them instead of
    silently showing "skipped".
  - `Confirm-M365Action`, `ShouldProcess`, per-group result objects, `-Level Change` logging.
  - Currently every error is shown as "already member or error"; report the real error.

## 3. Contact Export

- **Hard-coded values:**
  - `-TenantID "b3ccacbd-..."` (customer tenant ID)
  - `C:\Reports` output folder
- **Bug:** `"...users?$select=displayName,mail&..."` is a double-quoted string, so
  `$select` is read as an (empty) variable and the select is lost. Use `` `$select `` or single quotes.
- **Changes:** use `Assert-M365Connection -GraphScopes 'User.Read.All'`, write to
  `Get-M365OutputPath -Type Exports`, and optionally filter to enabled member accounts only.

## 4. Bulk Add Users to List or Group

- **Hard-coded values:**
  - CSV path `C:\Users\upnamesmbmc.csv`
  - distribution group `mbmcall`
- **Changes:**
  - Parameters / prompts for the CSV path and group, plus a CSV template in `Templates/CSV`.
  - Detect the group type: distribution list or mail-enabled security group uses Exchange
    (`Add-DistributionGroupMember`); Microsoft 365 or security group uses Graph.
  - Validate every row first (user exists, already a member) and show the plan.
  - Replace `$?` checks with try/catch and per-row result objects.
  - `Confirm-M365Action -Impact High` for bulk changes; export results to CSV.

## 5. Bulk Add SharePoint Admins

- **Hard-coded values:**
  - admin URL `https://humanservicececenter-admin.sharepoint.com`
  - user `mrideout@thehumanservicecenter.org`
- **Bug:** `Set-SPOUser` has no `-IsSiteCollectionMember` parameter, so the script fails on
  every site. The documented parameter is `-IsSiteCollectionAdmin` ([Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/set-spouser?view=sharepoint-ps)).
- **Changes:**
  - Switch from the SharePoint Online Management Shell (`Connect-SPOService`) to PnP through
    `Assert-M365Connection -Service SharePoint`.
  - Prompt for the user(s) and the site scope: all sites, filtered by URL or template, or from CSV.
  - Decide: site collection admin vs. member/visitor access (two modes, clearly labeled).
  - Preview the site list, `Confirm-M365Action -Impact High`, log each grant, and export results.
  - Option to exclude OneDrive sites (`-my.sharepoint.com`).

## 6. OneDrive to SharePoint Archive

Already moved into Core in v0.1.0:

- PowerShell 7 bootstrap and WinGet install → `Start-M365Toolkit.ps1`
- Windows 10 device-code sign-in and fallback → `Connect-ToolkitGraph`
- PnP app discovery (saved, existing, create) → `Private/SharePointConnection.ps1`
- SharePoint root and admin URL discovery → `Get-ToolkitSharePointRoot`
- `Ensure-Module` → `Install-M365Dependencies` / `Import-ToolkitModule`

Remaining work:

- Remove the duplicated bootstrap, connection and app sections, about 900 lines (Core handles them).
- Replace `Start-Transcript` to `ProgramData\OneDriveArchive\Logs` with `Write-M365Log`
  (an optional transcript can go to the toolkit log folder).
- Replace `Connect-PnPSite` calls with `Get-M365SharePointConnection -Url`.
- Keep the migration engine (CreateCopyJobs, merge, shortcut handling, error tracking) and
  review it section by section.
- Apps created earlier under the name "OneDrive to Sharepoint Archive Script" are detected
  automatically by the new provider (the name contains "SharePoint").
