# Reports & Auditing: three baseline tasks

Implements License Report (Order 10), User Access Report (20), Contact Export (30)
using the existing task IDs and Graph-only provider declarations on main.
All are Ready / ReadOnly / PermissionReview=Unreviewed. Ready means implemented,
not production-validated. No Exchange, SharePoint or OneDrive code is replaced.

## Standard installation

Extract this ZIP outside the repository, open 64-bit PowerShell 7 there, unblock
trusted package files, and run the direct apply command:

```powershell
Get-ChildItem -LiteralPath . -Recurse -File | Unblock-File
.\Install-Patch.ps1 -ToolkitPath 'C:\Users\meeke\OneDrive\GitHub Repos\M365-Admin-Toolkit'
```

Answer Y to the backup/apply prompt. -WhatIf remains optional. The installer checks
hashes, syntax, paths, manifest scopes and isolated fake-based helper tests before
writing, then backs up the affected existing files, copies only listed files and
checks the installed result. Full regression/live tests remain deferred.

This is an additive local file overlay, not a line-level merge or Git branch merge.
Listed existing files are replaced in full after backup; preserve any local edits
in those files first. Unrelated local scripts/settings/.git are untouched. No SDK
imports, authentication, dependency installs, Git operations or tenant calls occur
in installation. Keep editors, toolkit processes and simultaneous installers idle.

## 1. License Report

Scopes: User.Read.All, LicenseAssignment.Read.All. Supported delegated admin role
and consent are still required by Graph; a scope string alone is not authorization.

- Tenant SKU inventory: technical product/SKU name, capability status, appliesTo,
  enabled/consumed/warning/suspended/lockedOut units.
- EnabledMinusConsumed is arithmetic for user-based SKUs only, not a promise that
  the license can be assigned. No pricing/cost, purchased-price or savings claims.
- Inventory-only, all-user assignments, or selected-user assignments. The launcher
  prompts for scope; parameters support noninteractive use.
- Assignment-state rows preserve direct/group source, assigning group ID, state,
  errors, disabled plans and update time. One user/SKU can have multiple source rows;
  these are not a unique-user seat count. Missing assignment-state/source fields
  are Unknown rather than assumed Direct. Group IDs are not resolved to names here.
- Optionally include unlicensed users. Both disabled users and guests remain in the
  license scan; they are not silently excluded. Inventory is always tenant-wide,
  even when user assignment reporting is selected-user scoped.
- CSVs for inventory/assignments plus JSON coverage. Partial reads keep collected
  rows but mark Complete=false. Technical names are not translated via a web lookup.

```powershell
.\Scripts\Reports\Get-LicenseReport.ps1 -InventoryOnly
.\Scripts\Reports\Get-LicenseReport.ps1 -UserPrincipalName user@contoso.com -IncludeUnlicensed
```

## 2. User Access Report

Scopes: User.Read.All, Group.Read.All, LicenseAssignment.Read.All,
RoleManagement.Read.Directory. Role reads also require an appropriate delegated
Entra admin role. Every scope is declared up front; no mid-task consent expansion.

- Selected users only: profile, licenses/source state, direct/transitive group
  membership, owned groups and directly assigned active Entra directory roles.
- Direct and indirect membership are distinguished. If the direct query fails,
  remaining transitive results say that directness is unknown. Duplicate groups
  are deduplicated by ID. Group ownership is separate, not treated as membership.
- Cast membership queries include $count=true and ConsistencyLevel=eventual;
  results can lag recent directory changes. All owned objects are paged, but only
  groups are emitted by this baseline. Limited group metadata is flagged.
- Four CSVs: profiles, licenses, groups, directory roles; plus coverage JSON with
  per-user/per-segment status. Earlier successful sections survive another failure.
- NOT an everything-the-user-can-access report. Excludes mailbox/folder delegation,
  SharePoint/OneDrive access/links, enterprise apps/OAuth, hidden memberships needing
  additional permissions, PIM eligibility/history, group-derived directory roles,
  Azure RBAC, Intune/workload roles and effective-resource-permission evaluation.
- CollectedSegmentsComplete refers only to requested reads. IsFullEffectiveAccessAudit
  is always false. Even a successful baseline does not certify no other access.
- No fallback to broader Directory.Read.All, no extra service connection and no
  permission grants/admin elevation occur just to collect more data.

```powershell
.\Scripts\Reports\Get-UserAccessReport.ps1 -UserPrincipalName user@contoso.com -PassThru
```

## 3. Contact Export

Scope: User.Read.All. CSV is under the toolkit's tenant-scoped Exports path.

- Directory users with email; default enabled Member accounts with mail populated.
- Optional IncludeDisabled, IncludeGuests, selected UserPrincipalName and literal
  case-insensitive SearchText across display/email/department/title/company fields.
- UseUpnFallback is explicit and labeled not verified deliverable; UPN is never
  silently treated as a usable mail address. No email-address deduplication hides
  separate users sharing an address.
- Includes display/given/surname, email and source, UPN, job title, department,
  company, office, business/mobile phones, enabled/type and directory ID.
- Not personal Outlook contacts, organizational contact objects, a complete GAL,
  group export, or an Outlook-import-specific schema. No contact objects are created.
- CSV plus coverage JSON. An empty filtered export is not a failure by itself;
  failed queries are explicitly partial and retain earlier rows.

```powershell
.\Scripts\Reports\Export-ContactList.ps1
.\Scripts\Reports\Export-ContactList.ps1 -IncludeDisabled -IncludeGuests
.\Scripts\Reports\Export-ContactList.ps1 -SearchText accounting -UseUpnFallback
```

## Shared behavior

Uses Core connection assertion, logging and tenant output paths. No direct Connect-*
calls. Scripts are read-only except local report creation. No change-confirmation
prompt is needed for directory reads. CSV formula-like strings get an apostrophe
prefix; PassThru objects retain raw values. Treat exports/coverage as sensitive admin
and personal data; use your normal storage access/retention controls.

Global public-cloud Graph v1.0 only: HTTPS graph.microsoft.com port 443; disallow
userinfo/fragments and beta/foreign-host links. Every nextLink is revalidated,
tracked to detect cycles and bounded by 2,000 pages per collection. A failed/capped
read preserves partial rows with an issue instead of pretending completeness.
No automatic broad retries/SDK imports occur inside the query helper. Recover from
throttling/authorization issues and rerun the report as appropriate. Reporting is
not a point-in-time transactional snapshot; counts may drift during changes.

## Backup and recovery

%LOCALAPPDATA%\M365AdminToolkit\PatchBackups\ReportsAuditing-<unique-id>\

Before/ stores exact original file bytes. Install-Record.json tracks existing/new
files, before/after hashes and install state. The installer attempts rollback on
copy/post-check failure. Power loss/forced termination cannot run rollback; inspect
the record/backup before restoring only the listed paths. Empty created directories
may remain after an interrupted install. Hashes detect corruption, not malicious
package tampering; this package is not digitally signed.

## Validation status

Build environment does not have PowerShell. Packaging checked ZIP integrity,
manifest wiring, hashes, safe member paths and no GUID literals in non-test payload.
Actual PowerShell parsing, isolated helpers, Pester, full regression, permission
consent/admin role behavior and live Graph responses were NOT executed here.
Install-Patch.ps1 runs real parsing and isolated synthetic helper checks locally
before and after copying; that is not full end-to-end certification.

Optional later targeted tests:
Invoke-Pester -Path .\Tests\ReportsAuditing.Tests.ps1 -Output Detailed

References used for API behavior:
https://learn.microsoft.com/en-us/graph/api/subscribedsku-list
https://learn.microsoft.com/en-us/graph/api/resources/licenseassignmentstate
https://learn.microsoft.com/en-us/graph/api/user-list-transitivememberof
https://learn.microsoft.com/en-us/graph/api/user-list-ownedobjects
https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignments
