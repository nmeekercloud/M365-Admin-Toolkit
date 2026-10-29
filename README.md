# M365-Admin-Toolkit

A menu-driven PowerShell 7 toolkit for administering Microsoft 365 tenants: users, groups,
SharePoint, OneDrive, Exchange Online and reporting. It's built for IT professionals who
support many unrelated customer tenants.

## Design principles

- **PowerShell 7 only.** The launcher relaunches itself in `pwsh` (or installs it) when started from Windows PowerShell 5.1.
- **Microsoft modules only.** Uses Microsoft Graph PowerShell, ExchangeOnlineManagement and PnP.PowerShell. No third-party platforms or agents.
- **Interactive sign-in, nothing permanent.** You sign in with the tenant's admin account each session. Graph tokens are kept in the PowerShell process only.
- **Works across unrelated tenants.** Nothing tenant-specific is stored in the repository. The tenant comes from what you type at connect time.
- **Verified tenant, every time.** The sign-in is pinned to the tenant you enter, its verified domains are checked, guest accounts are refused, and Exchange and SharePoint are cross-checked against the same tenant ID.
- **Safeguards on every change.** Changes show the target tenant and ask for confirmation. High-impact changes require typing the tenant's domain. `-WhatIf` is supported and every change is logged.
- **Each script stands alone.** Scripts load the shared core and connect on demand, so they run from the menu or directly.

## Requirements

| Requirement | Version |
|---|---|
| Windows 10 / 11 | Windows only |
| PowerShell | 7.6.0 or later (the launcher can install it) |
| Microsoft.Graph.* modules | 2.41.1 or later |
| ExchangeOnlineManagement | 3.10.1 or later |
| PnP.PowerShell (optional, SharePoint) | 3.0.0 or later |
| Account | Global Administrator in the customer tenant |

Modules are checked at startup and installed for the current user on request (no admin rights needed).

## Quick start

You do not need Git or GitHub Desktop to use the toolkit.

### 1. Download the toolkit ZIP

1. Open the [Releases page](https://github.com/nmeekercloud/M365-Admin-Toolkit/releases).
2. Select the release you want to use. A release marked Pre-release is a beta
   intended for testing, not a production-readiness guarantee.
3. Under Assets, download the packaged toolkit ZIP attached to that release.
   Choose the toolkit package, not the automatically generated Source code ZIP
   or tar.gz downloads.

If no packaged toolkit ZIP is attached yet, the release package is not available
for this installation method. Do not substitute a patch ZIP: patches update an
existing toolkit and are not a complete installation.

### 2. Unblock and extract the ZIP

Only unblock a download after you have checked that you trust its source.

1. In File Explorer, right-click the downloaded ZIP and select Properties.
2. If an Unblock checkbox appears, select it, click Apply, and then click OK.
3. Right-click the ZIP and select Extract All.
4. Choose a folder you can easily find and extract the entire archive.
5. Open the extracted folders until you find Start-M365Toolkit.ps1 alongside
   the Config, Modules, Scripts, and Tools folders. Keep those files together.

Do not run the toolkit from inside the compressed ZIP.

### 3. Start the toolkit

Use PowerShell 7, with the minimum version listed in Requirements above. If it
is not installed, follow Microsoft's [PowerShell installation instructions](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).

1. In File Explorer, open the extracted folder containing Start-M365Toolkit.ps1.
2. Click the address bar and copy that folder's full path.
3. Open PowerShell 7 from the Windows Start menu.
4. In the first command below, replace PASTE-YOUR-EXTRACTED-FOLDER-PATH-HERE with
   the path you copied. Keep the quotation marks. Run that command, then the
   launcher command:

```powershell
Set-Location -LiteralPath "PASTE-YOUR-EXTRACTED-FOLDER-PATH-HERE"
.\Start-M365Toolkit.ps1
```

Review any prerequisite prompts before approving installations. Do not disable
organization security policies to work around a blocked script.

### 4. Connect to Microsoft 365

Use the toolkit's connection option, enter the tenant you intend to manage, and
sign in with the appropriate administrator account. Verify the displayed tenant
before running any administrative task.

For beta testing, use a dedicated test tenant rather than a production customer
tenant. A development branch does not isolate Microsoft 365 tenant operations.

Full instructions: [Documentation/Getting-Started.md](Documentation/Getting-Started.md)

## Repository layout

```
M365-Admin-Toolkit/
├── Start-M365Toolkit.ps1          # Launcher (start here)
├── Config/
│   ├── Toolkit.Settings.psd1      # Settings (no tenant data). Local overrides: *.local.psd1
│   └── Menu.psd1                  # Menu entries -> scripts
├── Modules/M365Toolkit.Core/      # Shared framework (connection, logging, safeguards, UI)
│   ├── Public/                    # Exported functions, one per file
│   └── Private/                   # Internal helpers
├── Scripts/                       # Admin scripts by category (integrated one at a time)
│   ├── Users/  Groups/  SharePoint/  OneDrive/  Exchange/  Reports/
├── Templates/                     # Script template and sample CSVs
├── Tests/                         # Pester tests (offline)
└── Documentation/
```

Logs, reports and backups are written to `%LOCALAPPDATA%\M365AdminToolkit\`, separated by tenant.
They're never written inside the repository.

## Documentation

- [Getting Started](Documentation/Getting-Started.md): install, launch, connect, test
- [Architecture](Documentation/Architecture.md): authentication, tenant verification, design decisions
- [Conventions](Documentation/Conventions.md): coding standards for toolkit scripts
- [Script Reference](Documentation/Script-Reference.md): core functions and scripts
- [Script Integration Backlog](Documentation/Script-Integration-Backlog.md): existing scripts being standardized

- [Testing Guide](Documentation/Testing/Testing-Guide.md): offline checks and safe live validation

## Status

The toolkit is under active development. Available tasks and prerequisite checks
are defined by the checked-out build. Offline tests and live tenant validation
cover different scopes; neither is a blanket production-readiness guarantee.
Use a dedicated test tenant for functional validation.

## License

[MIT](LICENSE)
