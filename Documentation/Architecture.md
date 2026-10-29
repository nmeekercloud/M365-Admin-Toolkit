# Architecture

## Overview

```
Start-M365Toolkit.ps1  (launcher: PS7 bootstrap, menus)
        │
        ▼
M365Toolkit.Core  (shared module, imported once per session)
  ├── Connection   Connect / Disconnect / Switch / Assert / Status / TenantInfo
  ├── Providers    Graph  →  Exchange Online  →  SharePoint (PnP)
  ├── Safeguards   Confirm-M365Action, -WhatIf support, backups
  ├── Logging      Write-M365Log, per-tenant files, redaction, retention
  ├── Dependencies Test / Install
  └── UI           Header, choices, pauses
        │
        ▼
Scripts\<Category>\<Verb-Noun>.ps1  (each script imports Core and calls Assert-M365Connection)
```

### Why Core is a module

Shared code lives in a PowerShell module rather than separate dot-sourced scripts:

- **One copy of the connection logic.** Scripts don't each re-implement sign-in.
- **Private state.** The verified tenant session (`$script:M365Session`) is visible only
  inside the module. Scripts can't accidentally overwrite which tenant you're in.
- **Standalone scripts.** A script run directly imports the module and calls
  `Assert-M365Connection`, which prompts for a tenant if needed. From the launcher, the
  module is already loaded and the existing connection is reused.
- **Testable.** The module can be loaded and tested offline with Pester.
- **Versioned.** The toolkit version comes from the module manifest.

## Authentication model

| Service | Module | Sign-in | App used |
|---|---|---|---|
| Microsoft Graph | Microsoft.Graph.Authentication 2.41.1+ | Interactive (WAM/browser), device code on Windows 10 or as fallback | Microsoft's first-party "Microsoft Graph Command Line Tools" app |
| Exchange Online | ExchangeOnlineManagement 3.10.1+ | Interactive, same account as Graph | Microsoft's first-party Exchange app |
| SharePoint | PnP.PowerShell 3.x | Interactive | Tenant-specific app registration (required by PnP) |

### Connection order

Always **Graph → Exchange Online → SharePoint**. Graph establishes and verifies the tenant
identity. Connecting Graph before Exchange has also been the reliable order when both
modules share a session ([Microsoft Tech Community](https://techcommunity.microsoft.com/blog/exchange/action-required-upgrade-exchangeonlinemanagement-powershell-module-to-version-3-/4561418/replies/4561500)).
Microsoft Graph PowerShell SDK 2.41 fixed the long-running assembly clash between these
modules for delegated interactive sessions ([Office 365 for IT Pros](https://office365itpros.com/2026/10/05/microsoft-graph-powershell-sdk-fix/)).
If Exchange sign-in still fails after Graph connects, set `Authentication.ExchangeDisableWAM = $true`.

### Tenant verification

1. `Connect-MgGraph -TenantId <what you typed>` pins the sign-in authority to that tenant.
2. `GET /organization` returns the tenant ID and verified domains. The typed domain must be
   one of them (or the typed GUID must equal the tenant ID).
3. `Get-MgContext` tenant ID must equal the organization ID.
4. `GET /me` must show `userType = Member`. Guests are refused, since a guest sign-in usually
   means the wrong account was picked.
5. Exchange Online: `Get-ConnectionInformation` tenant ID must equal the Graph tenant ID.
6. SharePoint: the PnP connection uses `-Tenant <verified tenant ID>`, and site URLs passed to
   `Get-M365SharePointConnection` must belong to the tenant's SharePoint host.

Any mismatch disconnects that service immediately and throws.

### No persistent sign-in

- Graph uses `-ContextScope Process`, so tokens live only in the current PowerShell process.
- PnP `-PersistLogin` is **off** by default (`SharePoint.PersistLogin`), so a new tenant can
  never silently reuse an earlier customer's cached sign-in.
- Switching tenants disconnects all services and verifies they're disconnected before
  connecting to the next tenant.

### What is created in a customer tenant

| Item | When | Notes |
|---|---|---|
| Consent for "Microsoft Graph Command Line Tools" | First Graph sign-in per tenant | Microsoft first-party app, not a custom app registration |
| PnP app registration | First SharePoint connection, **only if** you choose to create one | Confirmation required; existing apps are offered first |

## SharePoint decision

PnP.PowerShell's shared multi-tenant app was deleted on September 9, 2024. Every tenant now
needs its own app registration ([PnP PowerShell](https://pnp.github.io/powershell/index.html)).
Microsoft's SharePoint Online Management Shell only loads in PowerShell 7 through Windows
PowerShell compatibility (`-UseWindowsPowerShell`) ([Microsoft Learn](https://learn.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online)).

The toolkit uses **PnP** with the app-discovery logic from the existing OneDrive archive
script (saved client ID → existing app → create with confirmation). Graph is used wherever
it's enough (site discovery, files, sharing).

## Version requirements

- **ExchangeOnlineManagement 3.10.1+:** Microsoft plans to enforce stricter Exchange Online
  PowerShell logon requirements on March 31, 2027, and earlier versions may fail interactive
  authentication after that ([Exchange Team](https://techcommunity.microsoft.com/blog/exchange/action-required-upgrade-exchangeonlinemanagement-powershell-module-to-version-3-/4561418)).
- **PowerShell 7.6+:** ExchangeOnlineManagement 3.10 and later uses .NET 10 dependencies and
  requires PowerShell 7.6.0 or later ([gioxx KB](https://kb.gioxx.org/news/exchange-online-graph-assembly-clash/)).
- **Microsoft Graph 2.41.1+:** includes the assembly-clash fix. Microsoft has announced Graph
  PowerShell v3 (PowerShell 7 only) for Q4 2026 ([Microsoft 365 Developer Blog](https://devblogs.microsoft.com/microsoft365dev/investing-in-a-more-reliable-microsoft-graph-powershell-experience/)).
  Minimum versions are set in `Config\Toolkit.Settings.psd1`.

## Data handling

- No tenant-specific values in the repository (enforced by a Pester test that rejects GUIDs).
- Logs, reports, exports and backups live in `%LOCALAPPDATA%\M365AdminToolkit\`, in a folder per tenant.
- Logs redact JWT access tokens and `secret=`/`password=`-style values.
- `.gitignore` excludes CSV/XLSX customer data, certificates, keys and local settings.
