# Getting Started

## 1. Prerequisites

- Windows 10 or Windows 11.
- A **Global Administrator** account in each customer tenant you manage.
- Internet access to the PowerShell Gallery (for the first module install).
- PowerShell 7.6 or later. If you don't have it, the launcher offers to install it with WinGet.

## 2. Get the toolkit

**With Git (recommended):**

```powershell
cd $HOME\Documents
git clone https://github.com/<your-account>/M365-Admin-Toolkit.git
cd M365-Admin-Toolkit
```

**From a ZIP download:** extract it, then unblock the files. Windows marks downloaded scripts
as coming from the internet.

```powershell
Get-ChildItem -Path .\M365-Admin-Toolkit -Recurse | Unblock-File
```

## 3. Execution policy (one time)

Allow locally created scripts to run for your user account:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## 4. Launch

From PowerShell 7 or Windows PowerShell:

```powershell
.\Start-M365Toolkit.ps1
```

On startup the launcher:

1. **Checks the PowerShell version.** If you started it in Windows PowerShell 5.1, it finds
   PowerShell 7 and relaunches in a new window. If PowerShell 7.6+ isn't installed, it
   offers to install or update it with WinGet, then relaunches.
2. **Checks modules.** Missing or outdated modules are listed and you're asked before
   anything is installed. Modules install for **your user only** (no admin rights needed).
3. **Shows the main menu.**

Optional launch parameters:

```powershell
.\Start-M365Toolkit.ps1 -TenantDomain contoso.onmicrosoft.com   # connect immediately
.\Start-M365Toolkit.ps1 -SkipDependencyCheck                    # faster startup
.\Start-M365Toolkit.ps1 -UseDeviceCode                          # device code sign-in
```

## 5. Connect to a tenant

1. Choose **[7] Connect to Microsoft 365**.
2. Enter **any verified domain** of the customer tenant (`contoso.com` or
   `contoso.onmicrosoft.com`) or its tenant ID.
3. Choose the services you need:
   - **Graph only:** users, groups, licenses, reports
   - **Graph + Exchange Online:** adds mailboxes, inbox rules, message trace
   - **Graph + Exchange + SharePoint:** adds sites and OneDrive (PnP)
4. Sign in with the tenant's **Global Administrator** account.

The toolkit then verifies:

- the organization you signed into owns the domain you typed
- your account is a member, not a guest, of that tenant
- Exchange Online (and SharePoint) are connected to the same tenant ID

If any check fails, the toolkit disconnects and tells you why.

### First connection to a new tenant: consent

- **Microsoft Graph:** the first time you sign in to a tenant, Microsoft asks you to
  consent to the "Microsoft Graph Command Line Tools" app (Microsoft's own app, not a
  custom registration) for the permissions requested. Scripts request extra permissions
  only when they need them.
- **SharePoint (PnP):** PnP.PowerShell requires an app registration in each tenant.
  When you connect SharePoint, the toolkit:
  1. tests the client ID saved on this computer for that tenant, if any
  2. lists existing PnP / SharePoint app registrations for you to pick from
  3. offers to create one ("M365 Admin Toolkit (PnP)"), after you confirm

  Apps created by your earlier OneDrive archive script are detected and can be reused.

### Windows 10

On Windows 10 the toolkit uses **device code sign-in** for Graph by default. A browser
opens to `https://microsoft.com/devicelogin`; enter the code shown in the console. If the
normal sign-in fails on any Windows version, the toolkit falls back to device code sign-in
automatically.

## 6. Switch tenants

Choose **[8] Switch Tenant**. The toolkit confirms, disconnects every service, verifies
nothing is still connected, then connects to the new tenant with full verification.
If anything can't be disconnected, it stops and asks you to restart PowerShell rather
than risk working in the wrong tenant.

## 7. Connection status

**[9] Connection Status** shows the tenant name, ID and domains, the signed-in account,
each service's state (flagging any service connected to the wrong tenant), the Graph
permissions granted this session, and the current log file.

## 8. Logs and output

| Type | Location |
|---|---|
| Logs | `%LOCALAPPDATA%\M365AdminToolkit\Logs\<date>_<tenant>.log` |
| Reports | `%LOCALAPPDATA%\M365AdminToolkit\Reports\<tenant>\` |
| Exports | `%LOCALAPPDATA%\M365AdminToolkit\Exports\<tenant>\` |
| Backups | `%LOCALAPPDATA%\M365AdminToolkit\Backups\<tenant>\` |

**[L]** in the main menu opens the log folder. Logs older than 30 days are removed at startup.

## 9. Customizing settings

Don't edit `Config\Toolkit.Settings.psd1` for personal preferences. Instead, create
`Config\Toolkit.Settings.local.psd1` (git-ignored) with only the keys you want to change:

```powershell
@{
    Authentication = @{ UseDeviceCode = $true }
    Logging        = @{ RetentionDays = 90 }
}
```

## 10. Testing the foundation

### Offline tests (no tenant needed)

```powershell
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path .\Tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

### Live checklist (use a test or low-risk tenant first)

| # | Test | Expected |
|---|---|---|
| 1 | Run the launcher from **Windows PowerShell 5.1** | Relaunches in PowerShell 7 |
| 2 | Startup with modules missing | Module table shown; installs only after you answer Y |
| 3 | **[D]** after install | All required modules show `OK` |
| 4 | **[7]** with an invalid value (`contoso`) | "not a valid domain" message, no sign-in |
| 5 | **[7]** with tenant A domain, Graph only | Banner shows tenant A name and initial domain |
| 6 | **[9]** | Graph connected, tenant details correct |
| 7 | **[7]** again, choose Graph + Exchange | Exchange connects without asking for the tenant again |
| 8 | **[7]**, type tenant B's domain but sign in with tenant A's account | "Tenant verification failed", disconnected |
| 9 | **[8]** switch to tenant B | Tenant A disconnected; banner shows tenant B |
| 10 | **[7]**, Graph + Exchange + SharePoint | Saved/existing PnP app offered, or creation offered after confirmation |
| 11 | **[1]** User Management | Items show "not yet available" |
| 12 | **[0]** Exit, answer Y | All services disconnected |
| 13 | **[L]** | Log folder opens; log file is named for the tenant |

### Using the core from a plain PowerShell 7 console

```powershell
Import-Module .\Modules\M365Toolkit.Core\M365Toolkit.Core.psd1
Connect-M365 -TenantDomain contoso.onmicrosoft.com -Service Graph, ExchangeOnline
Get-M365TenantInfo
Get-M365ConnectionStatus | Format-Table
Disconnect-M365
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| "cannot be loaded because running scripts is disabled" | Step 3 (execution policy), and `Unblock-File` for ZIP downloads |
| Graph sign-in window doesn't appear | Use `-UseDeviceCode`, or set `Authentication.UseDeviceCode = $true` in a local settings file |
| Exchange sign-in fails right after Graph connects | Set `Authentication.ExchangeDisableWAM = $true` in a local settings file |
| "already loaded in this session" after module updates | Close PowerShell and start the toolkit again |
| Graph modules show `VersionMismatch` | Run **[D]** and accept the update so all Graph modules share one version |
| SharePoint app "cannot be used" | Choose another app or create a new one; new apps can take a minute to replicate |

## Publishing your copy to GitHub

1. Create an **empty** repository named `M365-Admin-Toolkit` on GitHub (no README,
   .gitignore or license, since the toolkit already has them).
2. In the toolkit folder:

```powershell
git init -b main
git add .
git commit -m "Initial commit: M365-Admin-Toolkit 0.1.0 foundation"
git remote add origin https://github.com/<your-account>/M365-Admin-Toolkit.git
git push -u origin main
```

3. Open the **Actions** tab on GitHub. The CI workflow runs PSScriptAnalyzer and Pester on
   Windows with PowerShell 7.
4. Optional: tag the release with `git tag v0.1.0` and `git push origin v0.1.0`.
