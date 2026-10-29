# Exchange Online tasks 1-2: standard-installer package

This replaces the earlier bare-overlay delivery with a complete local patch ZIP.
Always extract the package outside the repository and use its Install-Patch.ps1.
See Patch-Update-Workflow.md for the permanent packaging and operator standard.

Baseline used for the initial implementation: repository main commit
9039084d59f1238adb151c31559aa049ddb7eca9. This installer does not fetch main,
require a clean Git working tree, reset branches, or overwrite unrelated unmerged
work. It replaces only the files printed in its plan and backs up the changed
existing files, including files already copied from the initial delivery.
The scope remains Exchange menu items 1 and 2; other Exchange scripts are untouched.

## Copy Mailbox Permissions

- MailboxDelegates copies selected direct delegates ON one mailbox to another.
- UserAccess copies rights HELD BY one user to another on specified mailboxes.
- AllMailboxes is an explicit option for a tenant-wide user/shared mailbox scan.
- FullAccess, SendAs and SendOnBehalf are independently selectable.
- DelegateIdentity optionally filters delegates in MailboxDelegates mode.
- Existing target grants are skipped; other delegates remain; source grants are
  never removed. AutoMapping applies to NEW FullAccess grants only.

```powershell
.\Scripts\Exchange\Copy-MailboxPermissions.ps1 `
  -Mode MailboxDelegates -SourceIdentity source@contoso.com `
  -DestinationIdentity destination@contoso.com -Rights FullAccess,SendAs -WhatIf

.\Scripts\Exchange\Copy-MailboxPermissions.ps1 `
  -Mode UserAccess -SourceIdentity alice@contoso.com `
  -DestinationIdentity bob@contoso.com -MailboxIdentity accounts@contoso.com `
  -Rights FullAccess,SendAs,SendOnBehalf -WhatIf
```

## Shared Mailbox Management

List/view shared mailboxes; create a new shared mailbox; convert a cloud-managed
user mailbox to shared; add/remove selected direct delegates.

```powershell
.\Scripts\Exchange\Invoke-SharedMailboxManagement.ps1 -Operation List
.\Scripts\Exchange\Invoke-SharedMailboxManagement.ps1 `
  -Operation Create -Name Accounts -Alias accounts `
  -PrimarySmtpAddress accounts@contoso.com -WhatIf
.\Scripts\Exchange\Invoke-SharedMailboxManagement.ps1 `
  -Operation Convert -Identity accounts@contoso.com -WhatIf
.\Scripts\Exchange\Invoke-SharedMailboxManagement.ps1 `
  -Operation AddDelegate -Identity accounts@contoso.com `
  -DelegateIdentity alice@contoso.com -Rights FullAccess,SendAs -WhatIf
.\Scripts\Exchange\Invoke-SharedMailboxManagement.ps1 `
  -Operation RemoveDelegate -Identity accounts@contoso.com `
  -DelegateIdentity alice@contoso.com -Rights SendAs -WhatIf
```

Use your tenant's addresses; review the plan before removing -WhatIf. When launched
without parameters, the scripts prompt for the operation and input.

## Runtime safeguards and limitations

- Core provides Exchange connection assertion, tenant-aware confirmation,
  logging, and tenant-scoped report/backup locations. No Graph scopes are requested.
- Administrative changes require Confirm-M365Action and per-change ShouldProcess.
  Runtime -WhatIf makes no Exchange writes/backups, but may write local logs/reports.
- Before the first change, save a configuration JSON snapshot; creation saves an
  intent record. These are not mailbox content backups or automated tenant rollback.
- Check existing rights immediately before mutation. SendOnBehalf uses additive
  Add/Remove deltas, not a replacement list. Per-item failure reporting continues
  the batch except when a required backup cannot be written.
- Copy direct allow entries only. Exclude SELF and inherited entries; fail closed
  on unresolvable direct principals. Conflicting direct denies require manual review.
- No folder/calendar ACLs, group-derived effective access, cross-tenant rights,
  public-folder permissions, or automapping-state cloning. Read-back verification
  checks direct configuration, not client access or inherited/effective denies.
- Supported mutation mailbox types: cloud-managed UserMailbox and SharedMailbox.
  UserAccess requires two user mailboxes. Supported delegate types include user/
  shared mailboxes, mail users and mail-enabled security groups; group grants do
  not supply per-user automapping. Synchronized mutation targets are refused.
- Creating a mailbox prechecks exact accepted domains and active-recipient SMTP/
  alias collisions, not all soft-deleted/name conflicts. Exchange is authoritative.
- No mailbox deletion, license removal, sign-in blocking, password changes, or
  conversion back to regular. Conversion does not complete user offboarding.
  Review account retention, holds, archive, size and licensing separately.
- Verified / AppliedUnverified / Failed / WhatIf / Declined / Cancelled / existing
  results distinguish outcomes. AppliedUnverified requires inspection before retry;
  replication/provisioning can exceed the short read-back window. Never blindly
  recreate a mailbox because verification is delayed.
- Copy and mutation operations export CSV results; PassThru returns result objects.
  List/View are read-only and return their corresponding objects with PassThru.
- Large UserAccess scans can be slow and stop on incomplete principal resolution.
  Protect snapshots, logs and reports as administrative data.

## Validation status

The package builder verified ZIP member integrity, hashes, payload paths and
manifest consistency. PowerShell is unavailable in the build environment:
PowerShell parsing, isolated helper checks, Pester, PSScriptAnalyzer, launcher
behavior and live Exchange were NOT executed here.

Install-Patch.ps1 runs actual PowerShell parsing and isolated helper checks on
your computer during both preview and apply. Those checks do not prove full
launcher integration, all script paths or live tenant behavior. Run targeted
Pester then the full suite at separate checkpoints before a controlled tenant test.
Task descriptors say Ready (implemented), with PermissionReview=Unreviewed; this
is not certification that production runtime tests have passed.
